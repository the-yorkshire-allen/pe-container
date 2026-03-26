#!/bin/bash
# Initial Code Manager deployment orchestration.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${script_dir}/scripts/lib/logging.sh" ]; then
  # Repo layout when invoked from the source tree.
  source "${script_dir}/scripts/lib/logging.sh"
elif [ -f "${script_dir}/lib/logging.sh" ]; then
  # Fallback for colocated layouts.
  source "${script_dir}/lib/logging.sh"
elif [ -f "/puppet/scripts/lib/logging.sh" ]; then
  # Runtime image layout.
  source "/puppet/scripts/lib/logging.sh"
else
  echo "ERROR: Unable to locate logging.sh for code-manager-initial-deploy.sh" >&2
  exit 1
fi

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

persist_code_manager_token() {
  local token="$1"
  local method="$2"
  local login="$3"
  local token_file="${CODE_MANAGER_TOKEN_FILE:-${PE_STATE_DIR:-/puppet/state}/code-manager/deploy-token}"

  mkdir -p "$(dirname "${token_file}")"
  umask 077
  printf 'token=%s\n' "${token}" >"${token_file}"
  printf 'method=%s\n' "${method}" >>"${token_file}"
  printf 'login=%s\n' "${login}" >>"${token_file}"
  printf 'issued_at=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >>"${token_file}"
  chmod 0600 "${token_file}"

  log_message INFO "Persisted Code Manager deploy token metadata to ${token_file}"
}

main() {
  log_bootstrap_step "trigger_initial_code_deploy" "starting"

  local method="${CODE_MANAGER_DEPLOY_METHOD:-bootstrap-deploys}"
  local deploy_token="${CODE_MANAGER_DEPLOY_TOKEN:-}"
  local deploy_password="${CODE_MANAGER_DEPLOY_PASSWORD:-}"
  local webhook_token="${CODE_MANAGER_WEBHOOK_TOKEN:-}"
  local user_login="${CODE_MANAGER_DEPLOY_USER:-code_deploy}"
  local bootstrap_login="${CODE_MANAGER_BOOTSTRAP_LOGIN:-admin}"
  local bootstrap_password="${CODE_MANAGER_BOOTSTRAP_PASSWORD:-}"
  local pe_conf_file="${PE_CONF_FILE:-/etc/puppetlabs/pe/pe.conf}"
  local server
  local cacert
  local webhook_line
  local bootstrap_password_line
  local rbac_api_uri
  local token_json
  local generated_token
  local bootstrap_token
  local roles_json
  local role_id
  local users_json
  local user_id
  local user_password
  local response_body
  local http_code
  local probe_uri
  local deploy_uri
  local status_code
  local attempt

  if [ "${CODE_MANAGER_INITIAL_DEPLOY:-true}" = "false" ]; then
    log_message INFO "Initial Code Manager deploy disabled (CODE_MANAGER_INITIAL_DEPLOY=false)"
    log_bootstrap_step "trigger_initial_code_deploy" "skipped"
    return 0
  fi

  server=$(/opt/puppetlabs/bin/puppet config print server 2>/dev/null || echo "localhost")
  cacert=$(/opt/puppetlabs/bin/puppet config print localcacert 2>/dev/null || true)

  if [ -z "${webhook_token}" ]; then
    webhook_line=$(grep -E '^[[:space:]]*("puppet_enterprise::profile::master::code_manager_webhook_token"|"code_manager_webhook_token"|"webhook_auth_token")[[:space:]]*=' "${pe_conf_file}" | head -n 1 || true)
    if [ -n "${webhook_line}" ]; then
      webhook_token=$(extract_first_hocon_string_value "${webhook_line}")
    fi
  fi

  if [ "${method}" = "auto" ]; then
    if [ -n "${deploy_token}" ]; then
      method="deploys"
    elif [ -n "${webhook_token}" ]; then
      method="webhook"
    else
      method="bootstrap-deploys"
    fi
  fi

  if [ "${method}" = "bootstrap-deploys" ]; then
    rbac_api_uri="https://${server}:4433/rbac-api/v1"

    if [ -z "${cacert}" ] || [ ! -f "${cacert}" ]; then
      log_message WARN "Missing PE CA bundle; cannot run bootstrap-deploys flow"
      log_bootstrap_step "trigger_initial_code_deploy" "skipped"
      return 0
    fi

    if [ -z "${bootstrap_password}" ]; then
      bootstrap_password_line=$(grep -E '^[[:space:]]*("console_admin_password"|"puppet_enterprise::console_password"|console_password)[[:space:]]*=' "${pe_conf_file}" | head -n 1 || true)
      if [ -n "${bootstrap_password_line}" ]; then
        bootstrap_password=$(extract_first_hocon_string_value "${bootstrap_password_line}")
      fi
    fi

    if [ -z "${bootstrap_login}" ] || [ -z "${bootstrap_password}" ]; then
      log_message WARN "Missing bootstrap credentials (CODE_MANAGER_BOOTSTRAP_LOGIN/CODE_MANAGER_BOOTSTRAP_PASSWORD or console_admin_password in pe.conf); skipping bootstrap-deploys flow"
      log_bootstrap_step "trigger_initial_code_deploy" "skipped"
      return 0
    fi

    if [ -z "${user_login}" ]; then
      log_message WARN "CODE_MANAGER_DEPLOY_USER is empty; skipping bootstrap-deploys flow"
      log_bootstrap_step "trigger_initial_code_deploy" "skipped"
      return 0
    fi

    for attempt in $(seq 1 120); do
      status_code=$(curl -sS --cacert "${cacert}" -o /dev/null -w "%{http_code}" "${rbac_api_uri}/users" || true)
      case "${status_code}" in
      200 | 401 | 403)
        log_message INFO "RBAC API is reachable (HTTP ${status_code})"
        break
        ;;
      *)
        sleep 2
        ;;
      esac
    done

    if [ "${attempt}" -ge 120 ]; then
      log_message WARN "RBAC API did not become reachable in time; skipping bootstrap-deploys flow"
      log_bootstrap_step "trigger_initial_code_deploy" "skipped"
      return 0
    fi

    token_json=$(curl -sS --cacert "${cacert}" \
      -H "Content-Type: application/json" \
      --request POST "${rbac_api_uri}/auth/token" \
      --data "{\"login\":\"${bootstrap_login}\",\"password\":\"${bootstrap_password}\",\"lifetime\":\"5m\",\"label\":\"bootstrap-rbac-admin-token\"}" || true)
    bootstrap_token=$(printf '%s' "${token_json}" | /opt/puppetlabs/puppet/bin/ruby -rjson -e 'begin; data=JSON.parse(STDIN.read); puts(data["token"]); rescue; end')

    if [ -z "${bootstrap_token}" ]; then
      log_message WARN "Failed to generate bootstrap RBAC token for ${bootstrap_login}; skipping bootstrap-deploys flow"
      log_bootstrap_step "trigger_initial_code_deploy" "skipped"
      return 0
    fi

    roles_json=$(curl -sS --cacert "${cacert}" -H "X-Authentication: ${bootstrap_token}" "${rbac_api_uri}/roles" || true)
    role_id=$(printf '%s' "${roles_json}" | /opt/puppetlabs/puppet/bin/ruby -rjson -e 'begin; data=JSON.parse(STDIN.read); role=data.find{|r| r["display_name"]=="Code Deployers"}; puts(role && role["id"]); rescue; end')

    if [ -z "${role_id}" ]; then
      log_message WARN "Could not locate Code Deployers role; skipping bootstrap-deploys flow"
      log_bootstrap_step "trigger_initial_code_deploy" "skipped"
      return 0
    fi

    users_json=$(curl -sS --cacert "${cacert}" -H "X-Authentication: ${bootstrap_token}" "${rbac_api_uri}/users" || true)
    user_id=$(printf '%s' "${users_json}" | LOGIN="${user_login}" /opt/puppetlabs/puppet/bin/ruby -rjson -e 'begin; login=ENV["LOGIN"]; data=JSON.parse(STDIN.read); user=data.find{|u| u["login"]==login}; puts(user && user["id"]); rescue; end')

    user_password="${deploy_password}"
    if [ -z "${user_password}" ]; then
      user_password=$(openssl rand -base64 24 | tr -d '\n')
    fi

    if [ -z "${user_id}" ]; then
      response_body="/tmp/code-manager-bootstrap-user-create.json"
      http_code=$(curl -sS --cacert "${cacert}" -H "X-Authentication: ${bootstrap_token}" \
        -o "${response_body}" -w "%{http_code}" \
        -H "Content-Type: application/json" \
        --request POST "${rbac_api_uri}/users" \
        --data "{\"login\":\"${user_login}\",\"display_name\":\"Code Manager Deploy User\",\"email\":\"${user_login}@pe.local\",\"password\":\"${user_password}\",\"role_ids\":[${role_id}]}" || true)

      if [ "${http_code}" != "200" ] && [ "${http_code}" != "201" ] && [ "${http_code}" != "303" ] && [ "${http_code}" != "409" ]; then
        log_message WARN "Failed creating deploy user ${user_login} (HTTP ${http_code}); skipping bootstrap-deploys flow"
        log_bootstrap_step "trigger_initial_code_deploy" "skipped"
        return 0
      fi

      users_json=$(curl -sS --cacert "${cacert}" -H "X-Authentication: ${bootstrap_token}" "${rbac_api_uri}/users" || true)
      user_id=$(printf '%s' "${users_json}" | LOGIN="${user_login}" /opt/puppetlabs/puppet/bin/ruby -rjson -e 'begin; login=ENV["LOGIN"]; data=JSON.parse(STDIN.read); user=data.find{|u| u["login"]==login}; puts(user && user["id"]); rescue; end')

      if [ -z "${user_id}" ]; then
        log_message WARN "Deploy user ${user_login} not found after create; skipping bootstrap-deploys flow"
        log_bootstrap_step "trigger_initial_code_deploy" "skipped"
        return 0
      fi

      log_message INFO "Created deploy user ${user_login}"
    else
      http_code=$(curl -sS --cacert "${cacert}" -H "X-Authentication: ${bootstrap_token}" \
        -o /dev/null -w "%{http_code}" \
        -H "Content-Type: application/json" \
        --request POST "${rbac_api_uri}/users/${user_id}/roles" \
        --data "{\"role_id\":${role_id}}" || true)
      case "${http_code}" in
      200 | 201 | 409) ;;
      *) log_message WARN "Could not ensure Code Deployers role on ${user_login} (HTTP ${http_code})" ;;
      esac

      http_code=$(curl -sS --cacert "${cacert}" -H "X-Authentication: ${bootstrap_token}" \
        -o /dev/null -w "%{http_code}" \
        -H "Content-Type: application/json" \
        --request PUT "${rbac_api_uri}/users/${user_id}/password" \
        --data "{\"password\":\"${user_password}\"}" || true)
      if [ "${http_code}" != "200" ] && [ "${http_code}" != "204" ]; then
        log_message WARN "Failed to rotate password for ${user_login} (HTTP ${http_code}); skipping bootstrap-deploys flow"
        log_bootstrap_step "trigger_initial_code_deploy" "skipped"
        return 0
      fi
    fi

    token_json=$(curl -sS --cacert "${cacert}" \
      -H "Content-Type: application/json" \
      --request POST "${rbac_api_uri}/auth/token" \
      --data "{\"login\":\"${user_login}\",\"password\":\"${user_password}\",\"lifetime\":\"${CODE_MANAGER_TOKEN_LIFETIME:-17520h}\",\"label\":\"${CODE_MANAGER_TOKEN_LABEL:-bootstrap-deploys-token}\"}" || true)
    generated_token=$(printf '%s' "${token_json}" | /opt/puppetlabs/puppet/bin/ruby -rjson -e 'begin; data=JSON.parse(STDIN.read); puts(data["token"]); rescue; end')

    if [ -z "${generated_token}" ]; then
      log_message WARN "Failed to generate deploy token for ${user_login}; skipping bootstrap-deploys flow"
      log_bootstrap_step "trigger_initial_code_deploy" "skipped"
      return 0
    fi

    deploy_token="${generated_token}"
    method="deploys"
    persist_code_manager_token "${deploy_token}" "${method}" "${user_login}"
    log_message INFO "Generated long-lived deploy token for ${user_login}"
  fi

  # Compatibility mode retained for existing webhook integrations.
  if [ "${method}" = "bootstrap-webhook" ]; then
    log_message WARN "bootstrap-webhook mode is retained for compatibility; consider bootstrap-deploys for least privilege"
  fi

  if [ "${method}" = "auto" ]; then
    if [ -n "${deploy_token}" ]; then
      method="deploys"
    elif [ -n "${webhook_token}" ]; then
      method="webhook"
    else
      log_message INFO "No Code Manager token configured; skipping initial code deploy"
      log_bootstrap_step "trigger_initial_code_deploy" "skipped"
      return 0
    fi
  fi

  if [ "${method}" = "deploys" ] && [ -z "${deploy_token}" ]; then
    log_message WARN "CODE_MANAGER_DEPLOY_METHOD=deploys but CODE_MANAGER_DEPLOY_TOKEN is empty; skipping initial code deploy"
    log_bootstrap_step "trigger_initial_code_deploy" "skipped"
    return 0
  fi

  if [ "${method}" = "webhook" ] && [ -z "${webhook_token}" ]; then
    log_message WARN "CODE_MANAGER_DEPLOY_METHOD=webhook but webhook token is empty; skipping initial code deploy"
    log_bootstrap_step "trigger_initial_code_deploy" "skipped"
    return 0
  fi

  probe_uri="https://${server}:8170/code-manager/v1/deploys/status"
  for attempt in $(seq 1 120); do
    status_code=$(curl -s -k -o /dev/null -w "%{http_code}" "${probe_uri}" || true)
    case "${status_code}" in
    200 | 401 | 403)
      log_message INFO "Code Manager API is reachable (HTTP ${status_code})"
      break
      ;;
    *) sleep 2 ;;
    esac
  done

  if [ "${attempt}" -ge 120 ]; then
    log_message WARN "Code Manager API did not become reachable in time; skipping initial code deploy"
    log_bootstrap_step "trigger_initial_code_deploy" "skipped"
    return 0
  fi

  response_body="/tmp/code-manager-initial-deploy-response.json"
  if [ "${method}" = "webhook" ]; then
    deploy_uri="https://${server}:8170/code-manager/v1/webhook?token=${webhook_token}"
    if [ -n "${cacert}" ] && [ -f "${cacert}" ]; then
      http_code=$(curl -sS --cacert "${cacert}" -o "${response_body}" -w "%{http_code}" \
        -H "Content-Type: application/json" \
        --request POST "${deploy_uri}" \
        --data "${CODE_MANAGER_WEBHOOK_PAYLOAD:-{}}" || true)
    else
      http_code=$(curl -sS -k -o "${response_body}" -w "%{http_code}" \
        -H "Content-Type: application/json" \
        --request POST "${deploy_uri}" \
        --data "${CODE_MANAGER_WEBHOOK_PAYLOAD:-{}}" || true)
    fi
  else
    deploy_uri="https://${server}:8170/code-manager/v1/deploys"
    if [ -n "${cacert}" ] && [ -f "${cacert}" ]; then
      http_code=$(curl -sS --cacert "${cacert}" -o "${response_body}" -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -H "X-Authentication: ${deploy_token}" \
        --request POST "${deploy_uri}" \
        --data "${CODE_MANAGER_DEPLOY_PAYLOAD:-{\"deploy-all\": true}}" || true)
    else
      http_code=$(curl -sS -k -o "${response_body}" -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -H "X-Authentication: ${deploy_token}" \
        --request POST "${deploy_uri}" \
        --data "${CODE_MANAGER_DEPLOY_PAYLOAD:-{\"deploy-all\": true}}" || true)
    fi
  fi

  case "${http_code}" in
  200 | 201 | 202)
    log_message INFO "Initial Code Manager deploy accepted (method=${method}, HTTP ${http_code})"
    ;;
  *)
    log_message WARN "Initial Code Manager deploy request returned HTTP ${http_code} (method=${method})"
    if [ -s "${response_body}" ]; then
      log_message WARN "Code Manager response: $(head -c 500 "${response_body}")"
    fi
    ;;
  esac

  log_bootstrap_step "trigger_initial_code_deploy" "success"
}

main "$@"
