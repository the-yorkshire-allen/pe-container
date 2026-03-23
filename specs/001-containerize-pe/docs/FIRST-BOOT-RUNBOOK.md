# First-Boot Operator Runbook

## Overview

This runbook guides operators through first-time setup of a Puppet Enterprise container. The bootstrap process validates configuration, executes the installer, and persists state for subsequent restarts.

## Prerequisites

- Docker or Docker Compose installed
- Puppet Enterprise installer tarball (`.tar.gz`) available locally
- PE configuration file (`pe.conf`) with `console_password` defined
- PE license file (if applicable for your PE deployment)
- Minimum 4GB memory allocated to container
- Volume mounts configured for persistence

## First-Boot Workflow

### Step 1: Prepare Configuration

Before starting the container, ensure these files are ready:

#### pe.conf
Create or provide your `pe.conf` file with **required** entries:
- `console_password` - The password for the PE Console admin user (REQUIRED)
- Other PE settings (agents to configure, SSL settings, etc.)

Example minimal `pe.conf`:
```ini
console_password=your_secure_console_password_here
# Add other PE configuration as needed
certificate_authority_host=%{::trusted.certname}
```

**IMPORTANT**: The `console_password` field is mandatory for first-time installation. The bootstrap process will fail and display an error if it is missing or empty.

#### Installer Tarball
Obtain the PE installer matching your deployment:
```bash
# Example: Using locally cached installer
ls -lh /path/to/puppet-enterprise-VERSION-OS.tar.gz
```

The installer **must**:
- Be a gzip-compressed tar archive (`.tar.gz` format)
- Contain PE installer scripts and artifacts
- Match the version declared in your deployment (e.g., `2024.7.0`)

### Step 2: Map Volumes and Set Build Arguments

Using Docker CLI:
```bash
PE_VERSION="2024.7.0"
PE_INSTALLER_PATH="/local/path/to/puppet-enterprise-${PE_VERSION}-ubuntu-22.04.tar.gz"
PE_CONFIG_DIR="/local/config/directory"

# Ensure paths are absolute
[ -f "$PE_INSTALLER_PATH" ] || { echo "Installer not found"; exit 1; }
[ -f "$PE_CONFIG_DIR/pe.conf" ] || { echo "pe.conf not found"; exit 1; }

docker build \
  --build-arg PE_VERSION="$PE_VERSION" \
  --build-arg PE_INSTALLER_TAR_PATH="$PE_INSTALLER_PATH" \
  -t pe-primary:${PE_VERSION} \
  container/

docker run -d \
  --name pe-primary \
  -p 8140:8140 \
  -p 8142:8142 \
  -p 8143:8143 \
  -v "${PE_CONFIG_DIR}/pe.conf:/etc/puppetlabs/pe/pe.conf:ro" \
  -v pe-config:/etc/puppetlabs \
  -v pe-data:/opt/puppetlabs \
  -v pe-logs:/var/log/puppetlabs \
  -v pe-state:/puppet/state \
  pe-primary:${PE_VERSION}
```

Using Docker Compose:
```bash
# Edit compose/docker-compose.pe-primary.yml with your paths and settings
docker-compose -f compose/docker-compose.pe-primary.yml up -d
```

### Step 3: Monitor First-Boot Bootstrap

After container starts, monitor logs for bootstrap progress:

```bash
# Follow bootstrap output in real-time
docker logs -f pe-primary

# Expected output sequence:
# 1. [Bootstrap] Starting: preflight_validation
# 2. [Bootstrap] Success: preflight_validation
# 3. [Bootstrap] Starting: console_password_validation
# 4. [Bootstrap] Success: console_password_validation
# 5. [Bootstrap] Starting: set_installing_marker
# 6. [Bootstrap] Success: set_installing_marker
# 7. [Bootstrap] Starting: execute_installer
#    (PE installer runs - typically 10-30 minutes depending on PE version)
# 8. [Bootstrap] Success: execute_installer
# 9. [Bootstrap] Starting: persist_install_completion
# 10. [Bootstrap] Success: persist_install_completion
# 11. [Bootstrap] Starting: cleanup_installer_artifacts
# 12. [Bootstrap] Success: cleanup_installer_artifacts
# 13. === Bootstrap Complete ===
```

### Step 4: Validate Installation Success

Once bootstrap completes, verify the container is ready:

```bash
# Check container status
docker ps -a | grep pe-primary

# Verify running state (should show "healthy" after initialization)
docker ps --format 'table {{.Names}}\t{{.Status}}'

# Test health endpoint
docker exec pe-primary /puppet/healthcheck.sh
echo "Exit code: $?"  # Should be 0 (healthy)

# Check PE services status (after bootstrap)
docker exec pe-primary /puppet/status-probe.sh
# Output should show lifecycle state as "installed"
```

### Step 5: Access Puppet Enterprise Console

Once the container fully initializes:

1. Open browser: `https://<container-host>:8143`
2. Log in with username `admin@puppet.com`  
3. Use the console password from `pe.conf`

## Troubleshooting First-Boot

### Bootstrap Fails: "pe.conf not found"

**Issue**: Container exits with error about missing pe.conf

**Solutions**:
1. Verify pe.conf volume mount is correct:
   ```bash
   docker inspect pe-primary --format='{{json .Mounts}}'
   ```
2. Ensure pe.conf path is absolute and exists:
   ```bash
   [ -f "/path/to/pe.conf" ] && echo "Found" || echo "Missing"
   ```
3. Check volume permissions (should be readable by container uid)

### Bootstrap Fails: "console_password not found or empty"

**Issue**: Container exits saying console_password missing from pe.conf

**Solutions**:
1. Verify pe.conf contains console_password entry:
   ```bash
   grep "console_password" /path/to/pe.conf
   ```
2. Ensure password value is non-empty:
   ```bash
   grep "console_password" pe.conf | cut -d'=' -f2 | wc -c  # Should be > 1
   ```
3. Edit pe.conf to add line if missing:
   ```ini
   console_password=YourSecurePassword123!
   ```
4. Restart bootstrap:
   ```bash
   docker exec pe-primary /puppet/reset-runtime-state.sh
   docker restart pe-primary
   ```

### Bootstrap Fails: "Installer not found or invalid tar"

**Issue**: Container reports installer tar is missing or corrupted

**Solutions**:
1. Verify installer build argument was passed correctly:
   ```bash
   docker inspect pe-primary --format='{{json .Config.Env}}' | grep PE_
   ```
2. Test installer tar validity:
   ```bash
   tar -tzf /path/to/installer.tar.gz > /dev/null && echo "Valid" || echo "Invalid"
   ```
3. Rebuild image with correct path:
   ```bash
   docker build --build-arg PE_INSTALLER_TAR_PATH="/absolute/path/to/installer.tar.gz" ...
   ```

### Bootstrap Interrupted: "Lifecycle state: installing"

**Issue**: Log shows state is "installing" (partial installation)

**Solutions**:
1. This indicates the prior bootstrap attempt was interrupted (e.g., container aborted, network loss)
2. **Do NOT restart the container** - this will fail with same error
3. Manually reset and retry:
   ```bash
   docker exec pe-primary /puppet/reset-runtime-state.sh
   docker restart pe-primary
   ```
4. (Optional) Fix issue that interrupted first attempt (log space, network, etc.)
5. Bootstrap resumes from clean state

### Bootstrap Failed: "Lifecycle state: failed"

**Issue**: Log shows state is "failed"

**Solutions**:
1. Review logs for actual error during install steps:
   ```bash
   docker logs pe-primary | grep -A5 "Bootstrap.*Failed"
   ```
2. Common causes:
   - Insufficient disk space for PE installation
   - Network connectivity issue during installer execution
   - PE version mismatch between image and pe.conf
   - Corrupted installer tarball
3. Once root cause identified:
   ```bash
   docker exec pe-primary /puppet/reset-runtime-state.sh
   docker restart pe-primary
   ```

### Health Check Shows "Unhealthy"

**Issue**: `docker ps` shows container as unhealthy

**Solutions**:
1. Check health endpoint directly:
   ```bash
   docker exec pe-primary /puppet/healthcheck.sh
   ```
2. Review bootstrap logs:
   ```bash
   docker logs pe-primary | tail -20
   ```
3. If bootstrap is incomplete, wait for more time (PE install typically 10-30 min)
4. If bootstrap failed, see above guidance for failed state

## Operational Considerations

### Version Pinning

Each deployed container image is **locked** to a single PE version:
- Version is declared at **build time** via `PE_VERSION` build arg
- All subsequent restarts use the same version
- No automated in-place upgrades occur
- To upgrade PE, build a new image with new version and migrate data

### Persistence and Restarts

The containers maintain state across restarts:
- Lifecycle markers prevent re-running bootstrap on restart
- PE configuration is persisted in `pe-config` volume
- PE database and data stored in `pe-data` volume
- Log files retained in `pe-logs` volume

To restart the container:
```bash
docker restart pe-primary
# Logs will show: "Restoring from persisted state..."
```

### Explicit Reset Required

The design intentionally requires **explicit operator reset** for recovery:
- After bootstrap failure, automatic retry is NOT performed
- Operator must review logs, identify issue, then manually reset
- This prevents cascading failures and provides control visibility

To reset:
```bash
docker exec pe-primary /puppet/reset-runtime-state.sh
docker restart pe-primary
# Container returns to uninitialized state and bootstrap retries
```

### Security Notes

1. **Console Password**: Keep the password secure and not in version control
2. **Volumes**: Ensure volumes are stored on encrypted filesystem if handling sensitive data
3. **Network**: Secure TLS certificates for PE Console access
4. **Installer Tarball**: Keep installer secure until build-time validation completes

## Next Steps

Once first-boot bootstrap completes successfully:

1. **Configure PE Agents**: 
   - Set up agent-server relationships
   - Install agents on target nodes
   - Write Puppet manifests

2. **Enable SSL/TLS**:
   - Configure certificates for PE Console and agents
   - Set up certificate authority

3. **Integrate with External Systems**:
   - Connect to Webhook receivers
   - Configure notification plugins
   - Set up RBAC integrations

4. **Operational Monitoring**:
   - Monitor container health
   - Track container logs
   - Set up alerting on failed restarts

5. **Backup and Recovery**:
   - Back up PE volumes for disaster recovery
   - Document recovery procedures
   - Test restore workflows

## Support and Debugging

For detailed bootstrap debug output, rebuild with verbose logging:

```bash
docker build --build-arg DEBUG=1 -t pe-primary:dev .
```

For additional questions about PE configuration, see:
- [Puppet Enterprise Installation Documentation](https://puppet.com/docs/pe/latest/installing_pe.html)
- [pe.conf Reference](https://puppet.com/docs/pe/latest/installing_pe.html#configuring_pe_with_peconf)
