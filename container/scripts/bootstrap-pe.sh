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
R10K_PRIVATE_KEY_PATH="${R10K_PRIVATE_KEY_PATH:-/etc/puppetlabs/keys/r10k-deploy-key}"
R10K_PRIVATE_KEY_STAGING="${R10K_PRIVATE_KEY_STAGING:-/puppet/state/r10k/r10k-deploy-key.host}"

# Initial Code Manager deployment configuration
# If no token is provided, initial code deploy is skipped (non-fatal).
CODE_MANAGER_INITIAL_DEPLOY="${CODE_MANAGER_INITIAL_DEPLOY:-true}"
CODE_MANAGER_DEPLOY_METHOD="${CODE_MANAGER_DEPLOY_METHOD:-bootstrap-deploys}" # bootstrap-deploys|bootstrap-webhook|auto|deploys|webhook
CODE_MANAGER_DEPLOY_TOKEN="${CODE_MANAGER_DEPLOY_TOKEN:-}"
CODE_MANAGER_DEPLOY_PASSWORD="${CODE_MANAGER_DEPLOY_PASSWORD:-}"
CODE_MANAGER_WEBHOOK_TOKEN="${CODE_MANAGER_WEBHOOK_TOKEN:-}"
CODE_MANAGER_DEPLOY_USER="${CODE_MANAGER_DEPLOY_USER:-code_deploy}"
CODE_MANAGER_BOOTSTRAP_LOGIN="${CODE_MANAGER_BOOTSTRAP_LOGIN:-admin}"
CODE_MANAGER_BOOTSTRAP_PASSWORD="${CODE_MANAGER_BOOTSTRAP_PASSWORD:-}"
CODE_MANAGER_TOKEN_LIFETIME="${CODE_MANAGER_TOKEN_LIFETIME:-17520h}" # 2 years
CODE_MANAGER_TOKEN_LABEL="${CODE_MANAGER_TOKEN_LABEL:-bootstrap-deploys-token}"
CODE_MANAGER_DEPLOY_PAYLOAD="${CODE_MANAGER_DEPLOY_PAYLOAD:-{\"deploy-all\": true}}"
CODE_MANAGER_WEBHOOK_PAYLOAD="${CODE_MANAGER_WEBHOOK_PAYLOAD:-{}}"

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

extract_installer_archive() {
  log_bootstrap_step "extract_installer_archive" "starting"

  local installer_archive
  local archive_size_bytes
  local extract_start_epoch
  local extract_end_epoch
  local extract_duration_seconds
  installer_archive="${PE_INSTALLER_STAGING}/installer.tar.gz"

  if [ ! -f "${installer_archive}" ]; then
    log_message ERROR "Installer archive not found: ${installer_archive}"
    log_bootstrap_step "extract_installer_archive" "failure"
    return 1
  fi

  if [ ! -r "${installer_archive}" ]; then
    log_message ERROR "Installer archive is not readable: ${installer_archive}"
    log_bootstrap_step "extract_installer_archive" "failure"
    return 1
  fi

  archive_size_bytes=$(stat -c '%s' "${installer_archive}" 2>/dev/null || echo "unknown")
  log_message INFO "Installer archive size: ${archive_size_bytes} bytes (${installer_archive})"

  # Keep only known bootstrap artifacts before extraction.
  find "${PE_INSTALLER_STAGING}" -mindepth 1 -maxdepth 1 ! -name 'installer.tar.gz' ! -name '.build-metadata' -exec rm -rf {} +

  extract_start_epoch=$(date +%s)
  if ! tar -xzf "${installer_archive}" -C "${PE_INSTALLER_STAGING}"; then
    log_message ERROR "Failed to extract installer archive at ${installer_archive}"
    log_bootstrap_step "extract_installer_archive" "failure"
    return 1
  fi
  extract_end_epoch=$(date +%s)
  extract_duration_seconds=$((extract_end_epoch - extract_start_epoch))

  local installer_root
  installer_root="$(find_installer_root)"
  if [ -z "${installer_root}" ] || [ ! -x "${installer_root}/puppet-enterprise-installer" ]; then
    log_message ERROR "Installer extraction completed, but executable payload was not found"
    log_bootstrap_step "extract_installer_archive" "failure"
    return 1
  fi

  log_message INFO "Installer archive extracted to ${installer_root} in ${extract_duration_seconds}s"
  log_bootstrap_step "extract_installer_archive" "success"
  return 0
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

  local console_pwd_line
  console_pwd_line=$(grep -E '^[[:space:]]*("console_admin_password"|"puppet_enterprise::console_password"|console_password)[[:space:]]*=' "${PE_CONF_FILE}" | head -n 1 || true)

  # Check if console_password is present and non-empty
  if [ -z "${console_pwd_line}" ]; then
    log_message ERROR "console_password not found in pe.conf"
    log_message ERROR "First-time PE installation requires console_password in pe.conf"
    log_message ERROR "Add line to pe.conf: \"console_admin_password\"=your_secure_password"
    log_bootstrap_step "console_password_validation" "failure"
    return 1
  fi

  # Extract console_password value (handle whitespace and quoted values)
  local console_pwd
  console_pwd=$(printf '%s\n' "${console_pwd_line}" | cut -d'=' -f2- | tr -d '[:space:]' | tr -d '"')

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

extract_first_hocon_string_value() {
  local assignment_line="${1}"
  local rhs
  local first_quoted

  rhs=$(printf '%s\n' "${assignment_line}" | sed -E 's/^[^=]*=[[:space:]]*//')
  first_quoted=$(printf '%s\n' "${rhs}" | grep -oE '"[^"]+"' | head -n 1 | tr -d '"')

  if [ -n "${first_quoted}" ]; then
    printf '%s\n' "${first_quoted}"
    return 0
  fi

  printf '%s\n' "${rhs}" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//'
}

validate_r10k_private_key() {
  log_bootstrap_step "r10k_private_key_validation" "starting"

  local key_line
  key_line=$(grep -E '^[[:space:]]*("puppet_enterprise::profile::master::r10k_private_key"|r10k_private_key)[[:space:]]*=' "${PE_CONF_FILE}" | head -n 1 || true)

  # Key validation is only required when r10k_private_key is configured in pe.conf.
  if [ -z "${key_line}" ]; then
    log_message INFO "r10k_private_key not configured in pe.conf; skipping private key validation"
    log_bootstrap_step "r10k_private_key_validation" "success"
    return 0
  fi

  local configured_key_path
  configured_key_path=$(extract_first_hocon_string_value "${key_line}")

  if [ -z "${configured_key_path}" ]; then
    log_message ERROR "r10k_private_key is configured but empty in pe.conf"
    log_bootstrap_step "r10k_private_key_validation" "failure"
    return 1
  fi

  if [ "${configured_key_path}" != "${R10K_PRIVATE_KEY_PATH}" ]; then
    log_message WARN "R10K_PRIVATE_KEY_PATH (${R10K_PRIVATE_KEY_PATH}) does not match pe.conf r10k_private_key (${configured_key_path})"
    log_message WARN "Bootstrap validation will use pe.conf path: ${configured_key_path}"
  fi

  if [ ! -f "${configured_key_path}" ]; then
    log_message ERROR "r10k private key file not found at ${configured_key_path}"
    log_message ERROR "Mount your key into the container (default: /etc/puppetlabs/keys/r10k-deploy-key)"
    log_bootstrap_step "r10k_private_key_validation" "failure"
    return 1
  fi

  if [ ! -r "${configured_key_path}" ]; then
    log_message ERROR "r10k private key file is not readable at ${configured_key_path}"
    log_bootstrap_step "r10k_private_key_validation" "failure"
    return 1
  fi

  if [ -n "$(find "${configured_key_path}" -maxdepth 0 -perm /077 -print -quit 2>/dev/null)" ]; then
    log_message ERROR "r10k private key permissions are too open at ${configured_key_path}"
    log_message ERROR "Set permissions to 600 (or stricter) before startup"
    log_bootstrap_step "r10k_private_key_validation" "failure"
    return 1
  fi

  log_message INFO "r10k private key validation: OK (${configured_key_path})"
  log_bootstrap_step "r10k_private_key_validation" "success"
  return 0
}

prepare_r10k_ssh_materials() {
  log_bootstrap_step "r10k_ssh_materials_prepare" "starting"

  local key_line
  local remote_line
  local known_hosts_line
  local configured_key_path
  local r10k_remote
  local known_hosts_path
  local ssh_host

  key_line=$(grep -E '^[[:space:]]*("puppet_enterprise::profile::master::r10k_private_key"|r10k_private_key)[[:space:]]*=' "${PE_CONF_FILE}" | head -n 1 || true)
  remote_line=$(grep -E '^[[:space:]]*("puppet_enterprise::profile::master::r10k_remote"|r10k_remote)[[:space:]]*=' "${PE_CONF_FILE}" | head -n 1 || true)
  known_hosts_line=$(grep -E '^[[:space:]]*("puppet_enterprise::profile::master::r10k_known_hosts"|r10k_known_hosts)[[:space:]]*=' "${PE_CONF_FILE}" | head -n 1 || true)

  if [ -z "${key_line}" ]; then
    log_message INFO "r10k_private_key not configured in pe.conf; skipping SSH material preparation"
    log_bootstrap_step "r10k_ssh_materials_prepare" "success"
    return 0
  fi

  configured_key_path=$(extract_first_hocon_string_value "${key_line}")
  if [ -z "${configured_key_path}" ]; then
    log_message ERROR "r10k_private_key is configured but empty in pe.conf"
    log_bootstrap_step "r10k_ssh_materials_prepare" "failure"
    return 1
  fi

  if [ -f "${R10K_PRIVATE_KEY_STAGING}" ]; then
    mkdir -p "$(dirname "${configured_key_path}")"
    install -m 0400 -o pe-puppet -g pe-puppet "${R10K_PRIVATE_KEY_STAGING}" "${configured_key_path}" 2>/dev/null ||
      install -m 0400 "${R10K_PRIVATE_KEY_STAGING}" "${configured_key_path}"
    log_message INFO "Prepared r10k private key for pe-puppet at ${configured_key_path}"
  else
    log_message WARN "R10K key staging file not found at ${R10K_PRIVATE_KEY_STAGING}; using configured path as-is"
  fi

  # Build known_hosts automatically for SSH remotes when needed.
  # Write to pe-puppet's SSH known_hosts so r10k can use it without pe.conf configuration.
  if [ -z "${remote_line}" ]; then
    log_bootstrap_step "r10k_ssh_materials_prepare" "success"
    return 0
  fi

  r10k_remote=$(extract_first_hocon_string_value "${remote_line}")

  # Use pe-puppet's SSH known_hosts directly (no r10k_known_hosts in pe.conf needed)
  local pe_puppet_ssh_dir="/etc/puppetlabs/puppet/ssh"
  local known_hosts_path="${pe_puppet_ssh_dir}/known_hosts"

  ssh_host=""
  if printf '%s' "${r10k_remote}" | grep -qE '^git@[^:]+:'; then
    ssh_host=$(printf '%s' "${r10k_remote}" | sed -E 's#^git@([^:]+):.*#\1#')
  elif printf '%s' "${r10k_remote}" | grep -qE '^ssh://'; then
    ssh_host=$(printf '%s' "${r10k_remote}" | sed -E 's#^ssh://([^@]+@)?([^/:]+).*$#\2#')
  fi

  if [ -n "${ssh_host}" ]; then
    mkdir -p "${pe_puppet_ssh_dir}"
    if ! grep -qF "${ssh_host}" "${known_hosts_path}" 2>/dev/null; then
      if ssh-keyscan -H "${ssh_host}" >>"${known_hosts_path}" 2>/dev/null; then
        chmod 0644 "${known_hosts_path}"
        chown pe-puppet:pe-puppet "${known_hosts_path}" 2>/dev/null || true
        log_message INFO "Added ${ssh_host} to r10k known_hosts at ${known_hosts_path}"
      else
        log_message WARN "Unable to run ssh-keyscan for ${ssh_host}; SSH host key verification may fail"
      fi
    else
      log_message INFO "SSH known_hosts already contains entry for ${ssh_host}"
    fi
  fi

  log_bootstrap_step "r10k_ssh_materials_prepare" "success"
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

# Run post-install Puppet agent convergence required by PE.
run_post_install_agent_convergence() {
  log_bootstrap_step "post_install_agent_convergence" "starting"

  local run_number
  local exit_code
  for run_number in 1 2; do
    log_message INFO "Running post-install puppet agent convergence pass ${run_number}/2"
    set +e
    /opt/puppetlabs/bin/puppet agent -t
    exit_code=$?
    set -e

    case "${exit_code}" in
    0 | 2)
      log_message INFO "Post-install puppet agent run ${run_number}/2 completed with exit code ${exit_code}"
      ;;
    *)
      log_message ERROR "Post-install puppet agent run ${run_number}/2 failed with exit code ${exit_code}"
      log_bootstrap_step "post_install_agent_convergence" "failure"
      return 1
      ;;
    esac
  done

  log_bootstrap_step "post_install_agent_convergence" "success"
  return 0
}

# Trigger an initial Code Manager deployment once services are ready.
# Implementation is delegated to /puppet/code-manager-initial-deploy.sh.
trigger_initial_code_deploy() {
  /puppet/code-manager-initial-deploy.sh
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
      log_bootstrap_step "cleanup_installer_artifacts" "success" # Non-fatal
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

  # Step 2a: Prepare r10k SSH materials (deploy key ownership and known_hosts).
  if ! prepare_r10k_ssh_materials; then
    handle_bootstrap_failure "r10k_ssh_materials_prepare" "Could not prepare r10k SSH credentials"
    return 1
  fi

  # Step 2b: Validate r10k private key when configured.
  if ! validate_r10k_private_key; then
    handle_bootstrap_failure "r10k_private_key_validation" "r10k private key missing, unreadable, or has unsafe permissions"
    return 1
  fi

  # Step 3: Mark as installing (T024)
  if ! write_installing_marker; then
    handle_bootstrap_failure "write_installing_marker" "Could not write lifecycle marker"
    return 1
  fi

  # Step 3b: Extract installer payload from staged archive.
  if ! extract_installer_archive; then
    handle_bootstrap_failure "extract_installer_archive" "Could not extract installer payload"
    return 1
  fi

  # Step 4: Execute installer (T025)
  if ! execute_installer; then
    handle_bootstrap_failure "execute_installer" "Installer execution failed"
    return 1
  fi

  # Step 5: Run the required post-install puppet agent convergence.
  if ! run_post_install_agent_convergence; then
    handle_bootstrap_failure "post_install_agent_convergence" "Required puppet agent convergence failed"
    return 1
  fi

  # Step 5a: Trigger initial Code Manager deploy (non-fatal if skipped/fails).
  if ! trigger_initial_code_deploy; then
    log_message WARN "Initial Code Manager deploy failed; continuing bootstrap"
  fi

  # Step 6: Persist successful completion (T026)
  if ! persist_install_completion; then
    handle_bootstrap_failure "persist_install_completion" "Could not write install-complete marker"
    return 1
  fi

  # Step 7: Clean up installer (T026a)
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
