#!/usr/bin/env bash

# ==============================================================================
# 脚本功能：
#   在基础 Ubuntu 环境中，安装必要的 APT 依赖，并从 .tar.gz 压缩包中
#   恢复用户的家目录配置。
#
# 使用方法:
#   sudo ./restore_ubuntu_env.sh
# ==============================================================================

# --- 配置变量 ---
# 用户配置 (USERNAME 必须与 `scripts/prepare_online_env.sh` 中使用的用户名一致)
# UID/GID 将由系统自动分配，并通过后续的 chown 命令修复家目录权限。
readonly USERNAME="charles"

# 文件配置
readonly INPUT_ARCHIVE="resources/${USERNAME}_home.tar.gz"

# APT 依赖包列表 (从原始安装脚本中提取的核心依赖)
readonly APT_PACKAGES="build-essential git curl unzip jq libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncurses5-dev libffi-dev zsh bat ripgrep fd-find"

# --- 颜色定义 ---
readonly INFO='[34m'
readonly SUCCESS='[32m'
readonly ERROR='[31m'
readonly WARNING='[33m'
readonly NC='[0m' # No Color

# --- 函数定义 ---
info() {
    echo -e "${INFO}--- $1 ---${NC}"
}

success() {
    echo -e "${SUCCESS}$1${NC}"
}

error() {
    echo -e "${ERROR}错误: $1${NC}" >&2
    exit 1
}

warning() {
    echo -e "${WARNING}警告: $1${NC}" >&2
}

# --- 主逻辑 ---
set -eo pipefail

info "步骤 1: 环境检查"
if [ "$(id -u)" -ne 0 ]; then
    error "此脚本必须以 root 权限运行。请使用 'sudo ./restore_ubuntu_env.sh'。"
fi

if [ ! -f "${INPUT_ARCHIVE}" ]; then
    error "未找到 '${INPUT_ARCHIVE}'。请确保它存在于脚本的同级目录或正确路径。"
fi
success "环境检查通过。"

info "步骤 2: 检查并创建用户和组"
if ! getent group "${USERNAME}" &> /dev/null; then
    info "创建组 '${USERNAME}'..."
    groupadd "${USERNAME}"
else
    info "组 '${USERNAME}' 已存在。"
fi

if ! id -u "${USERNAME}" &> /dev/null; then
    info "创建用户 '${USERNAME}'..."
    useradd -m -s /bin/bash -g "${USERNAME}" "${USERNAME}"
    success "用户 '${USERNAME}' 已创建。"
else
    info "用户 '${USERNAME}' 已存在。"
    # 确保家目录存在且权限正确
    if [ ! -d "/home/${USERNAME}" ]; then
        warning "用户 '${USERNAME}' 的家目录 '/home/${USERNAME}' 不存在，正在创建..."
        mkdir -p "/home/${USERNAME}"
        chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}"
    fi
fi
success "用户和组检查完成。"

info "步骤 3: 更新 APT 软件包列表并安装依赖"
# 建议用户手动配置镜像源，这里不自动修改 sources.list
info "正在更新 APT 软件包列表..."
apt-get update || warning "APT 更新失败，可能存在网络问题或源配置不当。尝试继续安装..."

info "正在安装 APT 依赖: ${APT_PACKAGES}..."
apt-get install -y --no-install-recommends ${APT_PACKAGES} || error "APT 依赖安装失败。"

# 针对 fd-find 创建软链接
if [ -f "/usr/bin/fdfind" ] && [ ! -f "/usr/bin/fd" ]; then
    ln -sf /usr/bin/fdfind /usr/bin/fd
    success "已为 'fd-find' 创建 'fd' 软链接。"
fi
success "APT 依赖安装完成。"

info "步骤 4: 复制并还原家目录"
info "正在解压家目录归档 '${INPUT_ARCHIVE}' 到 '/home/${USERNAME}/'..."
tar -xzvf "${INPUT_ARCHIVE}" -C "/home/${USERNAME}/" --strip-components=1 || error "家目录解压失败。"
success "家目录已解压。"

info "步骤 5: 修复权限和设置默认Shell"
info "正在修复 '/home/${USERNAME}' 的权限..."
chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}" || error "权限修复失败。"

info "正在设置用户 '${USERNAME}' 的默认 Shell 为 Zsh..."
chsh -s /bin/zsh "${USERNAME}" || warning "设置默认 Shell 失败，请手动检查 Zsh 是否安装并配置正确。"
success "权限修复和默认Shell设置完成。"

echo # 添加空行
success "✅ 环境还原完成!"

info "--- 如何验证 ---"
echo "请切换到用户 '${USERNAME}' 并验证环境:"
echo -e "
  ${SUCCESS}su - ${USERNAME}${NC}
"
echo "进入后，你可以尝试以下命令来验证环境是否正常:"
echo "  - asdf --version"
echo "  - nvim --version"
echo "  - eza --version"
echo -e "
请注意，此脚本不会自动配置 PATH 或其他环境变量，这些通常在您的家目录配置中。"
