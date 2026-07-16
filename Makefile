# ==============================================================================
# Devbox Makefile
# Provides convenient shortcuts for common operations
# ==============================================================================

# Build profile for Docker image (mini or extra)
PROFILE ?= extra

.PHONY: help prepare package restore test clean setup workflow

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
	@echo "             FILE=<tar.gz> restores a local archive (offline)"
	@echo "             Without FILE, downloads from GitHub Releases (PROFILE, VERSION)"
	@echo "             CURRENT_USER=1 restores into the invoking user (default: charles)"
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
	@echo "  sudo make restore FILE=charles_home_extra.tar.gz    # local archive (offline)"
	@echo "  sudo make restore CURRENT_USER=1                    # auto-download latest"
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

# Restore environment (requires sudo) — thin wrapper over scripts/restore.sh,
# which is the real entry point and needs no make:
#   FILE given  → restore from a local archive (offline-friendly, no download)
#   FILE absent → download the bundle matching this host's arch from GitHub
#                 Releases first (PROFILE=mini|extra, VERSION=<tag>)
# Common flags: CURRENT_USER=1 ASSUME_YES=1 SKIP_OS_CHECK=1
restore:
	@ARCHIVE_FILE=$(FILE) PROFILE=$(PROFILE) VERSION=$(VERSION) CURRENT_USER=$(CURRENT_USER) ASSUME_YES=$(ASSUME_YES) SKIP_OS_CHECK=$(SKIP_OS_CHECK) ./scripts/restore.sh

# Test Docker restoration
# Usage: make test FILE=charles_home_extra.tar.gz
test:
	@if [ -z "$(FILE)" ]; then \
		echo "❌ FILE is required. Usage: make test FILE=charles_home_extra.tar.gz"; \
		exit 1; \
	fi
	@echo "🧪 Testing restoration from $(FILE)..."
	@ARCHIVE_FILE=$(FILE) ./tests/test_docker_restore.sh

# Clean up — container/image names derive from USERNAME in config.env
# (falling back to 'charles'), matching what the scripts actually create.
clean:
	@echo "🧹 Cleaning up..."
	@U=$${USERNAME:-$$([ -f config.env ] && . ./config.env; echo $${USERNAME:-charles})}; \
	docker stop manual_init_container_$$U test_offline_$$U 2>/dev/null || true; \
	docker rm manual_init_container_$$U test_offline_$$U 2>/dev/null || true; \
	docker rmi env-for-manual-init:$$U offline-machine-base:$$U 2>/dev/null || true; \
	rm -f original_setup.sh Dockerfile.restore; \
	rm -rf $${U}_home_temp
	@echo "✅ Cleanup completed"

# Full workflow
workflow: setup prepare
	@echo ""
	@echo "🎉 Environment preparation started!"
	@echo "Next steps:"
	@echo "1. Run 'make package' to create the offline bundle"
	@echo "2. Run 'sudo make restore FILE=<archive>' to restore on target system"
