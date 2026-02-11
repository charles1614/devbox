#!/usr/bin/env bash

# ==============================================================================
# Script: Initialize Plugins
# Automates zsh (zinit) and neovim (lazy.nvim) plugin installation.
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
# 1. Zsh / Zinit Plugins
# ==============================================================================
install_zsh_plugins() {
    log_info "Installing zsh/zinit plugins..."

    if [[ ! -f "$HOME/.zshrc" ]]; then
        log_warning "No .zshrc found, skipping zsh plugin installation"
        ((WARNINGS++))
        return
    fi

    # Source .zshrc in an interactive zsh subshell via stdin (zsh -is).
    # Using -i ensures zinit treats this as an interactive session and fully
    # installs all plugins. Without -i, zinit may skip or defer downloads.
    # TERM is set (in Environment section above) so bindkey calls work.
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

    # --- Verify zinit plugins ---
    local plugin_dir="$HOME/.local/share/zinit/plugins"
    if [[ -d "$plugin_dir" ]]; then
        local count
        count=$(find "$plugin_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
        log_info "Zinit plugins downloaded: ${count}"
        if [[ "$count" -lt 3 ]]; then
            log_warning "Expected at least 3 zinit plugins, got ${count}"
            ((WARNINGS++))
        fi
    else
        log_warning "Zinit plugin directory not found at ${plugin_dir}"
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
    else
        local rc=$?
        if [ "$rc" -eq 124 ]; then
            log_warning "Pass 2 timed out after ${NVIM_TIMEOUT}s"
        else
            log_warning "Pass 2 had errors"
        fi
        ((WARNINGS++))
    fi

    # --- Pass 3: TreeSitter parsers (native compilation) ---
    log_info "Pass 3/4: TreeSitter parser installation..."
    if timeout "$NVIM_TIMEOUT" nvim --headless "+TSUpdateSync" +qa 2>&1; then
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
