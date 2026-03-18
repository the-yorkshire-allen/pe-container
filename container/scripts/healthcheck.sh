#!/bin/bash
# Healthcheck Probe - Reports startup health outcomes to orchestrator

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/scripts/lib/state.sh"
source "${script_dir}/scripts/lib/logging.sh"
source "${script_dir}/scripts/lib/status-probe.sh"

# Emit startup outcome health status
healthcheck() {
    local state
    state=$(get_lifecycle_state)
    local exit_code
    
    # Map state to health probe output and exit code
    case "$state" in
        installing)
            log_message INFO "[Healthcheck] Installation in progress"
            exit_code=2  # Starting state, allow grace period
            ;;
        installed)
            if command -v /opt/puppetlabs/bin/puppet >/dev/null 2>&1 && \
               /opt/puppetlabs/bin/puppet infrastructure status --log_level=err >/dev/null 2>&1; then
                log_message INFO "[Healthcheck] Installation complete - PE infrastructure is healthy"
                exit_code=0  # Healthy
            else
                log_message ERROR "[Healthcheck] Installed state detected but PE infrastructure is not yet healthy"
                exit_code=1
            fi
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
