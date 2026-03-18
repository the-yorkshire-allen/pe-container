#!/bin/bash
# Structured Logging and Status Helpers for Operator Visibility

# Log message with severity
log_message() {
    local severity="$1"
    local message="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    case "$severity" in
        INFO)
            echo "[${timestamp}] INFO: ${message}" >&1
            ;;
        WARN)
            echo "[${timestamp}] WARN: ${message}" >&2
            ;;
        ERROR)
            echo "[${timestamp}] ERROR: ${message}" >&2
            ;;
        CRITICAL)
            echo "[${timestamp}] CRITICAL: ${message}" >&2
            ;;
        *)
            echo "[${timestamp}] ${message}" >&1
            ;;
    esac
}

# Map outcome state to operator-visible message
startup_outcome_message() {
    local state="$1"
    local additional_context="$2"
    
    case "$state" in
        installing)
            log_message INFO "Puppet Enterprise installation in progress... (First boot)"
            [ -n "$additional_context" ] && log_message INFO "  Details: ${additional_context}"
            ;;
        failed)
            log_message ERROR "Puppet Enterprise installation FAILED"
            log_message ERROR "The system entered a failed state. Manual operator intervention required."
            log_message ERROR "To recover: docker exec CONTAINER /puppet/reset-runtime-state.sh && docker restart CONTAINER"
            [ -n "$additional_context" ] && log_message ERROR "  Reason: ${additional_context}"
            ;;
        installed|restored)
            log_message INFO "Puppet Enterprise running from persisted state"
            [ -n "$additional_context" ] && log_message INFO "  Version: ${additional_context}"
            ;;
        reset-required)
            log_message WARN "Puppet Enterprise requires operator reset before restart"
            log_message WARN "The system detected a condition requiring explicit reset (e.g., partial state, version mismatch)."
            log_message WARN "To reset: docker exec CONTAINER /puppet/reset-runtime-state.sh && docker restart CONTAINER"
            [ -n "$additional_context" ] && log_message WARN "  Condition: ${additional_context}"
            ;;
        uninitialized)
            log_message INFO "Puppet Enterprise container ready for first-time setup"
            log_message INFO "Provide pe.conf (with console_password) and restart container to begin installation"
            [ -n "$additional_context" ] && log_message INFO "  ${additional_context}"
            ;;
        *)
            log_message WARN "Puppet Enterprise in unknown state: ${state}"
            ;;
    esac
}

# Log component status during installation
log_bootstrap_step() {
    local step_name="$1"
    local status="$2"  # "starting", "success", "failure"
    
    case "$status" in
        starting)
            log_message INFO "[Bootstrap] Starting: ${step_name}"
            ;;
        success)
            log_message INFO "[Bootstrap] Success: ${step_name}"
            ;;
        failure)
            log_message ERROR "[Bootstrap] Failed: ${step_name}"
            ;;
        *)
            log_message INFO "[Bootstrap] ${step_name}: ${status}"
            ;;
    esac
}

# Emit continuity signal (connected nodes visibility)
log_node_continuity_signal() {
    local last_checkin="$1"
    local connected_node_count="$2"
    
    if [ -z "$last_checkin" ] || [ -z "$connected_node_count" ]; then
        log_message WARN "Node continuity data unavailable (first startup or data missing)"
        return 0
    fi
    
    log_message INFO "Connected nodes continuity signal: ${connected_node_count} known nodes, last check-in at ${last_checkin}"
}

# Log integrity violation with recommendation
log_integrity_issue() {
    local issue_type="$1"
    local details="$2"
    
    case "$issue_type" in
        marker_missing)
            log_message ERROR "Integrity check failed: Required marker missing (${details})"
            ;;
        version_mismatch)
            log_message ERROR "Integrity check failed: Version mismatch (${details})"
            ;;
        path_missing)
            log_message ERROR "Integrity check failed: Required path missing or not writable (${details})"
            ;;
        metadata_corrupt)
            log_message ERROR "Integrity check failed: Metadata unparseable (${details})"
            ;;
        runtime_missing)
            log_message ERROR "Integrity check failed: Installed runtime artifacts missing (${details})"
            ;;
        *)
            log_message ERROR "Integrity check failed: ${issue_type} (${details})"
            ;;
    esac
}

export -f log_message
export -f startup_outcome_message
export -f log_bootstrap_step
export -f log_node_continuity_signal
export -f log_integrity_issue
