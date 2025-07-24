#!/usr/bin/env bash

# ==============================================================================
# Script: Test Docker Restoration
# Simulates offline environment restoration within a Docker container for testing.
# ==============================================================================

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/common.sh"

# --- Configuration ---
setup_environment

# Docker configuration
readonly DOCKERFILE_RESTORE="Dockerfile.restore"
readonly BASE_IMAGE_NAME="offline-machine-base:${USERNAME}"
readonly CONTAINER_NAME="test_offline_${USERNAME}"
readonly INPUT_ARCHIVE="${RESOURCES_DIR}/${HOME_ARCHIVE_NAME}"

# --- Cleanup function ---
cleanup() {
    log_info "清理临时 Dockerfile..."
    safe_remove "${DOCKERFILE_RESTORE}"
}

# --- Main logic ---
trap cleanup EXIT

log_info "步骤 1: 环境检查"
validate_docker
validate_file_exists "${INPUT_ARCHIVE}" "离线包"
log_success "环境检查通过。"

log_info "步骤 2: 创建纯净的"离线"Docker环境"
cat <<EOF > "${DOCKERFILE_RESTORE}"
ARG TARGETPLATFORM
FROM --platform=\${TARGETPLATFORM:-linux/amd64} ${DOCKER_BASE_IMAGE}
ENV DEBIAN_FRONTEND=noninteractive
# Pre-install ca-certificates and sudo
RUN apt-get update && apt-get install -y ca-certificates sudo
RUN groupadd -g ${GROUP_ID} ${USERNAME} && \\
    useradd -m -s /bin/bash -u ${USER_ID} -g ${GROUP_ID} ${USERNAME} && \\
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
EOF

if ! docker build --platform linux/amd64 --no-cache --build-arg TARGETPLATFORM=linux/amd64 -f "${DOCKERFILE_RESTORE}" -t "${BASE_IMAGE_NAME}" .; then
    error_exit "构建基础镜像失败"
fi
log_success "纯净的 '${BASE_IMAGE_NAME}' 镜像已创建。"

log_info "步骤 3: 启动"离线"容器"
cleanup_container "${CONTAINER_NAME}"

if ! docker run -d --name "${CONTAINER_NAME}" "${BASE_IMAGE_NAME}" tail -f /dev/null; then
    error_exit "启动测试容器失败"
fi
log_success ""离线"容器 '${CONTAINER_NAME}' 已在后台启动。"

log_info "步骤 4: 在"离线"容器中安装 APT 依赖 (使用清华镜像源)"
readonly APT_COMMAND="\
    apt-get update && \
    apt-get install -y --no-install-recommends ${APT_PACKAGES} && \
    ln -sf /usr/bin/fdfind /usr/bin/fd"

if ! docker exec "${CONTAINER_NAME}" bash -c "${APT_COMMAND}"; then
    error_exit "安装 APT 依赖失败"
fi
log_success "APT 依赖安装完成。"

log_info "步骤 5: 复制并还原家目录"
if ! docker cp "${INPUT_ARCHIVE}" "${CONTAINER_NAME}:/tmp/"; then
    error_exit "复制离线包到容器失败"
fi

if ! docker exec "${CONTAINER_NAME}" tar -xzvf "/tmp/${HOME_ARCHIVE_NAME}" -C "/home/${USERNAME}/"; then
    error_exit "解压家目录失败"
fi
log_success "家目录已解压。"

log_info "步骤 6: 修复权限和设置默认Shell"
if ! docker exec "${CONTAINER_NAME}" chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}"; then
    error_exit "修复权限失败"
fi

# Set default shell to zsh
if ! docker exec "${CONTAINER_NAME}" chsh -s /bin/zsh "${USERNAME}"; then
    error_exit "设置默认 Shell 失败"
fi
log_success "权限修复和默认Shell设置完成。"

echo
log_success "✅ 离线还原模拟完成!"

log_info "--- 如何验证 ---"
echo "请执行以下命令进入容器，它将自动打开 Zsh:"
echo -e "\n  ${SUCCESS}docker exec -it -u ${USERNAME} ${CONTAINER_NAME} /bin/zsh${NC}\n"
echo "进入后，你可以尝试以下命令来验证环境是否正常:"
echo "  - asdf --version"
echo "  - nvim --version"
echo "  - eza --version"
echo -e "\n当你测试完毕后，可以运行以下命令清理环境:"
echo -e "  ${SUCCESS}docker stop ${CONTAINER_NAME}${NC}"
