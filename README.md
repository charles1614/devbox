# Devbox: Portable Development Environment

This project provides a set of scripts to create a consistent, portable, and offline-ready development environment. It allows you to prepare a customized environment online, package it, and then restore it on various systems, including a base Ubuntu installation or within a Docker container.

## Project Structure

- `docker/`: Contains the optimized `Dockerfile` with multi-stage builds for better performance.
- `resources/`: Stores necessary resources, such as the archived home directory (`charles_home.tar.gz`).
- `scripts/`: Contains the core shell scripts for managing the environment lifecycle.
  - `common.sh`: Shared utilities and configuration management.
  - `prepare_online_env.sh`: Builds the Docker image, sets up the environment, and prepares for manual initialization.
  - `package_offline_bundle.sh`: Extracts the initialized home directory from the container and packages it into a `.tar.gz` archive.
  - `restore_ubuntu_env.sh`: Restores the environment from the archived home directory directly on a base Ubuntu system.
- `tests/`: Contains scripts for testing the environment restoration process.
  - `test_docker_restore.sh`: Simulates an offline environment restoration within a Docker container for testing purposes.
- `config.env.example`: Example configuration file for customizing the environment.
- `Makefile`: Convenient shortcuts for common operations.
- `.gitignore`: Enhanced Git ignore file to exclude temporary files and build artifacts.
- `README.md`: This project's documentation.

## Quick Start

### 1. Initial Setup

```bash
# Copy and customize the configuration
make setup
# Edit config.env with your settings
```

### 2. Prepare the Online Environment

```bash
make prepare
```

Follow the on-screen instructions to enter the container and complete the manual setup (e.g., running `source ~/.zshrc` and then `nvim +PlugInstall +qa`).

### 3. Package the Offline Bundle

```bash
make package
```

This will create `resources/charles_home.tar.gz`, which is your portable development environment.

### 4. Restore the Environment on Ubuntu

```bash
sudo make restore
```

### 5. Test Docker Restoration

```bash
make test
```

Follow the instructions provided by the script to enter the test container and verify the restored environment.

## Configuration

The project uses a centralized configuration system. Copy `config.env.example` to `config.env` and customize the values:

```bash
cp config.env.example config.env
# Edit config.env with your settings
```

Key configuration options:
- `USERNAME`: Your username for the development environment
- `USER_ID`/`GROUP_ID`: User and group IDs
- `SETUP_SCRIPT_URL`: URL to your dotfiles setup script
- `APT_PACKAGES`: Space-separated list of packages to install
- `DOCKER_BASE_IMAGE`: Base Docker image to use

## Advanced Usage

### Manual Script Execution

If you prefer to run scripts directly:

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

### Cleanup

```bash
make clean
```

This removes temporary files, containers, and images created during the process.

## Optimizations

This project has been optimized for:

- **Maintainability**: Shared utilities and centralized configuration
- **Performance**: Multi-stage Docker builds and layer optimization
- **Reliability**: Comprehensive error handling and validation
- **Usability**: Makefile shortcuts and improved documentation
- **Security**: Better Docker practices and permission handling

## Troubleshooting

### Common Issues

1. **Docker not found**: Install Docker and ensure it's running
2. **Permission denied**: Use `sudo` for restore operations
3. **Container already exists**: Run `make clean` to remove old containers
4. **Configuration errors**: Check `config.env` for correct values

### Debug Mode

For debugging, you can run scripts with verbose output:

```bash
bash -x ./scripts/prepare_online_env.sh
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is open source. Please check the license file for details.