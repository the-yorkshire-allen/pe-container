#!/bin/bash
# Health Status Probe for PE Container (Kubernetes-friendly)

# Status probe: /status/v1/simple endpoint simulation
status_probe_simple() {
    local state_file="${1:-./.pe-state}"
    
    # Determine current health state
    if [ -f "${state_file}/.installed" ]; then
        # Attempt to contact PE services on known ports
        # This is a placeholder; actual implementation depends on PE service availability
        if nc -w1 -z localhost 8140 2>/dev/null && \
           nc -w1 -z localhost 443 2>/dev/null; then
            echo "{\\"status\\":\\"running\\",\\"state\\":\\"installed\\"}" 
            return 0
        else
            echo "{\\"status\\":\\"degraded\\",\\"state\\":\\"installed\\",\\"detail\\":\\"services-not-responding\\"}"
            return 1
        fi
    elif [ -f "${state_file}/.installing" ]; then
        echo "{\\"status\\":\\"initializing\\",\\"state\\":\\"installing\\"}"
        return 2
    elif [ -f "${state_file}/.failed" ]; then
        echo "{\\"status\\":\\"error\\",\\"state\\":\\"failed\\"}"
        return 1
    elif [ -f "${state_file}/.reset-required" ]; then
        echo "{\\"status\\":\\"error\\",\\"state\\":\\"reset-required\\",\\"action\\":\\"reset-runtime-state\\"}"
        return 1
    else
        echo "{\\"status\\":\\"ready\\",\\"state\\":\\"uninitialized\\"}"
        return 2
    fi
}

# Health check return codes (Docker-compatible)
# 0 = healthy, 1 = unhealthy, 2 = starting/initializing (allow grace period)
healthcheck_exit_code() {
    local state="$1"
    
    case "$state" in
        installed)
            echo 0
            ;;
        installing|uninitialized)
            echo 2
            ;;
        failed|reset-required)
            echo 1
            ;;
        *)
            echo 1
            ;;
    esac
}

export -f status_probe_simple
export -f healthcheck_exit_code
