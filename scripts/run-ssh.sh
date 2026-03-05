#!/usr/bin/env bash
# Run a devbox container with SSH access and correct UID/GID mapping.
set -euo pipefail

# ---------- defaults ---------------------------------------------------------
IMAGE_USERNAME="charles"
TARGET_UID="$(id -u)"
TARGET_GID="$(id -g)"
SSH_PORT="2222"
IMAGE="ghcr.io/charles1614/devbox:extra-latest"
CONTAINER_NAME="devbox"
EXTRA_VOLUMES=()

# ---------- helpers ----------------------------------------------------------
usage() {
    cat <<EOF
Run a devbox container with SSH access and correct UID/GID mapping.

The image is built with a fixed username/UID (default: charles/1000).
This script remaps them at runtime to match the host user so that
bind-mounted volumes (~/.ssh, ~/.claude) are accessible immediately.

Usage:
  $(basename "$0") [OPTIONS]

Options:
  -u, --username USERNAME   Username baked into the image   (default: ${IMAGE_USERNAME})
  -i, --uid      UID        Target UID inside the container (default: ${TARGET_UID})
  -g, --gid      GID        Target GID inside the container (default: ${TARGET_GID})
  -p, --port     PORT       Host port mapped to SSH (22)    (default: ${SSH_PORT})
  -v, --volume   SRC:DST    Bind-mount a host path (repeatable; supports :ro/:rw)
      --image    IMAGE      Docker image to use             (default: ${IMAGE})
      --name     NAME       Container name                  (default: ${CONTAINER_NAME})
  -h, --help                Show this help and exit

~/.ssh (read-only) and ~/.claude are mounted automatically when present.

Examples:
  $(basename "$0")
  $(basename "$0") --uid 1001 --gid 1001
  $(basename "$0") -v ~/projects:/home/charles/projects
  $(basename "$0") -v ~/projects:/home/charles/projects -v ~/data:/data:ro
  $(basename "$0") --username alice --uid 1002 --port 2223
  $(basename "$0") --image ghcr.io/charles1614/devbox:mini-latest
EOF
    exit 0
}

die() {
    echo "Error: $*" >&2
    echo "Try '$(basename "$0") --help' for usage." >&2
    exit 1
}

require_arg() {
    [[ $# -ge 2 ]] || die "option $1 requires an argument"
}

is_uint() { [[ $1 =~ ^[0-9]+$ ]]; }

# ---------- argument parsing -------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--username) require_arg "$@"; IMAGE_USERNAME="$2"; shift 2 ;;
        -i|--uid)      require_arg "$@"; TARGET_UID="$2";     shift 2 ;;
        -g|--gid)      require_arg "$@"; TARGET_GID="$2";     shift 2 ;;
        -p|--port)     require_arg "$@"; SSH_PORT="$2";       shift 2 ;;
        -v|--volume)   require_arg "$@"; EXTRA_VOLUMES+=("$2"); shift 2 ;;
        --image)       require_arg "$@"; IMAGE="$2";          shift 2 ;;
        --name)        require_arg "$@"; CONTAINER_NAME="$2"; shift 2 ;;
        -h|--help)     usage ;;
        *)             die "unknown option: $1" ;;
    esac
done

# ---------- input validation -------------------------------------------------
is_uint "${TARGET_UID}" || die "--uid must be a positive integer, got '${TARGET_UID}'"
is_uint "${TARGET_GID}" || die "--gid must be a positive integer, got '${TARGET_GID}'"
is_uint "${SSH_PORT}"   || die "--port must be a positive integer, got '${SSH_PORT}'"
[[ ${IMAGE_USERNAME} =~ ^[a-z_][a-z0-9_-]*$ ]] \
    || die "--username must be a valid Linux username, got '${IMAGE_USERNAME}'"

HOME_DIR="/home/${IMAGE_USERNAME}"

# ---------- prerequisites ----------------------------------------------------
command -v docker &>/dev/null || die "docker is not installed or not in PATH"

# ---------- stop existing container if any -----------------------------------
if docker container inspect "${CONTAINER_NAME}" &>/dev/null; then
    echo "Removing existing container '${CONTAINER_NAME}'..."
    docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

# ---------- build volume mounts ----------------------------------------------
MOUNTS=()
[[ -d "${HOME}/.ssh" ]]    && MOUNTS+=(-v "${HOME}/.ssh:${HOME_DIR}/.ssh:ro")
[[ -d "${HOME}/.claude" ]] && MOUNTS+=(-v "${HOME}/.claude:${HOME_DIR}/.claude")

for vol in ${EXTRA_VOLUMES[@]+"${EXTRA_VOLUMES[@]}"}; do
    src="${vol%%:*}"
    [[ "${vol}" == *:* ]] || die "-v '${vol}' must be in SRC:DST format (e.g. ~/projects:/home/charles/projects)"
    [[ -e "${src}" ]]     || die "-v source path '${src}' does not exist"
    MOUNTS+=(-v "${vol}")
done

# ---------- startup command --------------------------------------------------
# Strategy:
#   1. sed:         remap UID/GID in /etc/passwd + /etc/group instantly
#   2. chown dirs:  fix all directories synchronously (fast — avoids
#                   "permission denied" on cd / mkdir / write immediately)
#   3. chown top:   fix top-level home files (e.g. .zsh_history)
#   4. chown rest:  fix remaining nested files in the background (tini as
#                   PID 1 adopts the orphan so bash does not block)
#   5. sshd:        starts right after step 3, no wait for step 4
read -r -d '' STARTUP <<'INNER' || true
    sed -i "s|^__USER__:x:[0-9]*:[0-9]*:|__USER__:x:__UID__:__GID__:|" /etc/passwd
    sed -i "s|^__USER__:x:[0-9]*:|__USER__:x:__GID__:|" /etc/group
    find __HOME__ -type d -exec chown __UID__:__GID__ {} + 2>/dev/null
    find __HOME__ -maxdepth 1 -exec chown __UID__:__GID__ {} + 2>/dev/null
    chown -R __UID__:__GID__ __HOME__ 2>/dev/null &
    mkdir -p /run/sshd
    /usr/sbin/sshd
    exec sleep infinity
INNER

# Replace placeholders with validated values (safe — all values are validated)
STARTUP="${STARTUP//__USER__/${IMAGE_USERNAME}}"
STARTUP="${STARTUP//__UID__/${TARGET_UID}}"
STARTUP="${STARTUP//__GID__/${TARGET_GID}}"
STARTUP="${STARTUP//__HOME__/${HOME_DIR}}"

# ---------- run --------------------------------------------------------------
echo "Starting '${CONTAINER_NAME}'..."
echo "  Image    : ${IMAGE}"
echo "  SSH port : ${SSH_PORT}"
echo "  User     : ${IMAGE_USERNAME}  UID=${TARGET_UID}  GID=${TARGET_GID}"
for vol in ${EXTRA_VOLUMES[@]+"${EXTRA_VOLUMES[@]}"}; do
    echo "  Volume   : ${vol}"
done

CID=$(docker run --rm -d \
    -p "${SSH_PORT}:22" \
    ${MOUNTS[@]+"${MOUNTS[@]}"} \
    --name "${CONTAINER_NAME}" \
    --init \
    --user root \
    --entrypoint /bin/bash \
    "${IMAGE}" \
    -c "${STARTUP}") || die "docker run failed"

echo ""
echo "Done (${CID:0:12}). Connect with:"
echo "  ssh -p ${SSH_PORT} ${IMAGE_USERNAME}@localhost"
