#!/usr/bin/env bash

# ==============================================================================
# Script: Restore Ubuntu Environment
# Installs necessary APT dependencies and restores user home directory
# configuration from a .tar.gz archive on a base Ubuntu system.
# ==============================================================================

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ------------------------------------------------------------------------------
# Guard: this is the internal core script, not the entry point.
# The entry point restore.sh execs this with NO args and all config passed via
# env vars (ARCHIVE_FILE / CURRENT_USER / ...). If it is run directly with
# flag-style args (e.g. --file X, --current-user), those args are silently
# ignored and the run later fails with a confusing "指定归档文件路径" error.
# Catch that here and redirect to the proper usage. (Invoking with only env
# vars — as tests/test_docker_restore.sh does — passes no args, so this is a
# no-op there.)
# ------------------------------------------------------------------------------
for _arg in "$@"; do
    case "${_arg}" in
        -*)
            error_exit "restore_ubuntu_env.sh 是内部核心脚本，不解析命令行选项 (收到 '${_arg}')。
请改用入口脚本 (它会解析 --file/--current-user 等选项并按需下载)：
    sudo ./scripts/restore.sh --file <archive.tar.gz> --current-user
或直接用环境变量运行本脚本：
    sudo ARCHIVE_FILE=<archive.tar.gz> CURRENT_USER=1 ./scripts/restore_ubuntu_env.sh"
            ;;
    esac
done

# ------------------------------------------------------------------------------
# CURRENT_USER mode helpers
# By default the environment is restored to the packaged user (charles). Set
# CURRENT_USER=1 to restore into the account that invoked the script instead —
# the common "restore onto my own cloud VM user" case. Under sudo the real user
# is taken from SUDO_USER/SUDO_UID/SUDO_GID; otherwise from `id`.
# ------------------------------------------------------------------------------
resolve_current_user() {
    local name uid gid
    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
        name="${SUDO_USER}"
        uid="${SUDO_UID:-$(id -u "${name}" 2>/dev/null)}"
        gid="${SUDO_GID:-$(id -g "${name}" 2>/dev/null)}"
    elif [ "$(id -u)" -ne 0 ]; then
        name="$(id -un)"
        uid="$(id -u)"
        gid="$(id -g)"
    else
        error_exit "CURRENT_USER=1 无法确定目标用户：请通过 'sudo' 从你的普通用户账户运行，或改用显式的 USERNAME/USER_ID/GROUP_ID 配置。"
    fi
    export USERNAME="${name}"
    export USER_ID="${uid}"
    export GROUP_ID="${gid}"
}

# Guard before overwriting an EXISTING account's home (protects real users).
confirm_overwrite_home() {
    local home="/home/${USERNAME}"
    log_warning "目标用户 '${USERNAME}' 及其家目录 '${home}' 已存在。"
    log_warning "恢复会用离线包中的同名文件覆盖现有配置 (如 .bashrc/.zshrc/.config)，并把登录 Shell 改为 zsh。"
    log_warning "为防止 SSH 锁定，归档中的 .ssh 目录会被跳过，现有 SSH 密钥保持不变。"
    if [ "${ASSUME_YES:-0}" = "1" ]; then
        log_info "ASSUME_YES=1 — 跳过交互确认。"
        return 0
    fi
    if [ ! -t 0 ]; then
        error_exit "非交互式运行且未设置 ASSUME_YES=1；为避免误覆盖现有家目录已中止。确认无误后加 ASSUME_YES=1 重试。"
    fi
    local reply=""
    read -r -p "确认继续覆盖 '${home}' 吗? [y/N] " reply
    case "${reply}" in
        y|Y|yes|YES) : ;;
        *) error_exit "已取消。" ;;
    esac
}

# --- Configuration ---
setup_environment

# Optional: retarget to the invoking user (default stays charles).
case "${CURRENT_USER:-0}" in
    1|true|TRUE|yes|YES|on|ON)
        resolve_current_user
        log_info "CURRENT_USER 模式：恢复目标为当前用户 '${USERNAME}' (UID=${USER_ID}, GID=${GROUP_ID})"
        log_warning "若离线包不是为 '${USERNAME}' 构建的 (默认包为 charles)，源码编译的工具 (如 mise 的 Python) 会因内嵌的 '/home/<用户>' 绝对路径而无法运行；建议使用为 '${USERNAME}' 构建的离线包 (${USERNAME}_home_*.tar.gz)。"
        ;;
esac

# File configuration — ARCHIVE_FILE must be provided
if [[ -z "${ARCHIVE_FILE}" ]]; then
    error_exit "请指定归档文件路径。用法: ARCHIVE_FILE=charles_home_extra.tar.gz $0"
fi
readonly INPUT_ARCHIVE="${ARCHIVE_FILE}"

# --- Main logic ---
log_info "步骤 1: 环境检查"
validate_sudo
validate_file_exists "${INPUT_ARCHIVE}" "离线包"
validate_os_compatibility
log_success "环境检查通过。归档文件: ${INPUT_ARCHIVE}"

log_info "步骤 2: 检查并创建用户和组"
# Record whether the target user already existed BEFORE we create it, so we can
# guard against clobbering a real account's home (and SSH keys) at extraction.
if id -u "${USERNAME}" &> /dev/null; then
    USER_PREEXISTED=1
else
    USER_PREEXISTED=0
fi

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

# Install dependencies. Failure is NOT fatal: on offline/air-gapped hosts the
# home directory restore (the core of this script) still works — the bundle's
# tools are self-contained. We warn and continue instead of aborting.
log_info "正在安装 APT 依赖: ${APT_PACKAGES}..."
if ! apt-get install -y --no-install-recommends ${APT_PACKAGES}; then
    log_warning "APT 依赖安装失败 (离线环境或源不可用)。继续恢复家目录。"
    log_warning "联网后可手动补装: apt-get install -y --no-install-recommends ${APT_PACKAGES}"
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
# Build extraction options. When restoring into a pre-existing account, confirm
# first and skip the archive's .ssh so existing SSH keys are never overwritten.
tar_opts=(-xzvf "${INPUT_ARCHIVE}" -C "/home/${USERNAME}/" --strip-components=1)
if [ "${USER_PREEXISTED:-0}" = "1" ]; then
    confirm_overwrite_home
    tar_opts+=(--exclude='./.ssh' --exclude='./.ssh/*')
    log_info "已存在的账户：解压时跳过归档内的 .ssh 目录，保留现有 SSH 密钥。"
fi
log_info "正在解压家目录归档 '${INPUT_ARCHIVE}' 到 '/home/${USERNAME}/'..."
if ! tar "${tar_opts[@]}"; then
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
echo "  - mise --version"
echo "  - nvim --version"
echo "  - starship --version"
echo "  - eza --version"
echo -e "\n请注意，此脚本不会自动配置 PATH 或其他环境变量，这些通常在您的家目录配置中。"
