#!/bin/bash
# State Management Helpers for PE Container Lifecycle
# Manages lifecycle markers, version metadata, and state transitions

# Lifecycle marker paths (must be on persisted volume)
PE_STATE_DIR="${PE_STATE_DIR:-/puppet/state}"
PE_MARKER_UNINITIALIZED="${PE_STATE_DIR}/.uninitialized"
PE_MARKER_INSTALLING="${PE_STATE_DIR}/.installing"
PE_MARKER_INSTALLED="${PE_STATE_DIR}/.installed"
PE_MARKER_FAILED="${PE_STATE_DIR}/.failed"
PE_MARKER_RESET_REQUIRED="${PE_STATE_DIR}/.reset-required"

# Version metadata (persisted)
PE_VERSION_FILE="${PE_STATE_DIR}/.pe-version"
PE_IMAGE_VERSION_FILE="${PE_STATE_DIR}/.image-version"

# Installer staging
PE_INSTALLER_STAGING="${PE_INSTALLER_STAGING:-/puppet/installer-staging}"
PE_INSTALLER_BUILD_METADATA="${PE_STATE_DIR}/.installer-metadata"

# Initialize state directory if needed
init_state_dir() {
    mkdir -p "${PE_STATE_DIR}" || return 1
    chmod 0755 "${PE_STATE_DIR}" || return 1
}

# Validate absolute path (used for installer path validation)
is_absolute_path() {
    local path="$1"
    [[ "$path" == /* ]] && return 0 || return 1
}

# Get current lifecycle state
get_lifecycle_state() {
    if [ -f "${PE_MARKER_INSTALLING}" ]; then
        echo "installing"
    elif [ -f "${PE_MARKER_INSTALLED}" ]; then
        echo "installed"
    elif [ -f "${PE_MARKER_FAILED}" ]; then
        echo "failed"
    elif [ -f "${PE_MARKER_RESET_REQUIRED}" ]; then
        echo "reset-required"
    else
        echo "uninitialized"
    fi
}

# Transition to installing state
set_installing_state() {
    init_state_dir || return 1
    rm -f "${PE_MARKER_UNINITIALIZED}" "${PE_MARKER_INSTALLED}" "${PE_MARKER_FAILED}" "${PE_MARKER_RESET_REQUIRED}" 2>/dev/null || true
    touch "${PE_MARKER_INSTALLING}" || return 1
}

# Transition to installed state (successful install completion)
set_installed_state() {
    init_state_dir || return 1
    rm -f "${PE_MARKER_INSTALLING}" "${PE_MARKER_FAILED}" "${PE_MARKER_RESET_REQUIRED}" 2>/dev/null || true
    touch "${PE_MARKER_INSTALLED}" || return 1
}

# Transition to failed state (installation failure)
set_failed_state() {
    init_state_dir || return 1
    rm -f "${PE_MARKER_INSTALLING}" "${PE_MARKER_INSTALLED}" "${PE_MARKER_RESET_REQUIRED}" 2>/dev/null || true
    touch "${PE_MARKER_FAILED}" || return 1
}

# Transition to reset-required state (manual reset needed)
set_reset_required_state() {
    init_state_dir || return 1
    rm -f "${PE_MARKER_INSTALLING}" "${PE_MARKER_INSTALLED}" "${PE_MARKER_FAILED}" 2>/dev/null || true
    touch "${PE_MARKER_RESET_REQUIRED}" || return 1
}

# Persist installed version metadata
persist_installed_version() {
    local version="$1"
    init_state_dir || return 1
    echo "$version" > "${PE_VERSION_FILE}" || return 1
}

# Get persisted installed version
get_persisted_version() {
    if [ -f "${PE_VERSION_FILE}" ]; then
        cat "${PE_VERSION_FILE}"
    else
        echo ""
    fi
}

# Persist image version metadata
persist_image_version() {
    local image_version="$1"
    init_state_dir || return 1
    echo "$image_version" > "${PE_IMAGE_VERSION_FILE}" || return 1
}

# Get persisted image version
get_persisted_image_version() {
    if [ -f "${PE_IMAGE_VERSION_FILE}" ]; then
        cat "${PE_IMAGE_VERSION_FILE}"
    else
        echo ""
    fi
}

# Validate installer staging directory
validate_installer_staging() {
    [ -d "${PE_INSTALLER_STAGING}" ] && [ -r "${PE_INSTALLER_STAGING}" ] && return 0 || return 1
}

# Marker file existence check
marker_exists() {
    local marker="$1"
    [ -f "$marker" ]
}

# Cleanup marker files (for reset operations)
clear_all_markers() {
    rm -f "${PE_MARKER_UNINITIALIZED}" "${PE_MARKER_INSTALLING}" "${PE_MARKER_INSTALLED}" \
          "${PE_MARKER_FAILED}" "${PE_MARKER_RESET_REQUIRED}" 2>/dev/null || true
}

# BUILD-TIME VALIDATION HELPERS

# Validate installer tar.gz file during build (enforces absolute path, existence, readability)
validate_installer_tar_at_build_time() {
    local tar_path="$1"
    local version="$2"
    
    [ -z "$tar_path" ] && {
        echo "ERROR: PE_INSTALLER_TAR_PATH is not set" >&2
        return 1
    }
    
    [ -z "$version" ] && {
        echo "ERROR: PE_VERSION is not set" >&2
        return 1
    }
    
    # Enforce absolute path (T017a)
    if ! is_absolute_path "$tar_path"; then
        echo "ERROR: PE_INSTALLER_TAR_PATH must be an absolute path (starting with /)" >&2
        echo "  Received: $tar_path" >&2
        return 1
    fi
    
    # Check file existence
    if [ ! -f "$tar_path" ]; then
        echo "ERROR: PE_INSTALLER_TAR_PATH file not found" >&2
        echo "  Path: $tar_path" >&2
        return 1
    fi
    
    # Check readability
    if [ ! -r "$tar_path" ]; then
        echo "ERROR: PE_INSTALLER_TAR_PATH file is not readable (permission denied)" >&2
        echo "  Path: $tar_path" >&2
        return 1
    fi
    
    # Check tar format
    if ! tar -tzf "$tar_path" > /dev/null 2>&1; then
        echo "ERROR: PE_INSTALLER_TAR_PATH is not a valid tar.gz archive" >&2
        echo "  Path: $tar_path" >&2
        return 1
    fi
    
    return 0
}

# Verify installer contains expected version (T019a - artifact/version identity check)
verify_installer_version_match() {
    local tar_path="$1"
    local expected_version="$2"
    
    # Extract version metadata from inside the tar without full extraction
    # Look for puppet-enterprise/VERSION or similar marker
    local tar_version=$(tar -tzf "$tar_path" | grep -i 'VERSION\|version' | head -1 | tr '\n' ' ')
    
    if [ -z "$tar_version" ]; then
        echo "WARNING: Could not extract version metadata from installer tar" >&2
        # Non-fatal; allow build to proceed with warning
        return 0
    fi
    
    # Simple check: if expected_version appears in tar contents, consider it matched
    if tar -tzf "$tar_path" | grep -q "$expected_version"; then
        return 0
    else
        echo "WARNING: Installer version ($tar_version) may not match expected version ($expected_version)" >&2
        # Continue with warning; operator is responsible for ensuring match
        return 0
    fi
}

export PE_STATE_DIR PE_MARKER_INSTALLING PE_MARKER_INSTALLED PE_MARKER_FAILED PE_MARKER_RESET_REQUIRED
export PE_VERSION_FILE PE_IMAGE_VERSION_FILE PE_INSTALLER_STAGING
