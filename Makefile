# ==============================================================================
# Devbox Makefile
# Provides convenient shortcuts for common operations
# ==============================================================================

.PHONY: help prepare package restore test clean setup

# Default target
help:
	@echo "Devbox - Portable Development Environment"
	@echo ""
	@echo "Available targets:"
	@echo "  setup     - Initial setup (copy config.env.example to config.env)"
	@echo "  prepare   - Prepare online environment for manual initialization"
	@echo "  package   - Package the initialized environment into offline bundle"
	@echo "  restore   - Restore environment on Ubuntu system (requires sudo)"
	@echo "  test      - Test Docker restoration process"
	@echo "  clean     - Clean up temporary files and containers"
	@echo "  help      - Show this help message"
	@echo ""
	@echo "Usage examples:"
	@echo "  make setup"
	@echo "  make prepare"
	@echo "  sudo make restore"
	@echo "  make test"

# Initial setup
setup:
	@if [ ! -f config.env ]; then \
		cp config.env.example config.env; \
		echo "✅ Created config.env from example. Please edit it with your settings."; \
	else \
		echo "⚠️  config.env already exists. Skipping setup."; \
	fi

# Prepare online environment
prepare:
	@echo "🚀 Preparing online environment..."
	@./scripts/prepare_online_env.sh

# Package offline bundle
package:
	@echo "📦 Packaging offline bundle..."
	@./scripts/package_offline_bundle.sh

# Restore environment (requires sudo)
restore:
	@echo "🔄 Restoring environment..."
	@./scripts/restore_ubuntu_env.sh

# Test Docker restoration
test:
	@echo "🧪 Testing Docker restoration..."
	@./tests/test_docker_restore.sh

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
	@echo "1. Follow the instructions to manually initialize the container"
	@echo "2. Run 'make package' to create the offline bundle"
	@echo "3. Run 'sudo make restore' to restore on target system" 
