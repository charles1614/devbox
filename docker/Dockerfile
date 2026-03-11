# ==============================================================================
# Optimized Dockerfile for Devbox Development Environment
# Uses multi-stage build and layer optimization for better performance
# ==============================================================================

# Build stage for dependencies
FROM nvcr.io/nvidia/cuda:13.1.0-runtime-ubuntu24.04 AS base

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV TZ=Etc/UTC

# Install system dependencies in a single layer for better caching
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        sudo \
        git \
        curl \
        sed \
        ca-certificates \
        wget \
        jq \
        cmake \
        ninja-build \
        openssh-server \
        && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    rm -rf /var/lib/apt/lists/*

# Development stage
FROM base AS development

# Build arguments
ARG USERNAME
ARG USER_ID
ARG GROUP_ID
ARG LOCAL_SETUP_SCRIPT
ARG PROFILE=extra

# Create user and group (handle GID/UID that already exist in the base image)
RUN (getent group ${GROUP_ID} > /dev/null 2>&1 || groupadd -g ${GROUP_ID} ${USERNAME}) && \
    if getent passwd ${USER_ID} > /dev/null 2>&1; then \
        existing_user=$(getent passwd ${USER_ID} | cut -d: -f1) && \
        usermod -l ${USERNAME} -d /home/${USERNAME} -m -s /bin/bash -g ${GROUP_ID} "$existing_user"; \
    else \
        useradd -m -s /bin/bash -u ${USER_ID} -g ${GROUP_ID} ${USERNAME}; \
    fi && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Configure SSH server
# Drop an override file so we never touch the distro sshd_config directly.
RUN ssh-keygen -A && \
    mkdir -p /etc/ssh/sshd_config.d && \
    printf 'PasswordAuthentication yes\nPermitRootLogin no\nPrintMotd no\n' \
        > /etc/ssh/sshd_config.d/devbox.conf

# Set the user SSH password from a Docker build secret.
# Falls back to "devbox" when no secret is mounted (local builds).
RUN --mount=type=secret,id=ssh_password \
    echo "${USERNAME}:$(cat /run/secrets/ssh_password 2>/dev/null || echo 'devbox')" | chpasswd

# Copy setup scripts
COPY ${LOCAL_SETUP_SCRIPT} /usr/local/bin/run.sh
COPY scripts/init_plugins.sh /usr/local/bin/init_plugins.sh
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/run.sh /usr/local/bin/init_plugins.sh /usr/local/bin/entrypoint.sh

EXPOSE 22

# Switch to user context
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Ensure mise-managed tools (chezmoi, starship, etc.) are on PATH for all shells
ENV PATH="/home/${USERNAME}/.local/share/mise/shims:/home/${USERNAME}/.local/bin:${PATH}"

# When triggered by dotfiles changes, bust cache from this point onward
ARG CACHEBUST=
# Install development tools and configurations
RUN bash -l -c "/usr/local/bin/run.sh --profile ${PROFILE} --set-zsh-default --chezmoi https://github.com/charles1614/dotfiles.git"

# Auto-install zsh (zap) and neovim (lazy.nvim) plugins
# GITHUB_TOKEN is passed as a build secret to raise GitHub API rate limits
# from 60/hr (unauthenticated) to 5000/hr, preventing plugin clone hangs in CI.
RUN --mount=type=secret,id=github_token \
    GITHUB_TOKEN=$(cat /run/secrets/github_token 2>/dev/null || true) \
    /usr/local/bin/init_plugins.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ps aux | grep -v grep | grep zsh || exit 1

# Entrypoint starts sshd then execs CMD
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/zsh"]
