#!/bin/bash
# Runtime State Validation - Checks persistence layer and integrity

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/state.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/logging.sh"

# Configured persistence targets (override via environment if needed)
PE_PERSIST_PATHS=(
    "/etc/puppetlabs"
    "/opt/puppetlabs"
    "/var/log/puppetlabs"
)

# Validate persistence path availability and writability
validate_persistence_paths() {
    local all_valid=0
    
    for path in "${PE_PERSIST_PATHS[@]}"; do
        if [ ! -d "$path" ]; then
            log_integrity_issue "path_missing" "Required path not found: $path"
            all_valid=1
        elif [ ! -w "$path" ]; then
            log_integrity_issue "path_missing" "Required path not writable: $path"
            all_valid=1
        fi
    done
    
    return $all_valid
}

# Validate marker file integrity
validate_markers() {
    init_state_dir || {
        log_integrity_issue "path_missing" "Cannot initialize state directory"
        return 1
    }
    
    # Ensure state directory is writable
    if [ ! -w "${PE_STATE_DIR}" ]; then
        log_integrity_issue "path_missing" "State directory not writable: ${PE_STATE_DIR}"
        return 1
    fi
    
    # Check that only one state marker exists
    local marker_count=0
    [ -f "${PE_MARKER_INSTALLED}" ] && ((marker_count++)) || true
    [ -f "${PE_MARKER_FAILED}" ] && ((marker_count++)) || true
    [ -f "${PE_MARKER_RESET_REQUIRED}" ] && ((marker_count++)) || true
    [ -f "${PE_MARKER_INSTALLING}" ] && ((marker_count++)) || true
    
    if [ $marker_count -gt 1 ]; then
        log_integrity_issue "marker_missing" "Multiple state markers present (corrupt state directory)"
        return 1
    fi
    
    return 0
}

# Enhanced marker parseability check (T031a - marker validation part)
validate_marker_parseability() {
    # Verify each marker file is parseable if present
    if [ -f "${PE_MARKER_INSTALLED}" ]; then
        if [ ! -r "${PE_MARKER_INSTALLED}" ]; then
            log_integrity_issue "marker_missing" "Cannot read installed marker (permission denied)"
            return 1
        fi
    fi
    
    if [ -f "${PE_MARKER_FAILED}" ]; then
        if [ ! -r "${PE_MARKER_FAILED}" ]; then
            log_integrity_issue "marker_missing" "Cannot read failed marker (permission denied)"
            return 1
        fi
    fi
    
    return 0
}

# Enhanced version metadata validation (T031a - metadata format and compatibility checks)
validate_version_metadata() {
    local persisted_version=$(get_persisted_version 2>/dev/null || echo "")
    local image_version=$(get_persisted_image_version 2>/dev/null || echo "")
    
    # Check metadata parseability (T031a)
    if [ -n "$persisted_version" ]; then
        # Validate version format (basic: should not contain invalid chars)
        if echo "$persisted_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'; then
            : # Valid format
        else
            log_integrity_issue "metadata_corrupt" "Persisted version format invalid: $persisted_version"
            return 1
        fi
    fi
    
    if [ -n "$image_version" ]; then
        # Validate version format
        if echo "$image_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'; then
            : # Valid format
        else
            log_integrity_issue "metadata_corrupt" "Image version format invalid: $image_version"
            return 1
        fi
    fi
    
    # Check compatibility: if both versions exist, they must match (T032)
    if [ -n "$persisted_version" ] && [ -n "$image_version" ]; then
        if [ "$persisted_version" != "$image_version" ]; then
            log_integrity_issue "version_mismatch" \
                "Persisted version (${persisted_version}) does not match image version (${image_version}) - version mismatch detected"
            return 1
        fi
    fi
    
    return 0
}

# Restart state classifier for determining restart behavior (T031)
classify_restart_state() {
    local current_state=$(get_lifecycle_state)
    
    case "$current_state" in
        installed)
            echo "can_restore"
            return 0
            ;;
        installing)
            echo "requires_reset"
            return 0
            ;;
        failed)
            echo "requires_reset"
            return 0
            ;;
        reset-required)
            echo "requires_reset"
            return 0
            ;;
        uninitialized)
            echo "can_bootstrap"
            return 0
            ;;
        *)
            echo "unknown"
            return 1
            ;;
    esac
}

# Full integrity check (T031a - comprehensive validation)
check_integrity() {
    local state=$(get_lifecycle_state)
    
    log_message INFO "Validating runtime state integrity..."
    
    # Always check markers and paths
    validate_markers || return 1
    validate_marker_parseability || return 1
    validate_persistence_paths || return 1
    
    # If system is installed, verify version consistency and metadata format
    if [ "$state" = "installed" ]; then
        validate_version_metadata || return 1
    fi
    
    log_message INFO "Integrity validation: PASS"
    return 0
}

# Main: Called during startup to validate env before proceeding
main() {
    if ! check_integrity; then
        log_message ERROR "Runtime state validation failed - system in intervention-required state"
        return 1
    fi
}

main "$@"
