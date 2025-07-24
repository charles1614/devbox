# ==============================================================================
# Optimized Dockerfile for Devbox Development Environment
# Uses multi-stage build and layer optimization for better performance
# ==============================================================================

# Build stage for dependencies
ARG TARGETPLATFORM
FROM --platform=${TARGETPLATFORM:-linux/amd64} ubuntu:22.04 AS base

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

# Create user and group
RUN groupadd -g ${GROUP_ID} ${USERNAME} && \
    useradd -m -s /bin/bash -u ${USER_ID} -g ${GROUP_ID} ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Copy setup script
COPY ${LOCAL_SETUP_SCRIPT} /usr/local/bin/run.sh
RUN chmod +x /usr/local/bin/run.sh

# Switch to user context
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Install development tools and configurations
RUN bash -l -c "/usr/local/bin/run.sh --profile extra --set-zsh-default --chezmoi https://github.com/charles1614/dotfiles.git"

# Final stage - set default shell
USER root
RUN chsh -s /bin/zsh ${USERNAME}

# Switch back to user
USER ${USERNAME}

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ps aux | grep -v grep | grep zsh || exit 1

# Default command
CMD ["/bin/zsh"]
