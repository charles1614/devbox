#!/usr/bin/env bash

# ==============================================================================
# 脚本功能 (新版):
#   构建一个包含所有文件和程序的“半成品”环境，并启动一个容器，
#   然后暂停并等待用户手动进入容器完成交互式初始化。
# ==============================================================================

# --- 配置变量 ---
readonly USERNAME="charles"
readonly USER_ID=1000
readonly GROUP_ID=1000
readonly SETUP_SCRIPT_URL="https://raw.githubusercontent.com/charles1614/dotfiles/refs/heads/main/dot_config/xsetup/run.sh"

# Docker 和文件配置
readonly DOCKERFILE_PREPARE="docker/Dockerfile"
readonly IMAGE_NAME="env-for-manual-init:${USERNAME}"
readonly CONTAINER_NAME="manual_init_container_${USERNAME}" # 定义一个清晰的容器名
readonly LOCAL_SETUP_SCRIPT="original_setup.sh"

# --- 颜色定义 ---
readonly INFO='\033[34m'
readonly SUCCESS='\033[32m'
readonly ERROR='\033[31m'
readonly NC='\033[0m'

# --- 函数定义 ---
info() { echo -e "${INFO}--- $1 ---${NC}"; }
success() { echo -e "${SUCCESS}$1${NC}"; }
error() { echo -e "${ERROR}错误: $1${NC}" >&2; exit 1; }

cleanup() {
    info "清理临时下载脚本..."
    rm -f "${LOCAL_SETUP_SCRIPT}"
}

# --- 主逻辑 ---
set -eo pipefail
trap cleanup EXIT

# 解析命令行参数
DOCKER_BUILD_OPTIONS=""
if [[ "$1" == "--no-cache" ]]; then
    info "已启用 --no-cache 选项，将强制重新构建镜像"
    DOCKER_BUILD_OPTIONS="--no-cache"
fi

info "步骤 1: 环境检查"
if ! command -v docker &> /dev/null; then
    error "未找到 Docker。请先安装 Docker。"
fi
success "环境检查通过。"

info "步骤 2: 下载您的 setup 脚本"
# 使用 wget 替换 curl
wget -q "${SETUP_SCRIPT_URL}" -O "${LOCAL_SETUP_SCRIPT}"
success "'${LOCAL_SETUP_SCRIPT}' 已下载。"

info "步骤 3: 构建“半成品”镜像 (这可能需要较长时间)"
docker build ${DOCKER_BUILD_OPTIONS} \
    --build-arg USERNAME=${USERNAME} \
    --build-arg USER_ID=${USER_ID} \
    --build-arg GROUP_ID=${GROUP_ID} \
    --build-arg LOCAL_SETUP_SCRIPT=${LOCAL_SETUP_SCRIPT} \
    -f "${DOCKERFILE_PREPARE}" -t "${IMAGE_NAME}" .
success "镜像 '${IMAGE_NAME}' 构建完成。"

info "步骤 4: 启动容器并等待您的手动操作"
# 如果已存在同名容器，先强制删除，确保脚本可重复执行
if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
    info "检测到旧的容器，正在移除..."
    docker rm -f ${CONTAINER_NAME}
fi
# 在后台启动容器，并让它持续运行
docker run -d --name ${CONTAINER_NAME} ${IMAGE_NAME} tail -f /dev/null
success "容器 '${CONTAINER_NAME}' 已在后台启动。"
echo

# --- 指示用户进行手动操作 ---
info "--- 接下来，请您手动完成初始化 ---"
echo "1. 进入容器的交互式 Shell (请复制并执行下面的命令):"
echo -e "   ${SUCCESS}docker exec -it ${CONTAINER_NAME} /bin/zsh${NC}"
echo
echo "2. 在进入容器后，手动执行 source 命令来初始化插件:"
echo -e "   (在容器内的 zsh 提示符后输入) ${SUCCESS}source ~/.zshrc${NC}"
echo "   (这个过程可能会持续几十秒，请耐心等待它完成，直到再次出现提示符)"
echo
echo "3. 初始化完成后，输入 'exit' 退出容器:"
echo -e "   (在容器内的 zsh 提示符后输入) ${SUCCESS}exit${NC}"
echo
echo "4. 完成以上所有步骤后，请执行新的打包脚本:"
echo -e "   ${SUCCESS}./scripts/package_offline_bundle.sh${NC}"
