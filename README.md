# Devbox: Portable Development Environment

A comprehensive solution for creating, packaging, and restoring portable development environments. This project allows you to prepare a customized environment online, package it into an offline bundle, and restore it on any Ubuntu system or Docker container.

## Features

- 🚀 **Online Environment Preparation**: Set up your development environment with all tools and configurations
- 📦 **Offline Packaging**: Create portable tar.gz bundles that can be shared and restored anywhere
- 🔄 **Easy Restoration**: One-command restoration on Ubuntu systems or Docker containers
- 🧪 **Testing Support**: Built-in Docker testing to verify restoration works correctly
- 🔧 **Git LFS Integration**: Proper handling of large tar.gz files with Git Large File Storage

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

## Prerequisites

- **Docker**: For environment preparation and testing
- **Git LFS**: For handling large tar.gz files
- **Ubuntu 22.04+**: For restoration (or Docker for testing)

### Installing Git LFS

```bash
# Ubuntu/Debian
sudo apt-get install git-lfs

# macOS
brew install git-lfs

# Windows
# Download from https://git-lfs.github.com/
```

After installation, initialize Git LFS in your repository:

```bash
git lfs install
```

## Quick Start

### 1. Initial Setup

```bash
# Clone the repository
git clone <your-repo-url>
cd devbox

# Initialize Git LFS (if not already done)
git lfs install

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

### 4. Commit with Git LFS

```bash
# Add the tar.gz file (automatically tracked by Git LFS)
git add resources/charles_home.tar.gz

# Commit the changes
git commit -m "Add portable development environment bundle"

# Push to remote (Git LFS will handle the large file)
git push origin main
```

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

## Git LFS Configuration

### Setting up Git LFS for tar.gz files

Create or update `.gitattributes` in your repository:

```bash
# Track all tar.gz files with Git LFS
*.tar.gz filter=lfs diff=lfs merge=lfs -text
```

### Git LFS Commands

```bash
# Check what files are tracked by LFS
git lfs ls-files

# Pull LFS files from remote
git lfs pull

# Push LFS files to remote
git lfs push origin main

# Check LFS status
git lfs status
```

### Working with Large Files

```bash
# When adding new tar.gz files
git add resources/*.tar.gz
git commit -m "Add new environment bundle"
git push origin main

# When cloning a repository with LFS files
git clone <repo-url>
git lfs pull  # Download LFS files

# When pulling updates
git pull origin main
git lfs pull  # Download any new LFS files
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

# File paths
RESOURCES_DIR="resources"
SCRIPTS_DIR="scripts"
TESTS_DIR="tests"
DOCKER_DIR="docker"

# Archive naming
HOME_ARCHIVE_NAME="${USERNAME}_home.tar.gz"
```

## Advanced Usage

### Manual Script Execution

```bash
# Prepare environment
./scripts/prepare_online_env.sh [--no-cache]

# Package bundle
./scripts/package_offline_bundle.sh

# Restore environment
sudo ./scripts/restore_ubuntu_env.sh

# Test restoration
./tests/test_docker_restore.sh
```

### Docker Testing

```bash
# Run the test
make test

# Access the test container
docker exec -it test_offline_charles su - charles

# Verify the environment
zsh --version
nvim --version
# ... test other tools

# Clean up when done
make clean
```

### Workflow Commands

```bash
# Full workflow (setup + prepare)
make workflow

# Clean up everything
make clean

# Show help
make help
```

## Troubleshooting

### Common Issues

**Git LFS Issues:**
```bash
# If LFS files aren't downloading
git lfs pull

# If LFS isn't tracking files properly
git lfs track "*.tar.gz"
git add .gitattributes
git commit -m "Update LFS tracking"
```

**Docker Issues:**
```bash
# Clean up Docker resources
make clean

# Check Docker status
docker ps -a
docker images

# Remove specific containers/images
docker stop <container-name>
docker rm <container-name>
docker rmi <image-name>
```

**Permission Issues:**
```bash
# Ensure proper permissions for restore
sudo chown -R $USER:$USER resources/
```

**Network Issues:**
```bash
# If package installation fails, check network
ping archive.ubuntu.com

# Use alternative mirrors if needed
# Edit /etc/apt/sources.list in the container
```

### Debug Mode

```bash
# Run scripts with verbose output
bash -x ./scripts/prepare_online_env.sh

# Check container logs
docker logs <container-name>

# Enter container for debugging
docker exec -it <container-name> /bin/bash
```

## Best Practices

### Git LFS Management

1. **Always use Git LFS for tar.gz files**: Prevents repository bloat
2. **Regular cleanup**: Remove old environment bundles when no longer needed
3. **Version control**: Tag releases with specific environment versions
4. **Documentation**: Keep README updated with environment changes

### Environment Management

1. **Incremental updates**: Update environment incrementally rather than rebuilding from scratch
2. **Testing**: Always test restoration before sharing bundles
3. **Backup**: Keep backups of important environment configurations
4. **Documentation**: Document any special setup steps or dependencies

### Security

1. **Review contents**: Always review what's being packaged in your environment
2. **Sensitive data**: Never include sensitive data in environment bundles
3. **Updates**: Keep base images and packages updated
4. **Permissions**: Use appropriate file permissions in restored environments

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make your changes
4. Test thoroughly: `make test`
5. Commit with descriptive messages
6. Push to your fork: `git push origin feature-name`
7. Submit a pull request

### Development Setup

```bash
# Set up development environment
make setup
make prepare

# Run tests
make test

# Clean up
make clean
```

## License

This project is open source. Please check the license file for details.

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review existing issues
3. Create a new issue with detailed information
4. Include logs and error messages when possible