#!/usr/bin/env bash

# ==============================================================================
# Script: Package Offline Bundle
# Extracts the initialized home directory from the container and packages it
# into a .tar.gz archive after user manual initialization.
# ==============================================================================

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# --- Configuration ---
setup_environment

# Container and file configuration
readonly CONTAINER_NAME="manual_init_container_${USERNAME}"
readonly TEMP_HOME_DIR="./${USERNAME}_home_temp"
readonly OUTPUT_ARCHIVE="${RESOURCES_DIR}/${HOME_ARCHIVE_NAME}"

# --- Main logic ---
log_info "步骤 1: 检查容器状态"
if [ ! "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    error_exit "容器 '${CONTAINER_NAME}' 不在运行中。请先成功执行 'prepare_online_env.sh' 并完成所有手动操作。"
fi
log_success "容器状态正常。"

log_info "步骤 2: 从容器中提取已完全初始化的家目录"
# Clean up existing temp directory
safe_remove "${TEMP_HOME_DIR}"

# Extract home directory from container
if ! docker cp "${CONTAINER_NAME}:/home/${USERNAME}" "${TEMP_HOME_DIR}"; then
    error_exit "从容器中复制家目录失败"
fi
log_success "家目录已复制到 '${TEMP_HOME_DIR}'"

log_info "步骤 3: 打包并清理"
# Ensure resources directory exists
mkdir -p "${RESOURCES_DIR}"

# Remove existing archive
safe_remove "${OUTPUT_ARCHIVE}"

log_info "正在打包家目录..."
if ! tar --owner=0 --group=0 -czvf "${OUTPUT_ARCHIVE}" -C "${TEMP_HOME_DIR}" .; then
    error_exit "打包家目录失败"
fi
log_success "已成功创建离线包: ${OUTPUT_ARCHIVE}"

log_info "正在清理临时文件和容器..."
safe_remove "${TEMP_HOME_DIR}"

# Stop and remove container
if docker stop "${CONTAINER_NAME}" > /dev/null 2>&1; then
    log_success "容器已停止"
fi
if docker rm "${CONTAINER_NAME}" > /dev/null 2>&1; then
    log_success "容器已删除"
fi

echo
log_success "✅ 所有操作完成！"
