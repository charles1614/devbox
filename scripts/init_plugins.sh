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
export ASDF_DATA_DIR="${ASDF_DATA_DIR:-$HOME/.asdf}"
export PATH="$ASDF_DATA_DIR/bin:$ASDF_DATA_DIR/shims:$HOME/.local/bin:$PATH"
export TERM="${TERM:-xterm-256color}"

WARNINGS=0

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

    # Source .zshrc in a non-interactive zsh subshell.
    # - Powerlevel10k instant prompt cache won't exist on first run, so that
    #   block is harmlessly skipped.
    # - compinit is guarded by an interactive-shell check in the zshrc, so it
    #   is also skipped (fine — we only need plugin downloads here).
    # - zinit light/snippet commands clone plugins from GitHub on first source.
    # - TERM is set so terminfo-based bindkey calls don't produce empty keys.
    if zsh -c 'source ~/.zshrc' 2>&1; then
        log_success "Zsh plugins sourced successfully"
    else
        log_warning "zsh source had non-zero exit (may be non-critical)"
        ((WARNINGS++))
    fi

    # Verify zinit plugins were actually downloaded
    local plugin_dir="$HOME/.local/share/zinit/plugins"
    if [[ -d "$plugin_dir" ]]; then
        local count
        count=$(find "$plugin_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
        log_info "Zinit plugins downloaded: ${count}"
        if [[ "$count" -lt 5 ]]; then
            log_warning "Expected at least 5 zinit plugins, got ${count}"
            ((WARNINGS++))
        fi
    else
        log_warning "Zinit plugin directory not found at ${plugin_dir}"
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
    log_info "Pass 1/4: Lazy sync (bootstrap + install)..."
    if nvim --headless "+Lazy! sync" +qa 2>&1; then
        log_success "Pass 1 completed"
    else
        log_warning "Pass 1 exited non-zero (expected on first bootstrap)"
    fi

    # --- Pass 2: Second sync to settle any first-run race conditions ---
    log_info "Pass 2/4: Lazy sync (verify)..."
    if nvim --headless "+Lazy! sync" +qa 2>&1; then
        log_success "Pass 2 completed"
    else
        log_warning "Pass 2 had errors"
        ((WARNINGS++))
    fi

    # --- Pass 3: TreeSitter parsers (native compilation) ---
    log_info "Pass 3/4: TreeSitter parser installation..."
    if nvim --headless "+TSUpdateSync" +qa 2>&1; then
        log_success "TreeSitter parsers installed"
    else
        log_warning "TreeSitter installation had errors"
        ((WARNINGS++))
    fi

    # --- Pass 4: Mason tools ---
    log_info "Pass 4/4: Mason tools..."
    if nvim --headless -c "MasonToolsInstallSync" -c "qa" 2>&1; then
        log_success "Mason tools installed"
    else
        log_warning "Mason tools installation had errors"
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
