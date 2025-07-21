# OfflineDevEnv

This project provides a set of scripts to create a consistent, portable, and offline-ready development environment using Docker. It allows you to prepare a customized environment online, package it, and then restore it on any machine, even without internet access.

## Project Structure

- `docker/`: Contains the `Dockerfile` for building the base development environment.
- `resources/`: Stores necessary resources, such as the archived home directory (`charles_home.tar.gz`).
- `scripts/`: Contains the shell scripts for managing the environment lifecycle.
  - `1_prepare_online.sh`: Builds the Docker image, sets up the environment, and prepares for manual initialization.
  - `2_package_result.sh`: Extracts the initialized home directory from the container and packages it into a `.tar.gz` archive.
  - `3_restore_offline.sh`: Restores the environment from the archived home directory in an offline setting.
- `.gitignore`: Standard Git ignore file to exclude temporary files and build artifacts.
- `README.md`: This project's documentation.

## Usage

### 1. Prepare the Environment (Online)

This step builds the Docker image and starts a container for manual interactive initialization.

```bash
./scripts/1_prepare_online.sh [--no-cache]
```

Follow the on-screen instructions to enter the container and complete the manual setup (e.g., running `source ~/.zshrc`).

### 2. Package the Result

After completing the manual initialization in the container, this script extracts and packages your customized home directory.

```bash
./scripts/2_package_result.sh
```

This will create `resources/charles_home.tar.gz`.

### 3. Restore the Environment (Offline)

Use this script to restore your prepared environment on any machine, simulating an offline scenario.

```bash
./scripts/3_restore_offline.sh
```

This will create a new Docker container with your restored home directory. Follow the instructions to enter and verify the environment.

