# ==============================================================================
# 最终修正版 Dockerfile
# 结合了所有调试结果，确保构建成功且环境完整
# ==============================================================================
FROM ubuntu:22.04

# 接收来自 docker build 命令的参数
ARG USERNAME
ARG USER_ID
ARG GROUP_ID
ARG LOCAL_SETUP_SCRIPT

# 设置基础环境，避免交互式提示
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG C.UTF-8

# 1. 安装运行安装脚本所必需的基础软件包
RUN apt-get update && \
    apt-get install -y --no-install-recommends sudo git curl sed ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# 2. 创建用户
RUN groupadd -g ${GROUP_ID} ${USERNAME} && \
    useradd -m -s /bin/bash -u ${USER_ID} -g ${GROUP_ID} ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# 3. 复制 setup 脚本到镜像中
COPY ${LOCAL_SETUP_SCRIPT} /usr/local/bin/run.sh
RUN chmod +x /usr/local/bin/run.sh

# 设置时区以避免交互式提示
ENV TZ=Etc/UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone


# 切换到用户
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# 4. 执行您的 run.sh 脚本，完成所有文件和工具的安装
RUN bash -l -c "/usr/local/bin/run.sh --profile extra --set-zsh-default --chezmoi https://github.com/charles1614/dotfiles.git"


# ==============================================================================


# 7. 设置默认 shell (需要 root 权限)
USER root
RUN chsh -s /bin/zsh ${USERNAME}

# 最终将用户切回
USER ${USERNAME}

# (可选) 设置一个默认命令，便于调试
CMD ["/bin/zsh"]
