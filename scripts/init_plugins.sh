#!/usr/bin/env bash

# ==============================================================================
# Script: Initialize Plugins
# Automates zsh (zap) and neovim (lazy.nvim) plugin installation, bakes the
# offline manifests (treesitter parsers, mason packages) into the image, and
# verifies the result so incomplete bundles fail the build instead of failing
# lazily on an offline restore target.
# Designed to run during Docker build (no TTY, no interactive prompts).
# ==============================================================================

set -uo pipefail

# --- Colors ---
INFO='\033[34m'
SUCCESS='\033[32m'
ERROR='\033[31m'
WARNING='\033[33m'
NC='\033[0m'

log_info()    { echo -e "${INFO}[init_plugins] $1${NC}"; }
log_success() { echo -e "${SUCCESS}[init_plugins] $1${NC}"; }
log_error()   { echo -e "${ERROR}[init_plugins] $1${NC}" >&2; }
log_warning() { echo -e "${WARNING}[init_plugins] $1${NC}" >&2; }

# --- Environment ---
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
export TERM="${TERM:-xterm-256color}"
export GIT_TERMINAL_PROMPT=0  # Prevent git from hanging on auth prompts

# If GITHUB_TOKEN is available (passed as Docker build secret), configure
# authenticated git access via env vars. This avoids persisting tokens to disk
# and raises GitHub API rate limits from 60/hr to 5000/hr.
if [ -n "${GITHUB_TOKEN:-}" ]; then
    log_info "GITHUB_TOKEN detected, configuring authenticated git access..."
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0="url.https://x-access-token:${GITHUB_TOKEN}@github.com/.insteadOf"
    export GIT_CONFIG_VALUE_0="https://github.com/"
fi

WARNINGS=0
VERIFY_ERRORS=0
NVIM_CONFIG_PRESENT=0
NVIM_TIMEOUT=300   # 5 minutes per plain nvim headless pass
MASON_TIMEOUT=900  # mason package downloads
TS_TIMEOUT=1800    # treesitter parser downloads + compilation

# ------------------------------------------------------------------------------
# Offline-bundle manifests.
# The packaged home must work with NO network, so everything nvim would try to
# fetch lazily has to be baked in here and asserted by verify_nvim_bundle().
#
# TS_PARSERS: treesitter parsers compiled into the image. Keep in sync with
# `ensure_installed` in dotfiles dot_config/nvim/lua/plugins/treesitter.lua —
# that file also sets auto_install=false so an offline host never attempts a
# parser download at runtime.
# MASON_PACKAGES: mason.nvim packages. tree-sitter-cli is required by
# astrocore/nvim-treesitter (main branch); debugpy is required by the dotfiles
# mason-tool-installer config (missing packages = install-failure notification
# on every nvim start on an offline host).
# ------------------------------------------------------------------------------
TS_PARSERS="${TS_PARSERS:-bash c cpp cmake css csv diff dockerfile git_config git_rebase gitcommit gitignore go gomod gosum gowork html ini javascript jsdoc json json5 lua luadoc make markdown markdown_inline python query regex requirements rust ssh_config toml tsx typescript vim vimdoc xml yaml zsh}"
MASON_PACKAGES="${MASON_PACKAGES:-tree-sitter-cli debugpy}"
export TS_PARSERS MASON_PACKAGES

# ==============================================================================
# 1. Zsh / Zap Plugins
# ==============================================================================
install_zsh_plugins() {
    log_info "Installing zsh/zap plugins..."

    if [[ ! -f "$HOME/.zshrc" ]]; then
        log_warning "No .zshrc found, skipping zsh plugin installation"
        ((WARNINGS++))
        return
    fi

    # --- Pre-install Zap plugin manager ---
    # Zap's auto-installer (in .zshrc) moves the existing .zshrc to a backup
    # and creates a new default one. Pre-cloning Zap ensures the installer is
    # skipped, preserving the chezmoi-managed .zshrc.
    local zap_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zap"
    if [[ ! -d "$zap_dir" ]]; then
        log_info "Pre-installing Zap plugin manager..."
        if git clone --depth 1 --branch release-v1 \
            https://github.com/zap-zsh/zap.git "$zap_dir" 2>&1; then
            log_success "Zap pre-installed to $zap_dir"
        else
            log_warning "Failed to clone Zap"
            ((WARNINGS++))
        fi
    else
        log_info "Zap already installed at $zap_dir"
    fi

    # Source .zshrc in an interactive zsh subshell via stdin (zsh -is).
    # Using -i ensures zap treats this as an interactive session and fully
    # installs all plugins. TERM is set (in Environment section above) so
    # bindkey calls work.
    log_info "Sourcing .zshrc in interactive subshell..."
    if zsh -is <<'ZSH_EOF' 2>&1
source ~/.zshrc
ZSH_EOF
    then
        log_success "Zsh plugins sourced successfully"
    else
        log_warning "zsh source had non-zero exit (may be non-critical)"
        ((WARNINGS++))
    fi

    # --- Verify Zap plugins ---
    local plugin_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zap/plugins"
    if [[ -d "$plugin_dir" ]]; then
        local count
        count=$(find "$plugin_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
        log_info "Zap plugins downloaded: ${count}"
        if [[ "$count" -lt 3 ]]; then
            log_warning "Expected at least 3 zap plugins, got ${count}"
            ((WARNINGS++))
        fi
    else
        log_warning "Zap plugin directory not found at ${plugin_dir}"
        ((WARNINGS++))
    fi

    # --- Verify starship prompt ---
    if command -v starship &>/dev/null; then
        log_success "Starship prompt available: $(starship --version | head -1)"
    else
        log_warning "Starship not found in PATH"
        ((WARNINGS++))
    fi
}

# ==============================================================================
# 1b. CLI cache warmups
# ==============================================================================
# Tools whose first run wants the network get their caches baked into the
# bundle here. tealdeer (extra profile): `tldr <cmd>` on an offline host
# errors with "Page cache not found. Run 'tldr --update'" until the cache
# exists under ~/.cache/tealdeer.
warm_cli_caches() {
    if command -v tldr &>/dev/null; then
        log_info "Warming tealdeer (tldr) page cache..."
        if timeout 120 tldr --update >/dev/null 2>&1; then
            log_success "tealdeer page cache baked"
        else
            log_warning "tldr --update failed; first offline 'tldr' use will error"
            ((WARNINGS++))
        fi
    fi
}

# ==============================================================================
# 1c. Build-cache pruning (keeps the packaged archive under GitHub's asset cap)
# ==============================================================================
# GitHub Releases reject any asset >= 2 GiB, and the extra bundle crossed it.
# These directories are download/build caches: they are re-creatable, are never
# read to *run* an installed tool, and (being already-compressed archives) cost
# nearly their full size in the .tar.gz. Removing them costs an offline user
# nothing at runtime — a later `cargo install` / `npm install` would re-fetch,
# which needs network regardless.
#
# Rust's offline HTML docs (`rustup doc`) are the one judgement call: ~700 MiB
# of the toolchain. They are dropped by default to keep the bundle shippable;
# set PRUNE_RUST_DOCS=0 to keep them (bundle may then exceed the 2 GiB cap).
prune_build_caches() {
    log_info "Pruning build caches from the packaged home..."

    local -a targets=(
        "$HOME/.cargo/registry"          # crate sources+.crate cache from cargo install
        "$HOME/.cargo/.global-cache"
        "$HOME/.npm/_cacache"            # npm content-addressable download cache
        "$HOME/.npm/_logs"
        "$HOME/.cache/mise"              # mise HTTP/download cache
        "$HOME/.rustup/downloads"
        "$HOME/.rustup/tmp"
    )
    if [[ "${PRUNE_RUST_DOCS:-1}" != "0" ]]; then
        local doc_dir
        for doc_dir in "$HOME"/.rustup/toolchains/*/share/doc; do
            [[ -d "$doc_dir" ]] && targets+=("$doc_dir")
        done
    fi

    # TinyTeX ships per-architecture binaries and the mise plugin does not always
    # pick the host's: on arm64 only bin/x86_64-linux is installed, so every TeX
    # binary is unrunnable there ("cannot execute binary file") and the whole
    # ~390 MiB install is dead weight. Drop it only on a genuine arch mismatch —
    # a bundle whose TeX binaries DO match the host keeps working LaTeX.
    local tex_root expected_bin
    case "$(uname -m)" in
        x86_64)        expected_bin="x86_64-linux" ;;
        aarch64|arm64) expected_bin="aarch64-linux" ;;
        *)             expected_bin="" ;;
    esac
    for tex_root in "$HOME"/.local/share/mise/installs/tinytex/*/; do
        [[ -d "${tex_root}bin" ]] || continue
        if [[ -n "$expected_bin" && ! -d "${tex_root}bin/${expected_bin}" ]]; then
            log_warning "TinyTeX at ${tex_root} has no ${expected_bin} binaries (found: $(ls "${tex_root}bin" 2>/dev/null | tr '\n' ' ')); it cannot run on $(uname -m) — pruning."
            targets+=("${tex_root%/}")
        fi
    done

    local t freed=0 sz
    for t in "${targets[@]}"; do
        [[ -e "$t" ]] || continue
        sz=$(du -sk "$t" 2>/dev/null | cut -f1)
        if rm -rf "$t"; then
            freed=$((freed + ${sz:-0}))
        else
            log_warning "Failed to prune ${t}"
            ((WARNINGS++))
        fi
    done
    log_success "Build caches pruned: $((freed / 1024)) MiB freed from the bundle"
}

# ==============================================================================
# Prune orphaned source files left by in-place plugin updates
# ==============================================================================
# The CI build reuses a warmed layer cache and updates plugins in place with
# `Lazy! sync`. When a plugin restructures between the cached version and the
# pinned commit (nvim-treesitter / nvim-treesitter-textobjects master->main,
# AstroNvim v5->v6, mason, catppuccin, ...), files removed upstream linger as
# untracked orphans. These break nvim in several ways:
#   - a stale plugin/*.vim or autoload file is auto-sourced against a new API
#     ("Failed to source ..."),
#   - a stale lua/<name>.lua shadows the pinned lua/<name>/init.lua so
#     require() loads the old module,
#   - AstroNvim/AstroCommunity import their whole plugins/ dir, so an orphaned
#     spec (e.g. a removed vim-illuminate.lua calling nvim-treesitter's dropped
#     `has_parser`) loads as a phantom spec and errors on every buffer read.
# Removing untracked *.lua / *.vim from EVERY plugin repo restores each to its
# pinned checkout. `git clean` here respects .gitignore (no -x), so a plugin's
# intentionally-ignored generated files are preserved. The extension scope is
# deliberate: it excludes compiled parsers (*.so), generated helptags, AND
# treesitter queries (*.scm) — nvim-treesitter carries ~1000 untracked but
# *needed* .scm files, so "untracked" is NOT a safe orphan signal for queries the
# way it is for .lua/.vim modules. (Residual risk: a plugin that ships a needed,
# non-ignored, untracked .lua/.vim would lose it — none observed in practice.)
prune_plugin_orphans() {
    local lazy_dir="$HOME/.local/share/nvim/lazy"
    [ -d "$lazy_dir" ] || return 0
    local dir count total=0 removed
    for dir in "$lazy_dir"/*/; do
        [ -d "$dir/.git" ] || continue
        # Single pass: `git clean -fd` (non-quiet) both removes the untracked
        # *.lua/*.vim and prints one "Removing <path>" line per entry, which we
        # count — no separate dry-run. If git itself errors (corrupt/detached
        # checkout), warn instead of silently skipping the repo.
        if ! removed=$(git -C "$dir" clean -fd -- '*.lua' '*.vim' 2>/dev/null); then
            log_warning "git clean failed in $(basename "$dir"); orphans (if any) left in place"
            ((WARNINGS++))
            continue
        fi
        count=$(printf '%s' "$removed" | grep -c 'Removing ' || true)
        if [ "$count" -gt 0 ]; then
            log_info "Pruned ${count} orphaned source file(s) from $(basename "$dir")"
            total=$((total + count))
        fi
    done
    if [ "$total" -gt 0 ]; then
        log_success "Removed ${total} orphaned plugin source file(s) for a clean checkout"
    else
        log_info "No orphaned plugin source files (checkout already clean)"
    fi
}

# ==============================================================================
# 2. Neovim / lazy.nvim Plugins
# ==============================================================================
install_nvim_plugins() {
    log_info "Installing neovim plugins..."

    # Check nvim is available
    if ! command -v nvim &>/dev/null; then
        log_warning "Neovim not found in PATH, skipping"
        ((WARNINGS++))
        return
    fi
    log_info "Neovim version: $(nvim --version | head -1)"

    # Check for AstroNvim / lazy.nvim config (only present in full/extra profiles)
    if [[ ! -f "$HOME/.config/nvim/init.lua" ]]; then
        log_info "No nvim init.lua found (mini profile?), skipping lazy.nvim setup"
        return
    fi
    NVIM_CONFIG_PRESENT=1

    # Tracks whether the settling sync (Pass 2) resolved the full plugin spec.
    # `Lazy! clean` is gated on it so an incomplete sync can't delete needed plugins.
    local sync_ok=0

    # --- Pass 1: Bootstrap lazy.nvim + install plugins ---
    # On first run, init.lua clones lazy.nvim itself, then require("lazy").setup()
    # registers all plugins. "Lazy! sync" forces a synchronous install/update.
    # Each pass is wrapped with `timeout` to prevent CI from hanging forever.
    log_info "Pass 1/5: Lazy sync (bootstrap + install)..."
    if timeout "$NVIM_TIMEOUT" nvim --headless "+Lazy! sync" +qa 2>&1; then
        log_success "Pass 1 completed"
    else
        local rc=$?
        if [ "$rc" -eq 124 ]; then
            log_warning "Pass 1 timed out after ${NVIM_TIMEOUT}s"
        else
            log_warning "Pass 1 exited non-zero (expected on first bootstrap)"
        fi
        ((WARNINGS++))
    fi

    # --- Pass 2: Second sync to settle any first-run race conditions ---
    log_info "Pass 2/5: Lazy sync (verify)..."
    if timeout "$NVIM_TIMEOUT" nvim --headless "+Lazy! sync" +qa 2>&1; then
        log_success "Pass 2 completed"
        sync_ok=1
    else
        local rc=$?
        if [ "$rc" -eq 124 ]; then
            log_warning "Pass 2 timed out after ${NVIM_TIMEOUT}s"
        else
            log_warning "Pass 2 had errors"
        fi
        ((WARNINGS++))
    fi

    # --- Prune orphaned source files before parser/tool passes ---
    # Must run after the syncs (which may have updated plugins in place) but
    # before Pass 3/4, so those nvim invocations don't source/require stale files.
    prune_plugin_orphans

    # --- Remove stale plugin repos left in a warmed build cache ---
    # `Lazy! sync` keeps every plugin still referenced by a spec, but an in-place
    # framework update (or a config change dropping a dependency) can leave whole
    # plugin repos installed yet unreferenced — e.g. AstroNvim v5 leftovers
    # (Comment.nvim, alpha-nvim, cmp-*) or a duplicate mini.nvim pulled in as a
    # dependency. Now that the orphaned specs are pruned, `Lazy! clean` drops
    # those unreferenced repos so the packaged bundle ships exactly the resolved
    # plugin set. Local-only (no network); failure is non-fatal.
    #
    # Gated on a clean Pass 2: `Lazy! clean` deletes every installed plugin not in
    # the RESOLVED spec, so if the sync did not settle (timeout/error, meaning the
    # spec may be incomplete) we skip it rather than risk removing needed plugins.
    if [ "$sync_ok" -eq 1 ]; then
        log_info "Cleaning unreferenced plugin repos (Lazy clean)..."
        if timeout "$NVIM_TIMEOUT" nvim --headless "+Lazy! clean" +qa 2>&1; then
            log_success "Lazy clean completed"
        else
            local rc=$?
            if [ "$rc" -eq 124 ]; then
                log_warning "Lazy clean timed out after ${NVIM_TIMEOUT}s"
            else
                log_warning "Lazy clean had errors (non-fatal)"
            fi
            ((WARNINGS++))
        fi
    else
        log_warning "Skipping Lazy clean: prior sync did not settle, resolved spec may be incomplete"
        ((WARNINGS++))
    fi

    # --- Pass 3: Mason packages (synchronous, via mason-registry API) ---
    # MasonToolsInstallSync proved unreliable here: its installs run async and
    # `+qa` can kill them mid-flight, shipping bundles without debugpy. This
    # installs each package directly and waits for its install handle to close.
    log_info "Pass 3/5: Mason packages (${MASON_PACKAGES})..."
    cat > /tmp/devbox_mason_ensure.lua <<'LUA'
local ok, mr = pcall(require, "mason-registry")
if not ok then
  io.stdout:write "MASON_SKIP: mason-registry not available\n"
  io.stdout:flush()
  vim.cmd "qa!"
end
pcall(function() mr.refresh() end)
local failed = false
for name in (os.getenv "MASON_PACKAGES" or ""):gmatch "%S+" do
  local okp, p = pcall(mr.get_package, name)
  if not okp then
    io.stdout:write("MASON_UNKNOWN: " .. name .. "\n")
    failed = true
  elseif p:is_installed() then
    io.stdout:write("MASON_PRESENT: " .. name .. "\n")
  else
    io.stdout:write("MASON_INSTALLING: " .. name .. "\n")
    io.stdout:flush()
    local hok, handle = pcall(function() return p:install() end)
    if hok and handle and handle.is_closed then
      vim.wait(600000, function() return handle:is_closed() end, 1000)
    else
      vim.wait(600000, function() return p:is_installed() end, 2000)
    end
    io.stdout:write((p:is_installed() and "MASON_OK: " or "MASON_FAIL: ") .. name .. "\n")
    failed = failed or not p:is_installed()
  end
  io.stdout:flush()
end
vim.cmd(failed and "cquit!" or "qa!")
LUA
    if timeout "$MASON_TIMEOUT" nvim --headless "+luafile /tmp/devbox_mason_ensure.lua" 2>&1; then
        log_success "Mason packages ensured"
    else
        local rc=$?
        if [ "$rc" -eq 124 ]; then
            log_warning "Pass 3 timed out after ${MASON_TIMEOUT}s"
        else
            log_warning "Mason package installation had errors"
        fi
        ((WARNINGS++))
    fi

    # --- Pass 4: TreeSitter parsers (synchronous, nvim-treesitter `main`) ---
    # `TSUpdateSync` no longer exists on the `main` branch that AstroNvim v6
    # pins, so the old pass silently installed nothing beyond AstroNvim's
    # startup defaults. Install the manifest explicitly and block on the async
    # task; needs the tree-sitter CLI, hence Pass 3 running first.
    log_info "Pass 4/5: TreeSitter parsers (${TS_PARSERS})..."
    cat > /tmp/devbox_ts_install.lua <<'LUA'
local ok, ts = pcall(require, "nvim-treesitter")
if not ok then
  io.stdout:write "TS_SKIP: nvim-treesitter not available\n"
  io.stdout:flush()
  vim.cmd "qa!"
end
local todo, unknown = {}, {}
local available = {}
for _, lang in ipairs(ts.get_available()) do available[lang] = true end
for lang in (os.getenv "TS_PARSERS" or ""):gmatch "%S+" do
  table.insert(available[lang] and todo or unknown, lang)
end
if #unknown > 0 then
  io.stdout:write("TS_UNKNOWN: " .. table.concat(unknown, " ") .. "\n")
end
io.stdout:flush()
if #todo == 0 then
  -- Nothing resolvable (registry unavailable?) — fail fast instead of parking
  -- on the install await until the outer timeout kills the pass.
  io.stdout:write "TS_EMPTY: no requested parsers available in registry\n"
  io.stdout:flush()
  vim.cmd "cquit!"
end
local done = false
ts.install(todo, { summary = true }):await(function() done = true end)
vim.wait(1500000, function() return done end, 1000)
local installed = {}
for _, lang in ipairs(ts.get_installed "parsers") do installed[lang] = true end
local missing = {}
for _, lang in ipairs(todo) do
  if not installed[lang] then table.insert(missing, lang) end
end
if #missing > 0 then
  io.stdout:write("TS_MISSING: " .. table.concat(missing, " ") .. "\n")
  io.stdout:flush()
  vim.cmd "cquit!"
end
io.stdout:write("TS_OK: all requested parsers installed\n")
io.stdout:flush()
vim.cmd "qa!"
LUA
    if timeout "$TS_TIMEOUT" nvim --headless "+luafile /tmp/devbox_ts_install.lua" 2>&1; then
        log_success "TreeSitter parsers installed"
    else
        local rc=$?
        if [ "$rc" -eq 124 ]; then
            log_warning "Pass 4 timed out after ${TS_TIMEOUT}s"
        else
            log_warning "TreeSitter installation had errors"
        fi
        ((WARNINGS++))
    fi

    # Verify lazy.nvim plugins were downloaded
    local lazy_dir="$HOME/.local/share/nvim/lazy"
    if [[ -d "$lazy_dir" ]]; then
        local count
        count=$(find "$lazy_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
        log_info "Lazy.nvim plugins downloaded: ${count}"
    else
        log_warning "Lazy.nvim plugin directory not found at ${lazy_dir}"
        ((WARNINGS++))
    fi
}

# ==============================================================================
# 3. Offline-bundle verification
# ==============================================================================
# The whole point of the image is offline restore, so a bundle missing baked
# artifacts is a build failure, not a warning: every missing piece here turns
# into a network fetch (and an error notification) on the offline target.
verify_nvim_bundle() {
    [[ "$NVIM_CONFIG_PRESENT" -eq 1 ]] || return 0
    log_info "Pass 5/5: verifying offline bundle completeness..."

    local parser_dir="$HOME/.local/share/nvim/site/parser"
    local mason_pkg_dir="$HOME/.local/share/nvim/mason/packages"
    local lang pkg
    for lang in ${TS_PARSERS}; do
        if [[ ! -f "${parser_dir}/${lang}.so" ]]; then
            log_error "verify: treesitter parser missing: ${lang}.so"
            ((VERIFY_ERRORS++))
        fi
    done
    for pkg in ${MASON_PACKAGES}; do
        if [[ ! -d "${mason_pkg_dir}/${pkg}" ]]; then
            log_error "verify: mason package missing: ${pkg}"
            ((VERIFY_ERRORS++))
        fi
    done
    if [[ ! -x "$HOME/.local/share/nvim/mason/bin/tree-sitter" ]]; then
        log_error "verify: tree-sitter CLI missing from mason bin"
        ((VERIFY_ERRORS++))
    fi
    if [[ ! -d "$HOME/.local/share/nvim/lazy/lazy.nvim" ]]; then
        log_error "verify: lazy.nvim missing (bootstrap would need network)"
        ((VERIFY_ERRORS++))
    fi

    if [[ "$VERIFY_ERRORS" -eq 0 ]]; then
        log_success "Offline bundle verification passed"
    fi
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    log_info "Starting automated plugin initialization..."
    echo ""

    install_zsh_plugins
    echo ""
    warm_cli_caches
    echo ""
    install_nvim_plugins
    echo ""
    # After every installer has run, so nothing repopulates the caches.
    prune_build_caches
    echo ""
    verify_nvim_bundle

    echo ""
    if [[ "$WARNINGS" -gt 0 ]]; then
        log_warning "Completed with ${WARNINGS} warning(s). Review output above."
    else
        log_success "All plugins installed successfully!"
    fi

    # Transient pass warnings don't break the build, but a bundle that FAILED
    # verification would fetch (and fail) at runtime on offline targets — that
    # is a build failure. INIT_PLUGINS_STRICT=0 restores the old soft behavior.
    if [[ "$VERIFY_ERRORS" -gt 0 ]]; then
        if [[ "${INIT_PLUGINS_STRICT:-1}" = "0" ]]; then
            log_warning "Offline bundle verification failed (${VERIFY_ERRORS} missing artifact(s)); continuing because INIT_PLUGINS_STRICT=0."
        else
            log_error "Offline bundle verification failed: ${VERIFY_ERRORS} missing artifact(s). Failing the build (set INIT_PLUGINS_STRICT=0 to bypass)."
            exit 1
        fi
    fi
    exit 0
}

main "$@"
