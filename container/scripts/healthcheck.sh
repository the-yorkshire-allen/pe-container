#!/bin/bash
# Healthcheck Probe - Reports startup health outcomes to orchestrator

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/lib/state.sh"
source "${script_dir}/lib/logging.sh"
source "${script_dir}/lib/status-probe.sh"

# Emit startup outcome health status
healthcheck() {
    local state=$(get_lifecycle_state)
    local exit_code
    
    # Map state to health probe output and exit code
    case "$state" in
        installing)
            log_message INFO "[Healthcheck] Installation in progress"
            exit_code=2  # Starting state, allow grace period
            ;;
        installed)
            log_message INFO "[Healthcheck] Installation complete - services running"
            exit_code=0  # Healthy
            ;;
        failed)
            log_message ERROR "[Healthcheck] Installation FAILED - manual intervention required"
            exit_code=1  # Unhealthy
            ;;
        reset-required)
            log_message ERROR "[Healthcheck] Reset required - manual intervention needed"
            exit_code=1  # Unhealthy
            ;;
        uninitialized)
            log_message INFO "[Healthcheck] Uninitialized - ready for setup"
            exit_code=2  # Starting, allow grace period
            ;;
        *)
            log_message ERROR "[Healthcheck] Unknown state: ${state}"
            exit_code=1  # Unhealthy
            ;;
    esac
    
    return "$exit_code"
}

main() {
    healthcheck "$@"
}

main "$@"
