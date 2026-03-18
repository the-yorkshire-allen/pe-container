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

# Validate version metadata consistency
validate_version_metadata() {
    local persisted_version=$(get_persisted_version)
    local image_version=$(get_persisted_image_version)
    
    # If versions exist, they must match
    if [ -n "$persisted_version" ] && [ -n "$image_version" ]; then
        if [ "$persisted_version" != "$image_version" ]; then
            log_integrity_issue "version_mismatch" \
                "Persisted version (${persisted_version}) does not match image version (${image_version})"
            return 1
        fi
    fi
    
    return 0
}

# Full integrity check
check_integrity() {
    local state=$(get_lifecycle_state)
    
    log_message INFO "Validating runtime state integrity..."
    
    # Always check markers and paths
    validate_markers || return 1
    validate_persistence_paths || return 1
    
    # If system is installed, verify version consistency
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
