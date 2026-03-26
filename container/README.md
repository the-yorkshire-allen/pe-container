# Building a Puppet Enterprise Container

This guide explains how to build a versioned PE container image from a local installer artifact.

## Prerequisites

1. **Docker** installed and configured for building images
2. **Puppet Enterprise installer** downloaded and verified on your local filesystem  
   - Recommended: Verify SHA256 and/or GPG signature from Puppet's official source
3. **Absolute file path** to the installer (Linux/Mac use `/path/to/installer.tar.gz`)
4. **PE version identifier** matching the installer (e.g., `2024.1.0`)

## Build Command

Use the provided `Makefile` target to build:

```bash
PE_VERSION="2024.1.0"
PE_INSTALLER_TAR_PATH="/opt/pe-installers/puppet-enterprise-2024.1.0-el-7-x86_64.tar.gz"

make build PE_VERSION="${PE_VERSION}" PE_INSTALLER_TAR_PATH="${PE_INSTALLER_TAR_PATH}"
```

### Parameters

- **PE_VERSION**: Version string identifying the PE release. Must match the installer archive contents.
- **PE_INSTALLER_TAR_PATH**: Full absolute path to the installer tar.gz on your filesystem.

## What Happens During Build

1. **Input Validation** (fail-fast)
   - Verifies PE_VERSION is provided
   - Verifies PE_INSTALLER_TAR_PATH is absolute (starts with `/`)
   - Confirms installer file exists and is readable
   - Validates tar.gz format

2. **Installer Archive Staging**
   - Stages validated installer tar.gz into the image at `/puppet/installer-staging/installer.tar.gz`
   - Records build metadata (version, timestamp, source path)

3. **Bootstrap-Time Extraction**
   - On first container startup, bootstrap extracts the installer archive into `/puppet/installer-staging/`
   - Installer payload is cleaned up after successful installation

4. **Lifecycle Scripts Setup**
   - Copies entrypoint, healthcheck, bootstrap, state management into container
   - Configures tini as PID 1 for signal handling
   - Wires Docker healthcheck endpoint

5. **Image Tagging**
   - Tags image as `pe-container:${PE_VERSION}` and `pe-container:latest`
   - Ready for immediate deployment or registry push

## Build Validation Output

On success, you'll see:
```
[Build] Validating PE_VERSION and PE_INSTALLER_TAR_PATH...
[Build] Starting Docker build with PE_VERSION=2024.1.0...
... (docker build output)
[Build] SUCCESS: Image tagged as pe-container:2024.1.0
```

On failure, docker build exits with clear error messaging:
```
ERROR: PE_INSTALLER_TAR_PATH file not found: /nonexistent/installer.tar.gz
```

## Using the Built Image

After build completes, run with:

```bash
docker-compose -f container/compose/docker-compose.pe-primary.yml up -d
```

Default example configs now live in `config_examples/`:

- `config_examples/pe-primary.conf`
- `config_examples/pe-code-manager-rbac.conf`

For Code Manager with a private deploy key:

1. Create a host secrets directory and copy your key:

```bash
mkdir -p ./secrets
cp /path/to/your/private_key ./secrets/r10k-deploy-key
chmod 600 ./secrets/r10k-deploy-key
```

2. Use the Code Manager config and map the host key file into `/etc/puppetlabs`:

```bash
PE_VERSION=2023.8.8 \
R10K_PRIVATE_KEY_SOURCE="$PWD/secrets/r10k-deploy-key" \
PE_CONF_PATH="$PWD/config_examples/pe-code-manager-rbac.conf" \
docker-compose -f container/compose/docker-compose.pe-primary.yml up -d --no-build
```

**AUTOMATIC INITIAL DEPLOY**: After post-install convergence, bootstrap invokes `/puppet/code-manager-initial-deploy.sh` (built from `container/scripts/code-manager-initial-deploy.sh`). The default `bootstrap-deploys` flow creates or reuses a dedicated deploy user, ensures `Code Deployers` role membership, mints a long-lived token for that user, and calls the Code Manager deploys API on `8170` with `X-Authentication`. A short-lived bootstrap credential is used only for RBAC provisioning and is never sent to Code Manager. The generated deploy token metadata is persisted to `/puppet/state/code-manager/deploy-token` (override with `CODE_MANAGER_TOKEN_FILE`). Manual token modes (`deploys` or `webhook`) are also supported. See [Code Manager Automation](docs/code-manager-automation.md) for details.

Notes:

- The example config uses an SSH control-repo URL (`git@github.com:...`) so the deploy key is used by r10k.
- The mounted key is staged read-only, then bootstrap copies it to `/etc/puppetlabs/keys/r10k-deploy-key` with `pe-puppet` ownership and `0400` mode.
- Bootstrap auto-generates `/etc/puppetlabs/keys/r10k-known_hosts` for the SSH host when it is not already present.

If you want to choose a specific `pe.conf`, set `PE_CONF_PATH` inline:

```bash
PE_CONF_PATH="$PWD/config_examples/pe-primary.conf" docker-compose -f container/compose/docker-compose.pe-primary.yml up -d --no-build
```

For Code Manager against the sample RBAC control repo config:

```bash
PE_CONF_PATH="$PWD/config_examples/pe-code-manager-rbac.conf" docker-compose -f container/compose/docker-compose.pe-primary.yml up -d --no-build
```

Compose defaults `R10K_PRIVATE_KEY_PATH` to `/etc/puppetlabs/keys/r10k-deploy-key` in-container.

Or manually:

```bash
docker run \
  --name pe-primary \
  --volume pe-config:/etc/puppetlabs \
  --volume pe-data:/opt/puppetlabs \
  --volume pe-logs:/var/log/puppetlabs \
  -e PE_STATE_DIR=/puppet/state \
  "pe-container:2024.1.0"
```

First startup will bootstrap PE from the staged installer. Subsequent restarts restore from persisted state.

## Troubleshooting

### "PE_INSTALLER_TAR_PATH must be an absolute path"

Ensure the path starts with `/`. Relative paths (e.g., `./installer.tar.gz` or `~/path`) are not supported.

### "PE_INSTALLER_TAR_PATH file not found"

Verify the installer is located at the path you provided and is readable by your user/Docker:
```bash
ls -l /opt/pe-installers/puppet-enterprise-*.tar.gz
```

### "PE_INSTALLER_TAR_PATH is not a valid tar.gz archive"

Verify the file is a valid archive:
```bash
tar -tzf /opt/pe-installers/puppet-enterprise-*.tar.gz > /dev/null && echo "Valid" || echo "Invalid"
```

### Build takes a very long time

The first build performs image extraction and script setup. Subsequent builds using the same base image will be faster due to Docker layer caching.

## Connected-Node Quick Reference (T042)

Once PE is running, manage connected agent nodes with these commands:

### View Nodes
```bash
# List all known nodes
docker exec pe-primary puppet cert list --all

# Query node inventory
docker exec pe-primary puppet query 'nodes[certname,report_timestamp] {}' --format json
```

### Onboard a New Agent
```bash
# 1. On agent node — install puppet-agent and point at PE primary
puppet config set server pe-primary.example.local
puppet agent -t  # First run requests certificate

# 2. In PE container — approve the certificate signing request
docker exec pe-primary puppet cert sign <agent-certname>

# 3. Verify — agent reruns and appears in console
# PE Console → Infrastructure → Nodes
```

### Trigger Agent Run
```bash
# Via Bolt (from PE container)
docker exec pe-primary bolt task run puppet_agent::run \
  --targets pcp://<agent-certname>

# Or trigger directly on the agent node
puppet agent -t
```

### Remove an Agent Node
```bash
# Revoke certificate
docker exec pe-primary puppet cert disable <agent-certname>

# Clean node data
docker exec pe-primary puppet node deactivate <agent-certname>
```

### Node Continuity After Restart
```bash
# Snapshot pre-restart
docker exec pe-primary puppet cert list --all > /tmp/certs-before.txt

# Restart container
docker restart pe-primary

# Verify nodes unchanged
docker exec pe-primary puppet cert list --all > /tmp/certs-after.txt
diff /tmp/certs-before.txt /tmp/certs-after.txt  # Expect: empty diff
```

### Node Example Compose Profile
```bash
# Start PE primary + two agent containers for testing
docker compose -f container/compose/docker-compose.connected-nodes.yml up -d
```

---

## Next Steps

- See [Quickstart](../specs/001-containerize-pe/quickstart.md) for first-time startup and verification
- See [Build Interface Contract](../specs/001-containerize-pe/contracts/build-interface.md) for detailed input/output specifications
- See [Container Runtime Contract](../specs/001-containerize-pe/contracts/container-runtime.md) for runtime behavior and lifecycle
- See [Connected Nodes Runbook](./docs/connected-nodes.md) for agent onboarding and continuity procedures
- See [Scope Boundaries](./docs/scope-boundaries.md) for what this container does and does not manage

