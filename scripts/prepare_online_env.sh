#!/usr/bin/env bash

# ==============================================================================
# Script: Prepare Online Environment
# Builds a Docker image with all files and programs, starts a container,
# then pauses and waits for user manual interactive initialization.
# ==============================================================================

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# --- Configuration ---
setup_environment

# Docker configuration
readonly DOCKERFILE_PREPARE="${DOCKER_DIR}/Dockerfile"
readonly IMAGE_NAME="env-for-manual-init:${USERNAME}"
readonly CONTAINER_NAME="manual_init_container_${USERNAME}"
readonly LOCAL_SETUP_SCRIPT="original_setup.sh"

# --- Cleanup function ---
cleanup() {
    log_info "清理临时下载脚本..."
    safe_remove "${LOCAL_SETUP_SCRIPT}"
}

# --- Main logic ---
trap cleanup EXIT

# Parse command line arguments
DOCKER_BUILD_OPTIONS=""
if [[ "$1" == "--no-cache" ]]; then
    log_info "已启用 --no-cache 选项，将强制重新构建镜像"
    DOCKER_BUILD_OPTIONS="--no-cache"
fi

log_info "步骤 1: 环境检查"
validate_docker
validate_file_exists "${DOCKERFILE_PREPARE}" "Dockerfile"
log_success "环境检查通过。"

log_info "步骤 2: 下载您的 setup 脚本"
if ! wget -q "${SETUP_SCRIPT_URL}" -O "${LOCAL_SETUP_SCRIPT}"; then
    error_exit "下载 setup 脚本失败: ${SETUP_SCRIPT_URL}"
fi
log_success "'${LOCAL_SETUP_SCRIPT}' 已下载。"

log_info "步骤 3: 构建"半成品"镜像 (这可能需要较长时间)"
if ! docker build --platform linux/amd64 ${DOCKER_BUILD_OPTIONS} \
    --build-arg USERNAME=${USERNAME} \
    --build-arg USER_ID=${USER_ID} \
    --build-arg GROUP_ID=${GROUP_ID} \
    --build-arg LOCAL_SETUP_SCRIPT=${LOCAL_SETUP_SCRIPT} \
    --build-arg PROFILE=${PROFILE:-extra} \
    -f "${DOCKERFILE_PREPARE}" -t "${IMAGE_NAME}" .; then
    error_exit "Docker 镜像构建失败"
fi
log_success "镜像 '${IMAGE_NAME}' 构建完成。"

log_info "步骤 4: 启动容器并等待您的手动操作"
cleanup_container "${CONTAINER_NAME}"

# Start container in background
if ! docker run -d --name "${CONTAINER_NAME}" "${IMAGE_NAME}" tail -f /dev/null; then
    error_exit "启动容器失败"
fi
log_success "容器 '${CONTAINER_NAME}' 已在后台启动。"

# --- User instructions ---
log_info "--- 插件已在构建时自动安装 ---"
echo "Zsh (zinit) 和 Neovim (lazy.nvim) 插件已在镜像构建时自动安装。"
echo
echo "如需进入容器进行额外的手动配置:"
echo -e "   ${SUCCESS}docker exec -it ${CONTAINER_NAME} /bin/zsh${NC}"
echo
echo "完成后，请执行打包脚本:"
echo -e "   ${SUCCESS}make package${NC}"
