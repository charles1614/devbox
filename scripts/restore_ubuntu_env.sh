#!/usr/bin/env bash

# ==============================================================================
# Script: Restore Ubuntu Environment
# Installs necessary APT dependencies and restores user home directory
# configuration from a .tar.gz archive on a base Ubuntu system.
# ==============================================================================

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# --- Configuration ---
setup_environment

# File configuration
readonly INPUT_ARCHIVE="${RESOURCES_DIR}/${HOME_ARCHIVE_NAME}"

# --- Main logic ---
log_info "步骤 1: 环境检查"
# validate_sudo
validate_file_exists "${INPUT_ARCHIVE}" "离线包"
log_success "环境检查通过。"

log_info "步骤 2: 检查并创建用户和组"
# Create group if it doesn't exist
if ! getent group "${USERNAME}" &> /dev/null; then
    log_info "创建组 '${USERNAME}'..."
    if ! groupadd "${USERNAME}"; then
        error_exit "创建组 '${USERNAME}' 失败"
    fi
else
    log_info "组 '${USERNAME}' 已存在。"
fi

# Create user if it doesn't exist
if ! id -u "${USERNAME}" &> /dev/null; then
    log_info "创建用户 '${USERNAME}'..."
    if ! useradd -m -s /bin/bash -g "${USERNAME}" "${USERNAME}"; then
        error_exit "创建用户 '${USERNAME}' 失败"
    fi
    log_success "用户 '${USERNAME}' 已创建。"
else
    log_info "用户 '${USERNAME}' 已存在。"
    # Ensure home directory exists with correct permissions
    if [ ! -d "/home/${USERNAME}" ]; then
        log_warning "用户 '${USERNAME}' 的家目录 '/home/${USERNAME}' 不存在，正在创建..."
        if ! mkdir -p "/home/${USERNAME}"; then
            error_exit "创建家目录失败"
        fi
        if ! chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}"; then
            error_exit "设置家目录权限失败"
        fi
    fi
fi
log_success "用户和组检查完成。"

log_info "步骤 3: 更新 APT 软件包列表并安装依赖"
# Update package list
log_info "正在更新 APT 软件包列表..."
if ! apt-get update; then
    log_warning "APT 更新失败，可能存在网络问题或源配置不当。尝试继续安装..."
fi

# Install dependencies
log_info "正在安装 APT 依赖: ${APT_PACKAGES}..."
if ! apt-get install -y --no-install-recommends ${APT_PACKAGES}; then
    error_exit "APT 依赖安装失败"
fi

# Create symlink for fd-find
if [ -f "/usr/bin/fdfind" ] && [ ! -f "/usr/bin/fd" ]; then
    if ln -sf /usr/bin/fdfind /usr/bin/fd; then
        log_success "已为 'fd-find' 创建 'fd' 软链接"
    else
        log_warning "创建 'fd' 软链接失败"
    fi
fi
log_success "APT 依赖安装完成。"

log_info "步骤 4: 复制并还原家目录"
log_info "正在解压家目录归档 '${INPUT_ARCHIVE}' 到 '/home/${USERNAME}/'..."
if ! tar -xzvf "${INPUT_ARCHIVE}" -C "/home/${USERNAME}/" --strip-components=1; then
    error_exit "家目录解压失败"
fi
log_success "家目录已解压。"

log_info "步骤 5: 修复权限和设置默认Shell"
log_info "正在修复 '/home/${USERNAME}' 的权限..."
if ! chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}"; then
    error_exit "权限修复失败"
fi

log_info "正在设置用户 '${USERNAME}' 的默认 Shell 为 Zsh..."
if ! chsh -s /bin/zsh "${USERNAME}"; then
    log_warning "设置默认 Shell 失败，请手动检查 Zsh 是否安装并配置正确"
fi
log_success "权限修复和默认Shell设置完成。"

echo
log_success "✅ 环境还原完成!"

log_info "--- 如何验证 ---"
echo "请切换到用户 '${USERNAME}' 并验证环境:"
echo -e "\n  ${SUCCESS}su - ${USERNAME}${NC}\n"
echo "进入后，你可以尝试以下命令来验证环境是否正常:"
echo "  - asdf --version"
echo "  - nvim --version"
echo "  - eza --version"
echo -e "\n请注意，此脚本不会自动配置 PATH 或其他环境变量，这些通常在您的家目录配置中。"
