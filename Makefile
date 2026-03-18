.PHONY: help build run reset-state healthcheck

# PE Container Build and Runtime Helpers
# Usage: make build PE_VERSION=2024.1 PE_INSTALLER_TAR_PATH=/path/to/installer.tar.gz

PE_VERSION ?= 
PE_INSTALLER_TAR_PATH ?= 
PE_INSTALLER_CONTEXT_PATH ?= container/assets/pe-installer/installer.tar.gz
CONTAINER_NAME ?= pe-primary
IMAGE_NAME ?= pe-container

help:
	@echo "Puppet Enterprise Container Commands"
	@echo ""
	@echo "Build targets:"
	@echo "  make build PE_VERSION=<version> PE_INSTALLER_TAR_PATH=<path/to/installer.tar.gz>"
	@echo ""
	@echo "Runtime targets:"
	@echo "  make run CONTAINER_NAME=<name> IMAGE_NAME=<image>"
	@echo "  make reset-state CONTAINER_NAME=<name>"
	@echo "  make healthcheck CONTAINER_NAME=<name>"
	@echo ""

build:
	@if [ -z "$(PE_VERSION)" ] || [ -z "$(PE_INSTALLER_TAR_PATH)" ]; then \
		echo "ERROR: PE_VERSION and PE_INSTALLER_TAR_PATH are required"; \
		echo "Usage: make build PE_VERSION=<version> PE_INSTALLER_TAR_PATH=<path>"; \
		exit 1; \
	fi
	@echo "[Build] Validating PE_VERSION and PE_INSTALLER_TAR_PATH..."
	@if [ ! -f "$(PE_INSTALLER_TAR_PATH)" ]; then \
		echo "ERROR: Installer file not found: $(PE_INSTALLER_TAR_PATH)"; \
		exit 1; \
	fi
	@if ! tar -tzf "$(PE_INSTALLER_TAR_PATH)" > /dev/null 2>&1; then \
		echo "ERROR: PE_INSTALLER_TAR_PATH is not a valid tar.gz archive: $(PE_INSTALLER_TAR_PATH)"; \
		exit 1; \
	fi
	@case "$(PE_INSTALLER_TAR_PATH)" in \
		/*) ;; \
		*) echo "ERROR: PE_INSTALLER_TAR_PATH must be an absolute path (start with /): $(PE_INSTALLER_TAR_PATH)"; exit 1 ;; \
	esac
	@mkdir -p "$(dir $(PE_INSTALLER_CONTEXT_PATH))"
	@echo "[Build] Staging installer into Docker build context: $(PE_INSTALLER_CONTEXT_PATH)"
	@cp -f "$(PE_INSTALLER_TAR_PATH)" "$(PE_INSTALLER_CONTEXT_PATH)"
	@echo "[Build] Starting Docker build with PE_VERSION=$(PE_VERSION)..."
	@set -e; \
	docker build \
		--build-arg PE_VERSION="$(PE_VERSION)" \
		--build-arg PE_INSTALLER_TAR_PATH="$(PE_INSTALLER_TAR_PATH)" \
		--build-arg PE_INSTALLER_TAR_CONTEXT_PATH="$(PE_INSTALLER_CONTEXT_PATH)" \
		--tag "$(IMAGE_NAME):$(PE_VERSION)" \
		--tag "$(IMAGE_NAME):latest" \
		--file container/Dockerfile \
		.; \
	status=$$?; \
	rm -f "$(PE_INSTALLER_CONTEXT_PATH)"; \
	if [ $$status -eq 0 ]; then \
		echo "[Build] SUCCESS: Image tagged as $(IMAGE_NAME):$(PE_VERSION)"; \
	else \
		echo "[Build] FAILED"; \
		exit $$status; \
	fi

run:
	docker run \
		--name "$(CONTAINER_NAME)" \
		--detach \
		--volume pe-config:/etc/puppetlabs \
		--volume pe-data:/opt/puppetlabs \
		--volume pe-logs:/var/log/puppetlabs \
		"$(IMAGE_NAME)"

reset-state:
	docker exec "$(CONTAINER_NAME)" /puppet/reset-runtime-state.sh

healthcheck:
	docker exec "$(CONTAINER_NAME)" /puppet/healthcheck.sh

# TODO: Additional targets for compose stack management
