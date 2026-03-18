#!/bin/bash
# Bootstrap PE - First-time Installation and Configuration
# Runs once per container lifetime; subsequent starts restore from persisted state

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/scripts/lib/state.sh"
source "${script_dir}/scripts/lib/logging.sh"

# PE configuration location (typically mounted as volume)
PE_CONF_FILE="${PE_CONF_FILE:-/etc/puppetlabs/pe/pe.conf}"
PE_LICENSE_FILE="${PE_LICENSE_FILE:-/etc/puppetlabs/license.txt}"

require_systemd_runtime() {
    if ! systemctl status >/dev/null 2>&1; then
        log_message ERROR "PE installation requires systemd service management, but systemd is not running as PID 1 in this container"
        log_message ERROR "Current container model uses a shell/tini entrypoint, which cannot operate PE system services"
        log_message ERROR "A systemd-based container runtime is required for real PE installation and restore"
        return 1
    fi

    return 0
}

find_installer_root() {
    find "${PE_INSTALLER_STAGING}" -maxdepth 1 -mindepth 1 -type d -name 'puppet-enterprise-*' | head -1
}

# Preflight validation - check pe.conf and licensing (T023)
preflight_validation() {
    log_bootstrap_step "preflight_validation" "starting"
    
    # Check pe.conf exists
    if [ ! -f "${PE_CONF_FILE}" ]; then
        log_message ERROR "pe.conf not found at ${PE_CONF_FILE}"
        log_message ERROR "First-time installation requires pe.conf with configuration"
        log_bootstrap_step "preflight_validation" "failure"
        return 1
    fi
    
    if [ ! -r "${PE_CONF_FILE}" ]; then
        log_message ERROR "pe.conf not readable at ${PE_CONF_FILE}"
        log_bootstrap_step "preflight_validation" "failure"
        return 1
    fi
    
    # Check license (if required)
    if [ -f "${PE_LICENSE_FILE}" ] && [ ! -r "${PE_LICENSE_FILE}" ]; then
        log_message ERROR "License file not readable at ${PE_LICENSE_FILE}"
        log_bootstrap_step "preflight_validation" "failure"
        return 1
    fi
    
    log_bootstrap_step "preflight_validation" "success"
    return 0
}

# Validate console_password in pe.conf (T023a)
validate_console_password() {
    log_bootstrap_step "console_password_validation" "starting"
    
    # Check if console_password is present and non-empty
    if ! grep -q '^[[:space:]]*console_password' "${PE_CONF_FILE}"; then
        log_message ERROR "console_password not found in pe.conf"
        log_message ERROR "First-time PE installation requires console_password in pe.conf"
        log_message ERROR "Add line to pe.conf: console_password=your_secure_password"
        log_bootstrap_step "console_password_validation" "failure"
        return 1
    fi
    
    # Extract console_password value (handle whitespace and quoted values)
    local console_pwd
    console_pwd=$(grep '^[[:space:]]*console_password' "${PE_CONF_FILE}" | cut -d'=' -f2 | tr -d '[:space:]' | tr -d '"')
    
    if [ -z "$console_pwd" ]; then
        log_message ERROR "console_password in pe.conf is empty"
        log_message ERROR "Provide a non-empty console_password in pe.conf"
        log_bootstrap_step "console_password_validation" "failure"
        return 1
    fi
    
    log_message INFO "console_password validation: OK"
    log_bootstrap_step "console_password_validation" "success"
    return 0
}

# Write installing marker (T024)
write_installing_marker() {
    log_bootstrap_step "set_installing_marker" "starting"
    
    if ! set_installing_state; then
        log_message ERROR "Failed to set installing marker"
        log_bootstrap_step "set_installing_marker" "failure"
        return 1
    fi
    
    persist_image_version "$(grep PE_VERSION /puppet/state/.build-metadata | cut -d'=' -f2)"
    
    log_message INFO "Lifecycle state transitioning to: installing"
    log_bootstrap_step "set_installing_marker" "success"
    return 0
}

# Execute one-time installer (T025)
execute_installer() {
    log_bootstrap_step "execute_installer" "starting"
    
    # Verify installer staging directory exists
    if [ ! -d "${PE_INSTALLER_STAGING}" ]; then
        log_message ERROR "Installer staging directory not found: ${PE_INSTALLER_STAGING}"
        log_bootstrap_step "execute_installer" "failure"
        return 1
    fi

    if ! require_systemd_runtime; then
        log_bootstrap_step "execute_installer" "failure"
        return 1
    fi

    local installer_root
    installer_root="$(find_installer_root)"

    if [ -z "${installer_root}" ] || [ ! -x "${installer_root}/puppet-enterprise-installer" ]; then
        log_message ERROR "Could not find executable puppet-enterprise-installer under ${PE_INSTALLER_STAGING}"
        log_bootstrap_step "execute_installer" "failure"
        return 1
    fi
    
    log_message INFO "Found installer content in ${installer_root}"
    log_message INFO "Running PE installer in non-interactive mode"

    if ! (cd "${installer_root}" && ./puppet-enterprise-installer -c "${PE_CONF_FILE}" -y); then
        log_message ERROR "puppet-enterprise-installer returned a non-zero exit code"
        log_bootstrap_step "execute_installer" "failure"
        return 1
    fi
    
    log_bootstrap_step "execute_installer" "success"
    return 0
}

# Persist successful installation (T026)
persist_install_completion() {
    log_bootstrap_step "persist_install_completion" "starting"
    
    local installed_version
    installed_version=$(grep '^PE_VERSION' /puppet/state/.build-metadata | cut -d'=' -f2 2>/dev/null || echo "unknown")
    
    if ! persist_installed_version "${installed_version}"; then
        log_message ERROR "Failed to persist installed version"
        log_bootstrap_step "persist_install_completion" "failure"
        return 1
    fi
    
    if ! set_installed_state; then
        log_message ERROR "Failed to set installed marker"
        log_bootstrap_step "persist_install_completion" "failure"
        return 1
    fi
    
    log_message INFO "Installation marked as complete with version: ${installed_version}"
    log_bootstrap_step "persist_install_completion" "success"
    return 0
}

# Remove installer artifacts after verification (T026a)
cleanup_installer_artifacts() {
    log_bootstrap_step "cleanup_installer_artifacts" "starting"
    
    if [ -d "${PE_INSTALLER_STAGING}" ]; then
        log_message INFO "Removing installer artifacts from ${PE_INSTALLER_STAGING}"
        if rm -rf "${PE_INSTALLER_STAGING:?}"/*; then
            log_message INFO "Installer artifacts removed"
            log_bootstrap_step "cleanup_installer_artifacts" "success"
            return 0
        else
            log_message WARN "Failed to fully remove installer artifacts (non-fatal)"
            log_bootstrap_step "cleanup_installer_artifacts" "success"  # Non-fatal
            return 0
        fi
    fi
    
    log_bootstrap_step "cleanup_installer_artifacts" "success"
    return 0
}

# Handle bootstrap failure with state and guidance (T027)
handle_bootstrap_failure() {
    local step_name="$1"
    local error_detail="${2:-Unknown error}"
    
    log_message ERROR "Bootstrap failed at step: ${step_name}"
    log_message ERROR "Details: ${error_detail}"
    
    # Transition to failed state
    if ! set_failed_state; then
        log_message ERROR "Could not write failed state marker"
    fi
    
    # Emit clear remediation guidance
    log_message ERROR ""
    log_message ERROR "=== INSTALLATION FAILED ==="
    log_message ERROR "The PE container encountered an error during first-time setup."
    log_message ERROR ""
    log_message ERROR "To recover:"
    log_message ERROR "1. Review the logs above to identify the issue"
    log_message ERROR "2. Correct the configuration or environment"
    log_message ERROR "3. Reset the container state:"
    log_message ERROR "   docker exec pe-primary /puppet/reset-runtime-state.sh"
    log_message ERROR "4. Restart the container:"
    log_message ERROR "   docker restart pe-primary"
    log_message ERROR ""
    log_message ERROR "Note: Automatic retry is NOT attempted. Manual reset is required."
    log_message ERROR "==========================="
    
    return 1
}

# Main bootstrap orchestration
main() {
    log_message INFO "=== Puppet Enterprise Bootstrap Starting ==="
    log_message INFO "First-time setup: performing preflight and installation"
    
    # Step 1: Validate configuration exists (T023)
    if ! preflight_validation; then
        handle_bootstrap_failure "preflight_validation" "pe.conf or license validation failed"
        return 1
    fi
    
    # Step 2: Validate console password (T023a)
    if ! validate_console_password; then
        handle_bootstrap_failure "console_password_validation" "console_password missing or empty in pe.conf"
        return 1
    fi
    
    # Step 3: Mark as installing (T024)
    if ! write_installing_marker; then
        handle_bootstrap_failure "write_installing_marker" "Could not write lifecycle marker"
        return 1
    fi
    
    # Step 4: Execute installer (T025)
    if ! execute_installer; then
        handle_bootstrap_failure "execute_installer" "Installer execution failed"
        return 1
    fi
    
    # Step 5: Persist successful completion (T026)
    if ! persist_install_completion; then
        handle_bootstrap_failure "persist_install_completion" "Could not write install-complete marker"
        return 1
    fi
    
    # Step 6: Clean up installer (T026a)
    if ! cleanup_installer_artifacts; then
        handle_bootstrap_failure "cleanup_installer_artifacts" "Could not remove installer artifacts"
        return 1
    fi
    
    log_message INFO "=== Bootstrap Complete ==="
    log_message INFO "Puppet Enterprise installation successful"
    log_message INFO "Container is ready for operation"
    
    return 0
}

main "$@"
