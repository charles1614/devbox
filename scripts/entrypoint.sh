#!/bin/bash
# ==============================================================================
# Container entrypoint — starts SSH daemon then executes CMD
# ==============================================================================
set -e

# sshd needs /run/sshd for privilege separation; /run is a tmpfs so we
# must recreate the directory every time the container starts.
/usr/bin/sudo /usr/bin/mkdir -p /run/sshd

# Start SSH daemon in the background (runs as root via sudo).
# Non-fatal: if sshd fails (e.g. missing host keys), the container still works.
/usr/bin/sudo /usr/sbin/sshd || echo "[entrypoint] WARNING: sshd failed to start, SSH unavailable"

exec "$@"
