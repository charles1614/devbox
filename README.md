# Devbox: Portable Development Environment

A solution for creating, packaging, and restoring portable development environments. Prepare a customized environment online, package it into an offline bundle, and restore it on any Ubuntu system or Docker container.

## Quick Start from GHCR

Pre-built images are published to GHCR automatically on every push to `main`. Two profiles are available:

| Profile | Tools |
|---------|-------|
| **mini** | python, uv, neovim, fzf, zoxide, chezmoi, zellij, starship, jq, ripgrep, fd |
| **extra** | everything in mini + node.js, go, rust, eza, lazygit, delta, bat, dust, yazi, btop, procs, tealdeer, xh, gping, llvm/clang |

```bash
# Pull the image
docker pull ghcr.io/charles1614/devbox:mini-latest
# or
docker pull ghcr.io/charles1614/devbox:extra-latest

# Run interactive shell (ready to use immediately)
docker run -it ghcr.io/charles1614/devbox:extra-latest
```

All tools (managed by mise), shell plugins (zinit), starship prompt, and neovim plugins (lazy.nvim) are pre-installed during the image build. No manual initialization is needed.

## Download Offline Bundle

Pre-built home directory archives are available on the [Releases](https://github.com/charles1614/devbox/releases) page:

- `charles_home_mini.tar.gz` — mini profile
- `charles_home_extra.tar.gz` — extra profile

## Build Locally

If you prefer to build the image yourself instead of pulling from GHCR:

```bash
# Clone the repository
git clone git@github.com:charles1614/devbox.git
cd devbox

# Set up configuration
make setup
# Edit config.env with your settings

# Build and start container
make prepare PROFILE=extra
# Use NO_CACHE=1 for a clean rebuild: make prepare PROFILE=extra NO_CACHE=1
```

This will build a Docker image and start a container. Then package the environment:

```bash
# Package into offline bundle
make package FILE=charles_home_extra.tar.gz
```

## Restore

Download the archive from [Releases](https://github.com/charles1614/devbox/releases), then:

**On Ubuntu system:**
```bash
sudo make restore FILE=charles_home_extra.tar.gz
# or
sudo make restore FILE=charles_home_mini.tar.gz
```

**Test in Docker:**
```bash
make test FILE=charles_home_extra.tar.gz
```

## Project Structure

```
devbox/
├── .github/workflows/  CI/CD (build, publish to GHCR, release archives)
├── docker/             Dockerfile
├── scripts/
│   ├── common.sh                 Shared utilities and configuration
│   ├── init_plugins.sh           Auto-install zsh/neovim plugins during build
│   ├── prepare_online_env.sh     Prepare online environment
│   ├── package_offline_bundle.sh Package into offline bundle
│   └── restore_ubuntu_env.sh     Restore on Ubuntu system
├── tests/              Docker restoration tests
├── config.env.example  Configuration template
└── Makefile            All commands
```

## Configuration

```bash
cp config.env.example config.env
```

| Option | Description |
|--------|-------------|
| `USERNAME` | Username for the environment |
| `USER_ID` / `GROUP_ID` | UID/GID for the user |
| `SETUP_SCRIPT_URL` | URL to your dotfiles setup script |
| `DOCKER_BASE_IMAGE` | Base Docker image (default: `ubuntu:22.04`) |
| `APT_PACKAGES` | Space-separated list of APT packages to install |

## Workflow Commands

| Command | Description |
|---------|-------------|
| `make setup` | Create `config.env` from example |
| `make prepare PROFILE=<mini\|extra>` | Build image and start container |
| `make package FILE=<output.tar.gz>` | Package initialized environment into offline bundle |
| `make restore FILE=<archive.tar.gz>` | Restore environment on Ubuntu system (requires sudo) |
| `make test FILE=<archive.tar.gz>` | Test Docker restoration |
| `make clean` | Clean up containers, images, and temp files |
| `make workflow` | Run setup + prepare in sequence |

## Prerequisites

- **Docker** — for building, testing, and running environments
