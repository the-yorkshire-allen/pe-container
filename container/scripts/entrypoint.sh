#!/bin/bash
# Container Entrypoint - Command Dispatcher and Lifecycle Orchestrator

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/lib/state.sh"
source "${script_dir}/lib/logging.sh"

# Entrypoint command dispatcher
dispatch_command() {
    local command="${1:-start}"
    
    case "$command" in
        start)
            # Main startup: validate state, conditionally bootstrap or restore
            startup_orchestrator
            ;;
        healthcheck)
            # Health status probe for Docker/Kubernetes
            healthcheck_command
            ;;
        reset-runtime-state)
            # Operator-triggered clean reset
            reset_state_command
            ;;
        *)
            log_message ERROR "Unknown command: ${command}"
            log_message INFO "Valid commands: start, healthcheck, reset-runtime-state"
            return 1
            ;;
    esac
}

# Startup orchestration - classifies state and branches bootstrap vs restore (T031-T035)
startup_orchestrator() {
    local state
    state=$(get_lifecycle_state)
    
    log_message INFO "PE container startup - lifecycle state: ${state}"
    
    case "$state" in
        uninitialized)
            # First-time setup: validate config and launch bootstrap (T028)
            log_message INFO "First-time setup detected - preparing to bootstrap"
            
            # Source and execute bootstrap workflow
            if [ -x "${script_dir}/bootstrap-pe.sh" ]; then
                "${script_dir}/bootstrap-pe.sh" || return 1
            else
                log_message ERROR "Bootstrap script not found or not executable"
                return 1
            fi
            return 0
            ;;
        installing)
            # Interrupted installation: fail and require reset (T033 - block auto-retry)
            log_message ERROR "Container found in interrupted 'installing' state"
            log_message ERROR "This indicates a prior bootstrap attempt was interrupted"
            log_message ERROR "Automatic retry is NOT performed to prevent cascading failures"
            set_reset_required_state
            log_message ERROR "Please run: docker exec CONTAINER /puppet/reset-runtime-state.sh && docker restart CONTAINER"
            return 1
            ;;
        installed)
            # Successful prior install: restore from persisted state (T034)
            log_message INFO "Restoring from persisted state (skipping installer)..."
            
            # T032: Enforce version match against image metadata
            if ! verify_installer_version_match; then
                log_message ERROR "Version mismatch detected between persisted state and image"
                log_message ERROR "Cannot proceed with mismatched versions"
                set_reset_required_state
                log_message ERROR "Please run: docker exec CONTAINER /puppet/reset-runtime-state.sh && docker restart CONTAINER"
                return 1
            fi
            
            # T035: Post-install pe.conf drift is ignored (no reinstall triggered by config changes)
            log_message INFO "Note: Changes to pe.conf after install are not applied (version-locked persistence)"
            log_message INFO "PE is running from persisted installed state"
            
            # TODO: Restore PE services from persisted state
            return 0
            ;;
        failed)
            # Prior install failed: require explicit reset (T033 - block auto-retry)
            log_message ERROR "Container found in 'failed' state from prior installation attempt"
            log_message ERROR "Automatic retry is blocked. Manual intervention required."
            log_message ERROR "Please run: docker exec CONTAINER /puppet/reset-runtime-state.sh && docker restart CONTAINER"
            return 1
            ;;
        reset-required)
            # Manual intervention needed
            log_message ERROR "Container requires operator intervention"
            log_message ERROR "Persistent state has been marked for reset (e.g., version mismatch or partial failure)"
            log_message ERROR "Please run: docker exec CONTAINER /puppet/reset-runtime-state.sh && docker restart CONTAINER"
            return 1
            ;;
        *)
            log_message ERROR "Unknown lifecycle state: ${state}"
            return 1
            ;;
    esac
}

# Healthcheck command
healthcheck_command() {
    # TODO: Implement health status - check /puppet/state for markers and PE services
    log_message INFO "Healthcheck requested"
    return 0
}

# Reset operation
reset_state_command() {
    log_message WARN "Operator reset requested - clearing all lifecycle markers"
    clear_all_markers
    rm -f "${PE_VERSION_FILE}" "${PE_IMAGE_VERSION_FILE}" 2>/dev/null || true
    log_message INFO "Reset complete - container is now in 'uninitialized' state. Restart to begin fresh bootstrap."
    return 0
}

# Entry point
main() {
    dispatch_command "$@"
}

main "$@"
