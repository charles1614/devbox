#!/usr/bin/env bash

# ==============================================================================
# Script: Initialize Plugins
# Automates zsh (zap) and neovim (lazy.nvim) plugin installation.
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
NVIM_TIMEOUT=300  # 5 minutes per nvim headless pass

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

    # Tracks whether the settling sync (Pass 2) resolved the full plugin spec.
    # `Lazy! clean` is gated on it so an incomplete sync can't delete needed plugins.
    local sync_ok=0

    # --- Pass 1: Bootstrap lazy.nvim + install plugins ---
    # On first run, init.lua clones lazy.nvim itself, then require("lazy").setup()
    # registers all plugins. "Lazy! sync" forces a synchronous install/update.
    # Each pass is wrapped with `timeout` to prevent CI from hanging forever.
    log_info "Pass 1/4: Lazy sync (bootstrap + install)..."
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
    log_info "Pass 2/4: Lazy sync (verify)..."
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

    # --- Pass 3: TreeSitter parsers (install ensure_installed synchronously) ---
    # nvim-treesitter's `main` branch has NO :TSUpdateSync command (only
    # TSInstall/TSUpdate, both async). Parser install is the Lua API
    # `require('nvim-treesitter').install(langs)`, which returns an awaitable we
    # :wait() on so the build blocks until parsers finish compiling. The language
    # list is AstroNvim's configured `ensure_installed`; if it can't be resolved
    # the call is a safe no-op. (The old :TSUpdateSync silently errored on `main`,
    # so parsers only ever came from the warmed cache — see the prune above.)
    log_info "Pass 3/4: TreeSitter parser installation..."
    local ts_wait_ms=$(( (NVIM_TIMEOUT - 20) * 1000 ))
    local ts_lua="local nts = require('nvim-treesitter'); local ok, core = pcall(require, 'astrocore'); local langs = (ok and vim.tbl_get(core, 'config', 'treesitter', 'ensure_installed')) or {}; if type(langs) == 'table' and #langs > 0 then nts.install(langs):wait(${ts_wait_ms}) end"
    if timeout "$NVIM_TIMEOUT" nvim --headless -c "lua ${ts_lua}" -c "qa" 2>&1; then
        log_success "TreeSitter parsers installed"
    else
        local rc=$?
        if [ "$rc" -eq 124 ]; then
            log_warning "Pass 3 timed out after ${NVIM_TIMEOUT}s"
        else
            log_warning "TreeSitter installation had errors"
        fi
        ((WARNINGS++))
    fi

    # --- Pass 4: Mason tools ---
    log_info "Pass 4/4: Mason tools..."
    if timeout "$NVIM_TIMEOUT" nvim --headless -c "MasonToolsInstallSync" -c "qa" 2>&1; then
        log_success "Mason tools installed"
    else
        local rc=$?
        if [ "$rc" -eq 124 ]; then
            log_warning "Pass 4 timed out after ${NVIM_TIMEOUT}s"
        else
            log_warning "Mason tools installation had errors"
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
# Main
# ==============================================================================
main() {
    log_info "Starting automated plugin initialization..."
    echo ""

    install_zsh_plugins
    echo ""
    install_nvim_plugins

    echo ""
    if [[ "$WARNINGS" -gt 0 ]]; then
        log_warning "Completed with ${WARNINGS} warning(s). Review output above."
    else
        log_success "All plugins installed successfully!"
    fi

    # Always exit 0 — plugin issues should not break the Docker build.
    # The image is still usable; any missing plugin will auto-install on
    # first interactive use.
    exit 0
}

main "$@"
