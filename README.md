# Devbox: Portable Development Environment

A comprehensive solution for creating, packaging, and restoring portable development environments. This project allows you to prepare a customized environment online, package it into an offline bundle, and restore it on any Ubuntu system or Docker container.

## Features

- 🚀 **Online Environment Preparation**: Set up your development environment with all tools and configurations
- 📦 **Offline Packaging**: Create portable tar.gz bundles that can be shared and restored anywhere
- 🔄 **Easy Restoration**: One-command restoration on Ubuntu systems or Docker containers
- 🧪 **Testing Support**: Built-in Docker testing to verify restoration works correctly
- 🔧 **Git LFS Integration**: Automatic handling of large tar.gz files with Git Large File Storage

## Quick Start

### 1. Initial Setup

```bash
# Clone the repository
git clone <your-repo-url>
cd devbox

# Set up configuration
make setup
# Edit config.env with your settings
```

### 2. Prepare Online Environment

```bash
make prepare
```

This will:
- Build a Docker container with your development environment
- Start the container for manual initialization
- Follow the on-screen instructions to complete setup

**Manual Setup Steps:**
```bash
# Enter the container (instructions will be shown)
docker exec -it manual_init_container_charles /bin/bash

# Complete your environment setup
source ~/.zshrc
nvim +PlugInstall +qa
# ... any other setup steps

# Exit when done
exit
```

### 3. Package Offline Bundle

```bash
make package
```

This creates `resources/charles_home.tar.gz` - your portable development environment.

### 4. Commit and Push

```bash
# Add and commit changes (Git LFS handles large files automatically)
git add .
git commit -m "Add portable development environment bundle"
git push
```

**Note**: The `.gitattributes` file is already configured for Git LFS, so `git push` will automatically handle the large tar.gz files.

### 5. Restore Environment

**On Ubuntu System:**
```bash
sudo make restore
```

**Test in Docker:**
```bash
make test
# Follow instructions to verify the restored environment
```

## Project Structure

```
devbox/
├── docker/              # Docker configuration files
├── resources/           # Generated resources (tar.gz files tracked by Git LFS)
├── scripts/            # Core shell scripts
│   ├── common.sh       # Shared utilities and configuration
│   ├── prepare_online_env.sh    # Prepare online environment
│   ├── package_offline_bundle.sh # Package into offline bundle
│   └── restore_ubuntu_env.sh    # Restore on Ubuntu system
├── tests/              # Testing scripts
│   └── test_docker_restore.sh   # Docker restoration testing
├── config.env.example  # Configuration template
├── Makefile           # Convenient shortcuts
└── README.md          # This documentation
```

## Configuration

Copy and customize the configuration:

```bash
cp config.env.example config.env
# Edit config.env with your settings
```

### Key Configuration Options

```bash
# User configuration
USERNAME="your_username"
USER_ID=1000
GROUP_ID=1000

# Setup script (optional)
SETUP_SCRIPT_URL="https://raw.githubusercontent.com/your-username/dotfiles/main/setup.sh"

# Docker configuration
DOCKER_BASE_IMAGE="ubuntu:22.04"

# APT packages to install
APT_PACKAGES="build-essential git curl unzip jq libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncurses5-dev libffi-dev zsh bat ripgrep fd-find"
```

## Workflow Commands

```bash
# Full workflow (setup + prepare)
make workflow

# Clean up everything
make clean

# Show help
make help
```

## Prerequisites

- **Docker**: For environment preparation and testing
- **Git LFS**: For handling large tar.gz files (already configured)
- **Ubuntu 22.04+**: For restoration (or Docker for testing)

## License

This project is open source. Please check the license file for details.