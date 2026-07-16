#!/usr/bin/env bash

# ==============================================================================
# Script: Restore (single entry point — no `make` required)
# Restores a devbox home-directory bundle onto this host.
#
#   --file given   → restore a local archive (offline-friendly, no download)
#   --file absent  → download the bundle matching this host's CPU arch from
#                    GitHub Releases first, then restore
#
# Every option can also be set as an environment variable (flag wins), so both
#   sudo ./scripts/restore.sh --current-user
#   sudo CURRENT_USER=1 ./scripts/restore.sh
# work, and the Makefile wrapper needs no special forwarding logic.
# ==============================================================================

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

set -eo pipefail

# ---------- defaults (env vars) ----------------------------------------------
ARCHIVE_FILE="${ARCHIVE_FILE:-}"
PROFILE="${PROFILE:-extra}"
VERSION="${VERSION:-latest}"
REPO="${DEVBOX_REPO:-charles1614/devbox}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-.}"
CURRENT_USER="${CURRENT_USER:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
SKIP_OS_CHECK="${SKIP_OS_CHECK:-0}"
FORCE_DOWNLOAD="${FORCE_DOWNLOAD:-0}"

# ---------- helpers -----------------------------------------------------------
usage() {
    cat <<EOF
Restore a devbox home-directory bundle onto this host (run with sudo).

Usage:
  sudo $(basename "$0") [OPTIONS]

Options:
  -f, --file PATH        Local archive to restore (offline; skips download)
  -p, --profile PROFILE  Bundle profile: mini | extra        (default: ${PROFILE})
  -V, --version TAG      Release tag to download             (default: ${VERSION})
      --repo OWNER/REPO  GitHub repository                   (default: ${REPO})
      --download-dir DIR Where to save the downloaded archive (default: ${DOWNLOAD_DIR})
  -u, --current-user     Restore into the invoking user instead of 'charles'
  -y, --yes              Non-interactive: skip confirmation prompts
      --skip-os-check    Bypass the Ubuntu/glibc compatibility check
      --force-download   Re-download even if the archive is already saved
  -h, --help             Show this help and exit

Every option can also be provided as an environment variable:
  ARCHIVE_FILE  PROFILE  VERSION  DEVBOX_REPO  DOWNLOAD_DIR
  CURRENT_USER=1  ASSUME_YES=1  SKIP_OS_CHECK=1  FORCE_DOWNLOAD=1

Examples:
  sudo $(basename "$0")                                       # download latest extra, restore as charles
  sudo $(basename "$0") --current-user                        # ...into your own login user
  sudo $(basename "$0") -f charles_home_extra_amd64.tar.gz    # offline: local archive
  sudo $(basename "$0") -p mini -V v2026.07.01 -u -y
EOF
    exit 0
}

require_arg() {
    [ $# -ge 2 ] || error_exit "选项 $1 需要一个参数"
}

# ---------- argument parsing (flags override env) -----------------------------
while [ $# -gt 0 ]; do
    case $1 in
        -f|--file)         require_arg "$@"; ARCHIVE_FILE="$2";  shift 2 ;;
        -p|--profile)      require_arg "$@"; PROFILE="$2";       shift 2 ;;
        -V|--version)      require_arg "$@"; VERSION="$2";       shift 2 ;;
        --repo)            require_arg "$@"; REPO="$2";          shift 2 ;;
        --download-dir)    require_arg "$@"; DOWNLOAD_DIR="$2";  shift 2 ;;
        -u|--current-user) CURRENT_USER=1;   shift ;;
        -y|--yes)          ASSUME_YES=1;     shift ;;
        --skip-os-check)   SKIP_OS_CHECK=1;  shift ;;
        --force-download)  FORCE_DOWNLOAD=1; shift ;;
        -h|--help)         usage ;;
        *) error_exit "未知选项: $1 (使用 --help 查看用法)" ;;
    esac
done

# ---------- root check (before any download — fail early, not after 2 GB) ------
if [ "$(id -u)" -ne 0 ]; then
    error_exit "恢复需要 root 权限 (创建用户/APT/chown)。请使用 sudo 重新运行。"
fi

# ---------- download when no local archive was given ---------------------------
if [ -z "${ARCHIVE_FILE}" ]; then
    case "${PROFILE}" in
        mini|extra) : ;;
        *) error_exit "无效的 profile '${PROFILE}'，可选值: mini | extra" ;;
    esac

    case "$(uname -m)" in
        x86_64)        ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) error_exit "不支持的 CPU 架构: $(uname -m) (仅支持 x86_64 / aarch64)" ;;
    esac

    ASSET="charles_home_${PROFILE}_${ARCH}.tar.gz"
    if [ "${VERSION}" = "latest" ]; then
        URL="https://github.com/${REPO}/releases/latest/download/${ASSET}"
    else
        URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"
    fi
    DEST="${DOWNLOAD_DIR}/${ASSET}"

    log_info "步骤 0: 下载离线包"
    log_info "仓库: ${REPO} | 版本: ${VERSION} | 档案: ${ASSET}"

    if [ -s "${DEST}" ] && [ "${FORCE_DOWNLOAD}" != "1" ]; then
        log_warning "检测到已存在的 '${DEST}'，跳过下载 (使用 --force-download 强制重新下载)。"
    else
        if command -v curl &> /dev/null; then
            # .part + mv keeps DEST atomic; -C - resumes an interrupted download.
            if ! curl -fL --retry 3 --retry-delay 2 -C - -o "${DEST}.part" "${URL}"; then
                error_exit "下载失败: ${URL}"
            fi
            mv "${DEST}.part" "${DEST}"
        elif command -v wget &> /dev/null; then
            if ! wget -c -O "${DEST}.part" "${URL}"; then
                error_exit "下载失败: ${URL}"
            fi
            mv "${DEST}.part" "${DEST}"
        else
            error_exit "未找到 curl 或 wget，无法下载。请先安装其一，或手动下载后使用 --file: ${URL}"
        fi
        log_success "已下载: ${DEST} ($(du -h "${DEST}" | cut -f1))"
    fi

    # Sanity check: a GitHub error page is not a gzip archive.
    if ! gzip -t "${DEST}" 2>/dev/null; then
        error_exit "'${DEST}' 不是有效的 gzip 归档 (下载可能失败或版本/资产名不存在)。删除后重试，或检查 ${URL}"
    fi

    ARCHIVE_FILE="${DEST}"
fi

# ---------- hand off to the core restore script --------------------------------
export ARCHIVE_FILE CURRENT_USER ASSUME_YES SKIP_OS_CHECK
exec "${SCRIPT_DIR}/restore_ubuntu_env.sh"
