# Devbox: Portable Development Environment

A solution for creating, packaging, and restoring portable development environments. Prepare a customized environment online, package it into an offline bundle, and restore it on any Ubuntu system or Docker container.

## Quick Start from GHCR

Pre-built images are published to GHCR automatically on every push to `main`. Two profiles are available:

| Profile | Tools |
|---------|-------|
| **mini** | python, chezmoi, neovim, uv, zellij, fzf, zoxide |
| **extra** | everything in mini + rust, eza, lazygit, ctop, dust, nodejs, golang, clang |

```bash
# Pull the image
docker pull ghcr.io/charles1614/devbox:mini-latest
# or
docker pull ghcr.io/charles1614/devbox:extra-latest

# Run interactive shell (ready to use immediately)
docker run -it ghcr.io/charles1614/devbox:extra-latest
```

All tools, shell plugins (zinit), and neovim plugins (lazy.nvim) are pre-installed during the image build. No manual initialization is needed.

## Build Locally

If you prefer to build the image yourself instead of pulling from GHCR:

```bash
# Clone the repository
git clone git@github.com:charles1614/devbox.git
cd devbox

# Set up configuration
make setup
# Edit config.env with your settings

# Build and start container for manual initialization
make prepare
# Use NO_CACHE=1 for a clean rebuild: make prepare NO_CACHE=1
```

This will build a Docker image and start a container. Follow the on-screen instructions to complete manual setup, then:

```bash
# Package into offline bundle
make package

# Commit (Git LFS handles large files automatically)
git add .
git commit -m "Add portable development environment bundle"
git push
```

## Restore

**On Ubuntu system:**
```bash
sudo make restore
```

**Test in Docker:**
```bash
make test
```

## Project Structure

```
devbox/
├── .github/workflows/  CI/CD (build & publish to GHCR)
├── docker/             Dockerfile
├── scripts/
│   ├── common.sh                 Shared utilities and configuration
│   ├── init_plugins.sh           Auto-install zsh/neovim plugins during build
│   ├── prepare_online_env.sh     Prepare online environment
│   ├── package_offline_bundle.sh Package into offline bundle
│   └── restore_ubuntu_env.sh     Restore on Ubuntu system
├── resources/          Generated tar.gz bundles (Git LFS)
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
| `make prepare` | Build image and start container for manual init |
| `make package` | Package initialized environment into offline bundle |
| `make restore` | Restore environment on Ubuntu system (requires sudo) |
| `make test` | Test Docker restoration |
| `make clean` | Clean up containers, images, and temp files |
| `make workflow` | Run setup + prepare in sequence |

## Prerequisites

- **Docker** — for building, testing, and running environments
- **Git LFS** — for handling large tar.gz files (already configured via `.gitattributes`)
