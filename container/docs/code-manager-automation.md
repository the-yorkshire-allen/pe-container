# Code Manager Initial Deploy Automation

## Overview

Bootstrap now supports an optional **initial code release trigger** after installer completion and post-install agent convergence.

The workflow now runs from a dedicated script at `/puppet/code-manager-initial-deploy.sh`, invoked by bootstrap.

Default behavior uses a bootstrap-native deploys flow that does not require passing a pre-existing token into the container:

1. Mint a short-lived bootstrap RBAC token (from bootstrap credentials)
2. Create/reuse a dedicated deploy user
3. Ensure the deploy user is in `Code Deployers`
4. Set or rotate deploy user password
5. Mint a long-lived deploy token for that restricted user
6. Call the Code Manager deploys API on `8170` with `X-Authentication`

If any of these steps cannot be completed, bootstrap logs a warning and continues (non-fatal).

## Execution Point

Initial deploy runs in bootstrap **after**:

1. installer execution
2. post-install puppet agent convergence

This placement avoids early service-readiness timing failures.

## Environment Variables

```bash
# Enable/disable initial code deploy trigger
export CODE_MANAGER_INITIAL_DEPLOY="true"   # default: true

# bootstrap-deploys|bootstrap-webhook|auto|deploys|webhook (default: bootstrap-deploys)
export CODE_MANAGER_DEPLOY_METHOD="bootstrap-deploys"

# Used by bootstrap-deploys
export CODE_MANAGER_DEPLOY_USER="code_deploy"
export CODE_MANAGER_DEPLOY_PASSWORD=""   # optional; if unset, bootstrap generates one
export CODE_MANAGER_BOOTSTRAP_LOGIN="admin"
export CODE_MANAGER_BOOTSTRAP_PASSWORD="" # optional; if unset, bootstrap reads console_admin_password from pe.conf
export CODE_MANAGER_TOKEN_LIFETIME="17520h"   # 2 years
export CODE_MANAGER_TOKEN_LABEL="bootstrap-deploys-token"
export CODE_MANAGER_TOKEN_FILE="/puppet/state/code-manager/deploy-token"
export CODE_MANAGER_DEPLOY_PAYLOAD='{"deploy-all": true}'

# Optional manual token paths (non-default):
# Used when method is deploys
export CODE_MANAGER_DEPLOY_TOKEN="<rbac_token_for_code_deployer>"
export CODE_MANAGER_DEPLOY_PAYLOAD='{"deploy-all": true}'

# Used when method is webhook
export CODE_MANAGER_WEBHOOK_TOKEN="<webhook_token>"
```

`auto` resolution order:

1. If `CODE_MANAGER_DEPLOY_TOKEN` is set, use `deploys`
2. Else if `CODE_MANAGER_WEBHOOK_TOKEN` is set (or token found in `pe.conf`), use `webhook`
3. Else use `bootstrap-deploys`

## pe.conf Token Discovery for Webhook

When `CODE_MANAGER_WEBHOOK_TOKEN` env var is empty, bootstrap attempts to read a token from `pe.conf` keys matching:

- `puppet_enterprise::profile::master::code_manager_webhook_token`
- `code_manager_webhook_token`
- `webhook_auth_token`

## Bootstrap-Deploys Example (Default)

```bash
export CODE_MANAGER_DEPLOY_METHOD="bootstrap-deploys"
export CODE_MANAGER_DEPLOY_USER="code_deploy"
export CODE_MANAGER_DEPLOY_PASSWORD=""   # optional seed password for managed deploy user
export CODE_MANAGER_BOOTSTRAP_LOGIN="admin"
export CODE_MANAGER_BOOTSTRAP_PASSWORD="" # optional override
export CODE_MANAGER_TOKEN_LIFETIME="17520h"
export CODE_MANAGER_TOKEN_LABEL="bootstrap-deploys-token"
export CODE_MANAGER_TOKEN_FILE="/puppet/state/code-manager/deploy-token"
export CODE_MANAGER_DEPLOY_PAYLOAD='{"deploy-all": true}'
```

Bootstrap performs:

```bash
# 1) authenticate bootstrap principal via POST /rbac-api/v1/auth/token (short-lived)
# 2) create/reuse code_deploy user and ensure Code Deployers role
# 3) set/rotate deploy user password
# 4) mint long-lived token for code_deploy
# 5) POST /code-manager/v1/deploys with X-Authentication: <generated-token>
# 6) persist deploy token metadata to /puppet/state/code-manager/deploy-token (0600)
```

## Fetching The Generated Token

The generated deploy token metadata is written to `CODE_MANAGER_TOKEN_FILE` (default: `/puppet/state/code-manager/deploy-token`) so operators can retrieve it after first boot:

```bash
docker exec pe-primary cat /puppet/state/code-manager/deploy-token
```

## Manual Deploys API Example (Optional)

```bash
export CODE_MANAGER_DEPLOY_METHOD="deploys"
export CODE_MANAGER_DEPLOY_TOKEN="<rbac_token>"
export CODE_MANAGER_DEPLOY_PAYLOAD='{"deploy-all": true}'
```

Bootstrap performs:

```bash
curl --header "Content-Type: application/json" \
     --header "X-Authentication: <TOKEN>" \
     --request POST \
     "https://<server>:8170/code-manager/v1/deploys" \
     --data '{"deploy-all": true}'
```

## Log Verification

```bash
docker exec pe-primary journalctl -u pe-container-bootstrap.service --no-pager | \
  grep -E "trigger_initial_code_deploy|Code Manager API|Initial Code Manager deploy"
```

Success indicators:

- `Code Manager API is reachable`
- `Initial Code Manager deploy accepted`

Skip indicators:

- `Missing PE CA bundle ... cannot run bootstrap-deploys flow`
- `Missing bootstrap credentials ... cannot run bootstrap-deploys flow`
- `RBAC API did not become reachable in time`

## Troubleshooting

1. HTTP `401` from `deploys` endpoint:
Use a token for a user in Code Deployers role.

2. HTTP `403` from `deploys` endpoint:
Token is valid but not authorized for deployment actions.

3. HTTP `401` from bootstrap token minting:
Verify `CODE_MANAGER_BOOTSTRAP_LOGIN` / `CODE_MANAGER_BOOTSTRAP_PASSWORD` or `console_admin_password` in `pe.conf`.

4. HTTP `403` while creating deploy user:
Bootstrap principal is authenticated but not authorized for RBAC user management.

5. HTTP `404/405` from webhook endpoint:
Verify endpoint/token format and `CODE_MANAGER_WEBHOOK_PAYLOAD` expectations for your integration.

6. API readiness timeout:
Inspect bootstrap and PE service logs:

```bash
docker exec pe-primary journalctl -u pe-container-bootstrap.service --no-pager
docker exec pe-primary tail -n 200 /var/log/puppetlabs/puppetserver/puppetserver.log
```
