#!/usr/bin/env bash

# ==============================================================================
# Script: Test Docker Restoration
# Runs the REAL restore script (scripts/restore_ubuntu_env.sh) inside an
# isolated Ubuntu 24.04 container — the same OS the bundle is built on — so
# the test exercises exactly what runs on a target host.
#
# Env:
#   ARCHIVE_FILE=<tar.gz>   Offline bundle to test (required)
#   RESTORE_TIMEOUT=<sec>   Max seconds to wait for the in-container restore
#                           (default: 900 — APT install needs network time)
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
readonly RESTORE_TIMEOUT="${RESTORE_TIMEOUT:-900}"
readonly SUCCESS_MARKER="RESTORE_TEST_OK"

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

log_info "步骤 2: 创建测试镜像 (Ubuntu 24.04 — 与离线包构建环境一致)"
cat <<EOF > "${DOCKERFILE_RESTORE}"
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# Only ca-certificates — the restore script installs everything else itself;
# that installation path is part of what this test verifies.
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \\
    && rm -rf /var/lib/apt/lists/*

COPY scripts/restore_ubuntu_env.sh scripts/common.sh /workspace/scripts/
COPY ${INPUT_ARCHIVE} /workspace/archive.tar.gz
WORKDIR /workspace

# Run the real restore script (root inside the container == sudo on a host).
# ASSUME_YES=1 covers the pre-existing-user confirmation path non-interactively.
# On success print the marker; either way keep the container alive for
# inspection and the verification step below.
CMD ["/bin/bash", "-c", "chmod +x scripts/*.sh && ASSUME_YES=1 ARCHIVE_FILE=/workspace/archive.tar.gz ./scripts/restore_ubuntu_env.sh && echo ${SUCCESS_MARKER}; tail -f /dev/null"]
EOF

if ! docker build --no-cache -f "${DOCKERFILE_RESTORE}" -t "${BASE_IMAGE_NAME}" .; then
    error_exit "构建测试镜像失败"
fi
log_success "测试镜像 '${BASE_IMAGE_NAME}' 已创建。"

log_info "步骤 3: 在隔离的容器中运行真实恢复脚本"
if ! docker run -d --name "${CONTAINER_NAME}" "${BASE_IMAGE_NAME}"; then
    error_exit "启动测试容器失败"
fi

# Wait for the restore to finish: poll logs for the success marker, fail fast
# on a script error, and give up after RESTORE_TIMEOUT seconds.
log_info "等待恢复脚本执行完成 (超时: ${RESTORE_TIMEOUT}s)..."
elapsed=0
interval=10
while ! docker logs "${CONTAINER_NAME}" 2>&1 | grep -q "${SUCCESS_MARKER}"; do
    if docker logs "${CONTAINER_NAME}" 2>&1 | grep -q "错误:"; then
        docker logs "${CONTAINER_NAME}" 2>&1 | tail -30
        error_exit "恢复脚本报告了错误，请查看上面的日志输出"
    fi
    if [ -z "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
        docker logs "${CONTAINER_NAME}" 2>&1 | tail -30
        error_exit "测试容器意外退出"
    fi
    if [ "${elapsed}" -ge "${RESTORE_TIMEOUT}" ]; then
        docker logs "${CONTAINER_NAME}" 2>&1 | tail -30
        error_exit "恢复脚本在 ${RESTORE_TIMEOUT}s 内未完成"
    fi
    sleep "${interval}"
    elapsed=$((elapsed + interval))
done
log_success "恢复脚本执行完成 (耗时约 ${elapsed}s)。"

log_info "步骤 4: 验证恢复结果"
# User and group were created
if ! docker exec "${CONTAINER_NAME}" id "${USERNAME}" >/dev/null 2>&1; then
    error_exit "用户 '${USERNAME}' 创建失败"
fi

# Home directory restored with real content from the bundle
if ! docker exec "${CONTAINER_NAME}" test -s "/home/${USERNAME}/.zshrc"; then
    error_exit "家目录恢复失败 (/home/${USERNAME}/.zshrc 缺失或为空)"
fi

# mise-managed tools were unpacked
if ! docker exec "${CONTAINER_NAME}" test -d "/home/${USERNAME}/.local/share/mise"; then
    error_exit "mise 目录缺失，离线包内容不完整"
fi

# Default shell was switched to zsh
login_shell=$(docker exec "${CONTAINER_NAME}" sh -c "getent passwd ${USERNAME} | cut -d: -f7")
if [[ "${login_shell}" != *zsh* ]]; then
    error_exit "默认 Shell 未切换为 zsh (当前: ${login_shell})"
fi

# Home ownership belongs to the target user
home_owner=$(docker exec "${CONTAINER_NAME}" stat -c '%U' "/home/${USERNAME}")
if [ "${home_owner}" != "${USERNAME}" ]; then
    error_exit "家目录属主错误 (当前: ${home_owner})"
fi

log_info "步骤 5: 离线运行时验证 (断网模拟离线主机)"
# The bundle's promise is "no network fetches at restore time" — so the tools
# must also RUN clean without network. Cut the container off and exercise the
# first-prompt paths that have historically phoned home (treesitter parser
# auto-install, mason ensure_installed, blink prebuilt download, eza flags).
if ! docker network disconnect bridge "${CONTAINER_NAME}"; then
    error_exit "断网失败 (docker network disconnect bridge ${CONTAINER_NAME})"
fi

# Interactive zsh: `ls /tmp` is the canonical regression (eza --icons flag
# parsing broke argument-taking ls calls in older dotfiles).
if ! docker exec "${CONTAINER_NAME}" su - "${USERNAME}" -c \
        'zsh -ic "ls /tmp >/dev/null && command -v starship >/dev/null && command -v nvim >/dev/null && echo OFFLINE_ZSH_OK"' \
        2>/dev/null | grep -q "OFFLINE_ZSH_OK"; then
    error_exit "离线 zsh 启动/ls/starship/nvim 验证失败"
fi
log_success "离线 zsh 交互环境正常 (ls / starship / nvim)"

# Neovim runtime probes (extra-style bundles only — mini ships no init.lua).
if docker exec "${CONTAINER_NAME}" test -f "/home/${USERNAME}/.config/nvim/init.lua"; then
    # PROBE_EXPECT_TS=true  → wait (slow CI runners) for treesitter to enable,
    #                          then settle so late async noise lands in history.
    # PROBE_EXPECT_TS=false → unbaked-parser file: just settle, then assert the
    #                          auto_install=false promise (quiet, no fetch).
    docker exec "${CONTAINER_NAME}" bash -c 'cat > /tmp/offline_probe.lua << "LUA"
vim.defer_fn(function()
  local bufnr = vim.api.nvim_get_current_buf()
  if os.getenv "PROBE_EXPECT_TS" == "true" then
    vim.wait(60000, function() return vim.treesitter.highlighter.active[bufnr] ~= nil end, 1000)
  end
  vim.wait(10000, function() return false end, 1000)
  local out = {}
  table.insert(out, "TS_ACTIVE=" .. tostring(vim.treesitter.highlighter.active[bufnr] ~= nil))
  table.insert(out, vim.fn.execute "messages")
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.notifier then
    for _, n in ipairs(snacks.notifier.get_history { filter = function() return true end }) do
      table.insert(out, ("NOTIFY[%s] %s"):format(tostring(n.level), tostring(n.msg)))
    end
  end
  local f = io.open(os.getenv "PROBE_OUT", "w")
  f:write(table.concat(out, "\n"))
  f:close()
  vim.cmd "qa!"
end, 1000)
LUA
echo "print(1)"  > /tmp/probe_target.py
echo "{}"        > /tmp/probe_target.json
echo "object X"  > /tmp/probe_target.scala'

    # file:expect_ts — scala is deliberately NOT in the baked manifest: it must
    # stay quiet (no download attempt) yet unhighlighted, proving runtime
    # auto-install is off for arbitrary filetypes on offline hosts.
    for probe_spec in /tmp/probe_target.py:true /tmp/probe_target.json:true "/home/${USERNAME}/.zshrc:true" /tmp/probe_target.scala:false; do
        probe_file="${probe_spec%:*}"
        expect_ts="${probe_spec##*:}"
        probe_out="/tmp/probe_$(basename "${probe_file}").txt"
        docker exec "${CONTAINER_NAME}" su - "${USERNAME}" -c \
            "PROBE_OUT=${probe_out} PROBE_EXPECT_TS=${expect_ts} timeout 100 zsh -ic 'nvim --headless -c \"luafile /tmp/offline_probe.lua\" ${probe_file}'" \
            > /dev/null 2>&1 || true
        if ! docker exec "${CONTAINER_NAME}" grep -q "TS_ACTIVE=${expect_ts}" "${probe_out}"; then
            docker exec "${CONTAINER_NAME}" cat "${probe_out}" 2>/dev/null | tail -20
            error_exit "离线 nvim 验证失败: ${probe_file} treesitter 状态异常 (期望 active=${expect_ts})"
        fi
        if docker exec "${CONTAINER_NAME}" grep -qiE "Downloading|failed to install|Error during download" "${probe_out}"; then
            docker exec "${CONTAINER_NAME}" grep -iE "Downloading|failed to install|Error during download" "${probe_out}" | head -5
            error_exit "离线 nvim 验证失败: ${probe_file} 触发了网络下载/安装 (离线主机上会报错)"
        fi
    done
    log_success "离线 nvim 运行时正常 (py/json/zshrc 高亮可用; scala 无高亮但零网络请求)"
else
    log_info "未发现 nvim init.lua (mini 包)，跳过 nvim 离线验证。"
fi

log_success "✅ 恢复脚本测试成功完成!"

echo
log_info "--- 测试验证 ---"
echo "真实的恢复脚本已在隔离的 Ubuntu 24.04 容器中成功运行，验证了:"
echo "  ✓ OS/glibc 兼容性检查通过"
echo "  ✓ 用户和组创建"
echo "  ✓ APT 依赖安装"
echo "  ✓ 家目录恢复 (含 mise 工具链)"
echo "  ✓ 权限归属"
echo "  ✓ 默认 Shell 切换为 zsh"
echo "  ✓ 断网后 zsh 交互环境可用 (ls/starship/nvim)"
echo "  ✓ 断网后 nvim 无网络请求、treesitter 高亮可用 (extra 包)"
echo ""
echo "要进入测试容器进行手动验证，请运行:"
echo -e "  ${SUCCESS}docker exec -it ${CONTAINER_NAME} su - ${USERNAME}${NC}"
echo ""
echo "验证完成后，请运行以下命令清理环境:"
echo -e "  ${SUCCESS}make clean${NC}"
