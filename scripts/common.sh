#!/usr/bin/env bash

# ==============================================================================
# Common utilities for devbox scripts
# Provides shared functions, colors, and configuration
# ==============================================================================

# --- Color definitions ---
INFO='\033[34m'
SUCCESS='\033[32m'
ERROR='\033[31m'
WARNING='\033[33m'
NC='\033[0m'

# --- Default configuration ---
readonly DEFAULT_USERNAME="charles"
readonly DEFAULT_USER_ID=1000
readonly DEFAULT_GROUP_ID=1000
readonly DEFAULT_SETUP_SCRIPT_URL="https://raw.githubusercontent.com/charles1614/dotfiles/refs/heads/main/dot_config/xsetup/run.sh"

# --- Logging functions ---
log_info() { echo -e "${INFO}--- $1 ---${NC}"; }
log_success() { echo -e "${SUCCESS}$1${NC}"; }
log_error() { echo -e "${ERROR}错误: $1${NC}" >&2; }
log_warning() { echo -e "${WARNING}警告: $1${NC}" >&2; }

# --- Error handling ---
error_exit() {
    log_error "$1"
    exit 1
}

# --- Validation functions ---
validate_docker() {
    if ! command -v docker &> /dev/null; then
        error_exit "未找到 Docker。请先安装 Docker。"
    fi
}

validate_sudo() {
    if [ "$(id -u)" -ne 0 ]; then
        error_exit "此脚本必须以 root 权限运行。请使用 'sudo $0'。"
    fi
}

validate_file_exists() {
    local file="$1"
    local description="${2:-文件}"
    if [ ! -f "$file" ]; then
        error_exit "未找到 $description '$file'。"
    fi
}

# --- Docker utilities ---
cleanup_container() {
    local container_name="$1"
    if [ "$(docker ps -aq -f name=${container_name})" ]; then
        log_info "检测到旧的容器，正在移除..."
        docker rm -f "${container_name}" > /dev/null 2>&1 || true
    fi
}

cleanup_image() {
    local image_name="$1"
    if [ "$(docker images -q ${image_name})" ]; then
        log_info "检测到旧的镜像，正在移除..."
        docker rmi -f "${image_name}" > /dev/null 2>&1 || true
    fi
}

# --- File utilities ---
safe_remove() {
    local path="$1"
    if [ -e "$path" ]; then
        rm -rf "$path"
        log_success "已清理: $path"
    fi
}

# --- Configuration loading ---
load_config() {
    local config_file="config.env"
    # Try to find config.env in current directory or parent directory
    if [ -f "$config_file" ]; then
        log_info "加载配置文件: $config_file"
        source "$config_file"
    elif [ -f "../$config_file" ]; then
        log_info "加载配置文件: ../$config_file"
        source "../$config_file"
    else
        log_warning "未找到配置文件 $config_file，使用默认值"
    fi
}

# --- Environment setup ---
setup_environment() {
    # Set strict error handling
    set -eo pipefail
    
    # Load configuration
    load_config
    
    # Export default values if not set
    export USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
    export USER_ID="${USER_ID:-$DEFAULT_USER_ID}"
    export GROUP_ID="${GROUP_ID:-$DEFAULT_GROUP_ID}"
    export SETUP_SCRIPT_URL="${SETUP_SCRIPT_URL:-$DEFAULT_SETUP_SCRIPT_URL}"
    export APT_PACKAGES="${APT_PACKAGES:-build-essential git curl unzip jq libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncurses5-dev libffi-dev zsh bat ripgrep fd-find}"
    export RESOURCES_DIR="${RESOURCES_DIR:-resources}"
    export SCRIPTS_DIR="${SCRIPTS_DIR:-scripts}"
    export TESTS_DIR="${TESTS_DIR:-tests}"
    export DOCKER_DIR="${DOCKER_DIR:-docker}"
    export HOME_ARCHIVE_NAME="${HOME_ARCHIVE_NAME:-${USERNAME}_home.tar.gz}"
} 