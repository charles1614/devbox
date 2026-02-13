# ==============================================================================
# Optimized Dockerfile for Devbox Development Environment
# Uses multi-stage build and layer optimization for better performance
# ==============================================================================

# Build stage for dependencies
FROM ubuntu:22.04 AS base

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

# Create user and group
RUN groupadd -g ${GROUP_ID} ${USERNAME} && \
    useradd -m -s /bin/bash -u ${USER_ID} -g ${GROUP_ID} ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Copy setup scripts
COPY ${LOCAL_SETUP_SCRIPT} /usr/local/bin/run.sh
COPY scripts/init_plugins.sh /usr/local/bin/init_plugins.sh
RUN chmod +x /usr/local/bin/run.sh /usr/local/bin/init_plugins.sh

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

# Default command
CMD ["/bin/zsh"]
