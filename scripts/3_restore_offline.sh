#!/usr/bin/env bash

# ==============================================================================
# 脚本功能：
#   模拟离线环境，使用基础镜像创建一个新的 Docker 容器，安装必要的
#   APT 依赖，并从 .tar.gz 压缩包中恢复用户的家目录配置。
#
# 使用方法:
#   ./2_restore_offline.sh
# ==============================================================================

# --- 配置变量 ---
# 用户配置 (必须与 1_prepare_online.sh 中的配置一致)
readonly USERNAME="charles"
readonly USER_ID=1000
readonly GROUP_ID=1000

# Docker 和文件配置
readonly DOCKERFILE_RESTORE="Dockerfile.restore"
readonly BASE_IMAGE_NAME="offline-machine-base:${USERNAME}"
readonly CONTAINER_NAME="test_offline_${USERNAME}"
readonly INPUT_ARCHIVE="resources/${USERNAME}_home.tar.gz"

# APT 依赖包列表 (从原始安装脚本中提取的核心依赖)
readonly APT_PACKAGES="build-essential git curl unzip jq libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncurses5-dev libffi-dev zsh bat ripgrep fd-find"

# --- 颜色定义 ---
readonly INFO='\033[34m'
readonly SUCCESS='\033[32m'
readonly ERROR='\033[31m'
readonly NC='\033[0m' # No Color

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

cleanup() {
    info "清理临时 Dockerfile..."
    if [ -f "${DOCKERFILE_RESTORE}" ]; then
        rm -f "${DOCKERFILE_RESTORE}"
        success "'${DOCKERFILE_RESTORE}' 已清理。"
    fi
}

# --- 主逻辑 ---
set -eo pipefail
trap cleanup EXIT

info "步骤 1: 环境检查"
if ! command -v docker &> /dev/null; then
    error "未找到 Docker。"
fi
if [ ! -f "${INPUT_ARCHIVE}" ]; then
    error "未找到 '${INPUT_ARCHIVE}'。请先成功运行 './1_prepare_online.sh' 并手动完成打包。"
fi
success "环境检查通过。"

info "步骤 2: 创建纯净的“离线”Docker环境"
cat <<EOF > "${DOCKERFILE_RESTORE}"
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
# 预先安装 ca-certificates, sudo, 和 a-certificates (用于https)
RUN apt-get update && apt-get install -y ca-certificates sudo
RUN groupadd -g ${GROUP_ID} ${USERNAME} && \
    useradd -m -s /bin/bash -u ${USER_ID} -g ${GROUP_ID} ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
EOF

docker build --no-cache -f "${DOCKERFILE_RESTORE}" -t "${BASE_IMAGE_NAME}" .
success "纯净的 '${BASE_IMAGE_NAME}' 镜像已创建。"

info "步骤 3: 启动“离线”容器"
if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
    info "发现已存在的同名容器，正在删除..."
    docker rm -f "${CONTAINER_NAME}"
    success "旧容器已删除。"
fi
docker run -d --name "${CONTAINER_NAME}" "${BASE_IMAGE_NAME}" tail -f /dev/null
success "“离线”容器 '${CONTAINER_NAME}' 已在后台启动。"

info "步骤 4: 在“离线”容器中安装 APT 依赖 (使用清华镜像源)"
readonly APT_COMMAND="\
    sed -i 's@http://archive.ubuntu.com/ubuntu/@https://mirrors.tuna.tsinghua.edu.cn/ubuntu/@g' /etc/apt/sources.list && \
    sed -i 's@http://security.ubuntu.com/ubuntu/@https://mirrors.tuna.tsinghua.edu.cn/ubuntu/@g' /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends ${APT_PACKAGES} && \
    ln -sf /usr/bin/fdfind /usr/bin/fd"
docker exec "${CONTAINER_NAME}" bash -c "${APT_COMMAND}"
success "APT 依赖安装完成。"

info "步骤 5: 复制并还原家目录"
docker cp "${INPUT_ARCHIVE}" "${CONTAINER_NAME}:/tmp/"
docker exec "${CONTAINER_NAME}" tar -xzvf "/tmp/${INPUT_ARCHIVE}" -C "/home/${USERNAME}/"
success "家目录已解压。"

info "步骤 6: 修复权限和设置默认Shell"
docker exec "${CONTAINER_NAME}" chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}"
# 关键步骤：设置恢复后的用户的默认 shell 为 zsh
docker exec "${CONTAINER_NAME}" chsh -s /bin/zsh "${USERNAME}"
success "权限修复和默认Shell设置完成。"

echo # 添加空行
success "✅ 离线还原模拟完成!"

info "--- 如何验证 ---"
echo "请执行以下命令进入容器，它将自动打开 Zsh:"
echo -e "\n  ${SUCCESS}docker exec -it -u ${USERNAME} ${CONTAINER_NAME} /bin/zsh${NC}\n"
echo "进入后，你可以尝试以下命令来验证环境是否正常:"
echo "  - asdf --version"
echo "  - nvim --version"
echo "  - eza --version"
echo -e "\n当你测试完毕后，可以运行以下命令清理环境:"
echo -e "  ${SUCCESS}docker stop ${CONTAINER_NAME}${NC}"
