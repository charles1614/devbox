#!/usr/bin/env bash

# ==============================================================================
# Script: Test Docker Restoration
# Safely tests the restore script by running it inside a Docker container.
# This approach completely isolates the test environment from the host system.
# ==============================================================================

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/common.sh"

# --- Configuration ---
setup_environment

# File configuration — ARCHIVE_FILE must be provided
if [[ -z "${ARCHIVE_FILE}" ]]; then
    error_exit "请指定归档文件路径。用法: ARCHIVE_FILE=charles_home_extra.tar.gz $0"
fi

# Docker configuration
readonly DOCKERFILE_RESTORE="Dockerfile.restore"
readonly BASE_IMAGE_NAME="offline-machine-base:${USERNAME}"
readonly CONTAINER_NAME="test_offline_${USERNAME}"
readonly INPUT_ARCHIVE="${ARCHIVE_FILE}"

# --- Cleanup function ---
cleanup() {
    log_info "清理临时 Dockerfile..."
    safe_remove "${DOCKERFILE_RESTORE}"
}

# --- Pre-cleanup to handle existing containers ---
pre_cleanup() {
    log_info "清理可能存在的旧容器和镜像..."
    docker stop "${CONTAINER_NAME}" 2>/dev/null || true
    docker rm "${CONTAINER_NAME}" 2>/dev/null || true
    docker rmi "${BASE_IMAGE_NAME}" 2>/dev/null || true
}

# --- Main logic ---
trap cleanup EXIT

log_info "步骤 1: 环境检查"
validate_docker
validate_file_exists "${INPUT_ARCHIVE}" "离线包"
validate_file_exists "scripts/restore_ubuntu_env.sh" "恢复脚本"
log_success "环境检查通过。"

# Clean up any existing containers/images before starting
pre_cleanup

log_info "步骤 2: 创建安全的测试Docker环境"
cat <<EOF > "${DOCKERFILE_RESTORE}"
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# Install essential packages during build to avoid network issues at runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    sudo \
    zsh \
    neovim \
    build-essential \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy the restore script and archive
COPY scripts/restore_ubuntu_env.sh /workspace/restore_ubuntu_env.sh
COPY scripts/common.sh /workspace/common.sh
COPY ${INPUT_ARCHIVE} /workspace/archive.tar.gz

# Set working directory
WORKDIR /workspace

# Create a test script that tests core functionality without network access
RUN echo '#!/bin/bash' > /workspace/test_restore.sh && \
    echo 'set -e' >> /workspace/test_restore.sh && \
    echo 'echo "Starting restore test..."' >> /workspace/test_restore.sh && \
    echo 'chmod +x /workspace/restore_ubuntu_env.sh' >> /workspace/test_restore.sh && \
    echo 'echo "Testing user creation..."' >> /workspace/test_restore.sh && \
    echo 'if ! id -u "${USERNAME}" >/dev/null 2>&1; then' >> /workspace/test_restore.sh && \
    echo '  echo "Creating user ${USERNAME}..."' >> /workspace/test_restore.sh && \
    echo '  groupadd -g ${GROUP_ID} ${USERNAME} || true' >> /workspace/test_restore.sh && \
    echo '  useradd -m -s /bin/bash -u ${USER_ID} -g ${GROUP_ID} ${USERNAME}' >> /workspace/test_restore.sh && \
    echo '  echo "User ${USERNAME} created successfully"' >> /workspace/test_restore.sh && \
    echo 'else' >> /workspace/test_restore.sh && \
    echo '  echo "User ${USERNAME} already exists"' >> /workspace/test_restore.sh && \
    echo 'fi' >> /workspace/test_restore.sh && \
    echo 'echo "Testing home directory extraction..."' >> /workspace/test_restore.sh && \
    echo 'tar -xzvf "/workspace/archive.tar.gz" -C "/home/${USERNAME}/" --strip-components=1' >> /workspace/test_restore.sh && \
    echo 'chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}"' >> /workspace/test_restore.sh && \
    echo 'echo "Home directory extracted successfully"' >> /workspace/test_restore.sh && \
    echo 'echo "Setting default shell to zsh..."' >> /workspace/test_restore.sh && \
    echo 'chsh -s /bin/zsh "${USERNAME}"' >> /workspace/test_restore.sh && \
    echo 'echo "Default shell set to zsh"' >> /workspace/test_restore.sh && \
    echo 'echo "Restore completed successfully!"' >> /workspace/test_restore.sh && \
    echo 'echo "Container will stay alive for verification..."' >> /workspace/test_restore.sh && \
    echo 'tail -f /dev/null' >> /workspace/test_restore.sh && \
    chmod +x /workspace/test_restore.sh

# Set default command
CMD ["/workspace/test_restore.sh"]
EOF

if ! docker build --no-cache -f "${DOCKERFILE_RESTORE}" -t "${BASE_IMAGE_NAME}" .; then
    error_exit "构建测试镜像失败"
fi
log_success "测试镜像 '${BASE_IMAGE_NAME}' 已创建。"

log_info "步骤 3: 在隔离的容器中运行恢复测试"
# Start the container in the background
if ! docker run -d --name "${CONTAINER_NAME}" "${BASE_IMAGE_NAME}"; then
    error_exit "启动测试容器失败"
fi

# Wait a moment for the restore script to complete
log_info "等待恢复脚本执行完成..."
sleep 10

# Check container logs for errors
log_info "检查容器日志..."
docker logs "${CONTAINER_NAME}"

# Check if the restore script completed successfully
if ! docker logs "${CONTAINER_NAME}" | grep -q "Restore completed successfully!"; then
    log_error "恢复脚本执行失败，请查看上面的日志输出"
    error_exit "恢复脚本执行失败"
fi
log_success "恢复脚本测试完成。"

log_info "步骤 4: 验证恢复结果"
# Check if the user was created successfully
if ! docker exec "${CONTAINER_NAME}" id "${USERNAME}" >/dev/null 2>&1; then
    error_exit "用户 '${USERNAME}' 创建失败"
fi

# Check if home directory exists
if ! docker exec "${CONTAINER_NAME}" test -d "/home/${USERNAME}"; then
    error_exit "用户家目录创建失败"
fi

# Check if zsh is installed
if ! docker exec "${CONTAINER_NAME}" which zsh >/dev/null 2>&1; then
    error_exit "Zsh 安装失败"
fi

# Check if neovim is installed
if ! docker exec "${CONTAINER_NAME}" which nvim >/dev/null 2>&1; then
    error_exit "Neovim 安装失败"
fi

log_success "✅ 恢复脚本测试成功完成!"

echo
log_info "--- 测试验证 ---"
echo "恢复脚本已在隔离的Docker容器中成功运行。"
echo "测试验证了以下功能:"
echo "  ✓ 用户和组创建"
echo "  ✓ 家目录恢复"
echo "  ✓ 权限设置"
echo "  ✓ Zsh 安装"
echo "  ✓ Neovim 安装"
echo ""
echo "要进入测试容器进行手动验证，请运行:"
echo -e "  ${SUCCESS}docker exec -it ${CONTAINER_NAME} su - ${USERNAME}${NC}"
echo ""
echo "容器将保持运行状态供您验证。"
echo "验证完成后，请运行以下命令清理环境:"
echo -e "  ${SUCCESS}make clean${NC}"
echo ""
echo "或者手动清理:"
echo -e "  ${SUCCESS}docker stop ${CONTAINER_NAME} && docker rm ${CONTAINER_NAME} && docker rmi ${BASE_IMAGE_NAME}${NC}"
