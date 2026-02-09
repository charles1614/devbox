# ==============================================================================
# Devbox Makefile
# Provides convenient shortcuts for common operations
# ==============================================================================

# Build profile for Docker image (mini or extra)
PROFILE ?= extra

.PHONY: help prepare package restore test clean setup

# Default target
help:
	@echo "Devbox - Portable Development Environment"
	@echo ""
	@echo "Available targets:"
	@echo "  setup     - Initial setup (copy config.env.example to config.env)"
	@echo "  prepare   - Prepare online environment (PROFILE=mini|extra)"
	@echo "             Use NO_CACHE=1 to build without cache: make prepare NO_CACHE=1"
	@echo "  package   - Package the initialized environment into offline bundle"
	@echo "             Output: FILE=charles_home.tar.gz (default)"
	@echo "  restore   - Restore environment on Ubuntu system (requires sudo)"
	@echo "             Requires: FILE=<path-to-tar.gz>"
	@echo "  test      - Test Docker restoration process"
	@echo "             Requires: FILE=<path-to-tar.gz>"
	@echo "  clean     - Clean up temporary files and containers"
	@echo "  help      - Show this help message"
	@echo ""
	@echo "Usage examples:"
	@echo "  make setup"
	@echo "  make prepare PROFILE=extra"
	@echo "  make prepare PROFILE=mini NO_CACHE=1"
	@echo "  make package FILE=charles_home_extra.tar.gz"
	@echo "  sudo make restore FILE=charles_home_extra.tar.gz"
	@echo "  make test FILE=charles_home_extra.tar.gz"

# Initial setup
setup:
	@if [ ! -f config.env ]; then \
		cp config.env.example config.env; \
		echo "✅ Created config.env from example. Please edit it with your settings."; \
	else \
		echo "⚠️  config.env already exists. Skipping setup."; \
	fi

# Prepare online environment
# Usage: make prepare [PROFILE=mini|extra] [NO_CACHE=1]
prepare:
	@echo "🚀 Preparing online environment (profile: $(PROFILE))..."
	@if [ "$(NO_CACHE)" = "1" ]; then \
		PROFILE=$(PROFILE) ./scripts/prepare_online_env.sh --no-cache; \
	else \
		PROFILE=$(PROFILE) ./scripts/prepare_online_env.sh; \
	fi

# Package offline bundle
# Usage: make package [FILE=output.tar.gz]
package:
	@echo "📦 Packaging offline bundle..."
	@ARCHIVE_FILE=$(FILE) ./scripts/package_offline_bundle.sh

# Restore environment (requires sudo)
# Usage: sudo make restore FILE=charles_home_extra.tar.gz
restore:
	@if [ -z "$(FILE)" ]; then \
		echo "❌ FILE is required. Usage: sudo make restore FILE=charles_home_extra.tar.gz"; \
		exit 1; \
	fi
	@echo "🔄 Restoring from $(FILE)..."
	@ARCHIVE_FILE=$(FILE) ./scripts/restore_ubuntu_env.sh

# Test Docker restoration
# Usage: make test FILE=charles_home_extra.tar.gz
test:
	@if [ -z "$(FILE)" ]; then \
		echo "❌ FILE is required. Usage: make test FILE=charles_home_extra.tar.gz"; \
		exit 1; \
	fi
	@echo "🧪 Testing restoration from $(FILE)..."
	@ARCHIVE_FILE=$(FILE) ./tests/test_docker_restore.sh

# Clean up
clean:
	@echo "🧹 Cleaning up..."
	@docker stop manual_init_container_charles 2>/dev/null || true
	@docker rm manual_init_container_charles 2>/dev/null || true
	@docker stop test_offline_charles 2>/dev/null || true
	@docker rm test_offline_charles 2>/dev/null || true
	@docker rmi env-for-manual-init:charles 2>/dev/null || true
	@docker rmi offline-machine-base:charles 2>/dev/null || true
	@rm -f original_setup.sh
	@rm -f Dockerfile.restore
	@rm -rf charles_home_temp
	@echo "✅ Cleanup completed"

# Full workflow
workflow: setup prepare
	@echo ""
	@echo "🎉 Environment preparation started!"
	@echo "Next steps:"
	@echo "1. Run 'make package' to create the offline bundle"
	@echo "2. Run 'sudo make restore FILE=<archive>' to restore on target system"
