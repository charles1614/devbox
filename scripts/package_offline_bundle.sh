#!/usr/bin/env bash

# ==============================================================================
# 脚本功能：
#   在用户手动完成容器内的初始化后，从此容器中提取家目录，
#   将其打包成最终的离线部署文件，并清理所有临时资源。
# ==============================================================================

# --- 配置变量 ---
readonly USERNAME="charles"
readonly CONTAINER_NAME="manual_init_container_${USERNAME}"
readonly TEMP_HOME_DIR="./${USERNAME}_home_temp"
readonly OUTPUT_ARCHIVE="resources/${USERNAME}_home.tar.gz"

# --- 颜色定义 ---
readonly INFO='\033[34m'; readonly SUCCESS='\033[32m'; readonly ERROR='\033[31m'; readonly NC='\033[0m'
info() { echo -e "${INFO}--- $1 ---${NC}"; }
success() { echo -e "${SUCCESS}$1${NC}"; }
error() { echo -e "${ERROR}错误: $1${NC}" >&2; exit 1; }

# --- 主逻辑 ---
set -e

info "步骤 1: 检查容器状态"
if [ ! "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    error "容器 '${CONTAINER_NAME}' 不在运行中。请先成功执行 'prepare_online_env.sh' 并完成所有手动操作。"
fi
success "容器状态正常。"

info "步骤 2: 从容器中提取已完全初始化的家目录"
# 如果临时目录存在，先用 sudo 删除
if [ -d "${TEMP_HOME_DIR}" ]; then
    info "检测到残留的临时目录，正在清理..."
    sudo rm -rf "${TEMP_HOME_DIR}"
fi
docker cp "${CONTAINER_NAME}:/home/${USERNAME}" "${TEMP_HOME_DIR}"
success "家目录已复制到 '${TEMP_HOME_DIR}'"

info "步骤 3: 打包并清理"
rm -f "${OUTPUT_ARCHIVE}"
info "打包需要 sudo 权限..."
sudo tar --owner=0 --group=0 -czvf "${OUTPUT_ARCHIVE}" -C "${TEMP_HOME_DIR}" .
success "已成功创建离线包: ${OUTPUT_ARCHIVE}"

info "清理需要 sudo 权限..."
sudo rm -rf "${TEMP_HOME_DIR}"
docker stop ${CONTAINER_NAME} > /dev/null
docker rm ${CONTAINER_NAME} > /dev/null
success "临时文件和容器已清理。"

echo
success "✅ 所有操作完成！"
