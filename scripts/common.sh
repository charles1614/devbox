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

# --- OS / glibc compatibility check ---
# The offline bundle is built on Ubuntu 24.04 (glibc 2.39). mise-managed
# binaries (neovim, node, eza, …) link against the build host's glibc, so
# restoring onto an older release silently produces broken tools. Refuse early.
#
# Configurable via env:
#   BUILD_UBUNTU_VERSION  Ubuntu version the bundle was built on (default: 24.04)
#   MIN_GLIBC_VERSION     Minimum glibc required on target (default: 2.39)
#   SKIP_OS_CHECK=1       Bypass the check (use at your own risk)
validate_os_compatibility() {
    if [ "${SKIP_OS_CHECK:-0}" = "1" ]; then
        log_warning "SKIP_OS_CHECK=1 — 跳过操作系统兼容性检查。"
        return 0
    fi

    local build_ubuntu="${BUILD_UBUNTU_VERSION:-24.04}"
    local required_glibc="${MIN_GLIBC_VERSION:-2.39}"

    if [ ! -r /etc/os-release ]; then
        log_warning "未找到 /etc/os-release，无法检测操作系统。继续执行..."
        return 0
    fi

    local id="" version_id="" id_like=""
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    version_id="${VERSION_ID:-}"
    id_like="${ID_LIKE:-}"

    if [ "${id}" != "ubuntu" ]; then
        if [[ "${id_like}" == *debian* ]]; then
            log_warning "当前系统是 ${id} (Debian 系)，并非 Ubuntu。APT 包名可能不一致，将继续。"
        else
            error_exit "此恢复脚本仅支持 Ubuntu/Debian 系系统 (检测到: ${id:-unknown})。请使用 SKIP_OS_CHECK=1 强制继续。"
        fi
    else
        log_info "检测到 Ubuntu ${version_id} (离线包基于 Ubuntu ${build_ubuntu} 构建)"
        case "${version_id}" in
            16.04|18.04|20.04|22.04|22.10|23.04|23.10)
                error_exit "Ubuntu ${version_id} 的 glibc 版本低于离线包要求 (≥ ${required_glibc})。mise 管理的二进制工具 (neovim, node, eza 等) 将无法运行。请使用 Ubuntu ${build_ubuntu} 或更新版本，或在该版本上重建离线包。如确认要强行继续，使用 SKIP_OS_CHECK=1。"
                ;;
            24.04|24.10|25.04|25.10|26.04|26.10)
                : # supported
                ;;
            *)
                log_warning "未识别的 Ubuntu 版本 '${version_id}'。将继续执行，但可能存在兼容性问题。"
                ;;
        esac
    fi

    # glibc version probe — independent of the distro check above so that
    # Debian / unknown derivatives still get a concrete answer.
    if ! command -v ldd &> /dev/null; then
        log_warning "未找到 ldd，无法检测 glibc 版本。跳过检查。"
        return 0
    fi

    local actual_glibc
    actual_glibc=$(ldd --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)
    if [ -z "${actual_glibc}" ]; then
        log_warning "无法解析 glibc 版本，跳过检查。"
        return 0
    fi

    if awk -v a="${actual_glibc}" -v r="${required_glibc}" 'BEGIN {
            split(a, x, "."); split(r, y, ".");
            if (x[1]+0 < y[1]+0) exit 1;
            if (x[1]+0 == y[1]+0 && x[2]+0 < y[2]+0) exit 1;
            exit 0;
        }'; then
        log_success "glibc ${actual_glibc} ≥ ${required_glibc}，兼容。"
    else
        error_exit "glibc 版本过低 (${actual_glibc} < ${required_glibc})。mise 管理的二进制工具将报 'GLIBC_X.YZ not found'。请升级系统或重建离线包。如确认要强行继续，使用 SKIP_OS_CHECK=1。"
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
    export SCRIPTS_DIR="${SCRIPTS_DIR:-scripts}"
    export TESTS_DIR="${TESTS_DIR:-tests}"
    export DOCKER_DIR="${DOCKER_DIR:-docker}"
    export ARCHIVE_FILE="${ARCHIVE_FILE:-}"
} 