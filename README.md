# Devbox: Portable Development Environment

This project provides a set of scripts to create a consistent, portable, and offline-ready development environment. It allows you to prepare a customized environment online, package it, and then restore it on various systems, including a base Ubuntu installation or within a Docker container.

## Project Structure

- `docker/`: Contains the `Dockerfile` used for building the base development environment image.
- `resources/`: Stores necessary resources, such as the archived home directory (`charles_home.tar.gz`).
- `scripts/`: Contains the core shell scripts for managing the environment lifecycle.
  - `prepare_online_env.sh`: Builds the Docker image, sets up the environment, and prepares for manual initialization.
  - `package_offline_bundle.sh`: Extracts the initialized home directory from the container and packages it into a `.tar.gz` archive.
  - `restore_ubuntu_env.sh`: Restores the environment from the archived home directory directly on a base Ubuntu system.
- `tests/`: Contains scripts for testing the environment restoration process.
  - `test_docker_restore.sh`: Simulates an offline environment restoration within a Docker container for testing purposes.
- `.gitignore`: Standard Git ignore file to exclude temporary files and build artifacts.
- `README.md`: This project's documentation.

## Usage

### 1. Prepare the Online Environment

This step builds the Docker image and starts a container for manual interactive initialization. This is where you install all your desired tools and configurations.

```bash
./scripts/prepare_online_env.sh [--no-cache]
```

Follow the on-screen instructions to enter the container and complete the manual setup (e.g., running `source ~/.zshrc` and then `nvim +PlugInstall +qa`).

### 2. Package the Offline Bundle

After completing the manual initialization in the container, this script extracts and packages your customized home directory into an offline bundle.

```bash
./scripts/package_offline_bundle.sh
```

This will create `resources/charles_home.tar.gz`, which is your portable development environment.

### 3. Restore the Environment on Ubuntu

Use this script to restore your prepared environment directly on a base Ubuntu system. This script requires `sudo` privileges.

```bash
sudo ./scripts/restore_ubuntu_env.sh
```

### 4. Test Docker Restoration

This script is for testing purposes. It simulates an offline environment restoration within a new Docker container, allowing you to verify the `charles_home.tar.gz` bundle.

```bash
./tests/test_docker_restore.sh
```

Follow the instructions provided by the script to enter the test container and verify the restored environment.