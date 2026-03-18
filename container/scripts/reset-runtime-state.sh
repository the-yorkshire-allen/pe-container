#!/bin/bash
# Runtime State Reset - Operator-controlled cleanup for reinstallation

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/scripts/lib/state.sh"
source "${script_dir}/scripts/lib/logging.sh"

# Safe reset of all lifecycle markers and metadata
reset_runtime_state() {
    log_message WARN "=== Puppet Enterprise Runtime State Reset ==="
    log_message WARN "This operation will clear all installation state markers."
    log_message WARN "The next container startup will re-initialize from scratch."
    log_message WARN ""
    
    # Initialize state directory
    if ! init_state_dir; then
        log_message ERROR "Failed to initialize state directory"
        return 1
    fi
    
    # Clear all markers
    clear_all_markers
    
    # Clear version metadata
    rm -f "${PE_VERSION_FILE}" "${PE_IMAGE_VERSION_FILE}" 2>/dev/null || true
    
    log_message INFO "State reset complete - all markers cleared"
    log_message INFO "Container is now in 'uninitialized' state"
    log_message INFO "On next startup, you MUST provide pe.conf (with console_password)"
    
    return 0
}

main() {
    reset_runtime_state "$@"
}

main "$@"
