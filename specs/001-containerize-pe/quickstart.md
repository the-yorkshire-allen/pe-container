# Quickstart: Build and Run Containerized Puppet Enterprise

## Goal

Validate the end-to-end operator workflow: build a versioned image from local installer tar.gz input, then bootstrap, restart, and recover runtime state deterministically.

## Prerequisites

- Docker Engine (or compatible OCI runtime) on Linux
- Local Puppet Enterprise installer tar.gz artifact at an absolute path
- Desired PE version string for image tagging/build metadata
- Valid `pe.conf` including console password for first-time install
- Installer-required licensing material (if required)
- Prepared persistence targets for PE config/certs, application state, and logs

## 1. Build the Image (Required First Step)

Example workflow:

```bash
PE_VERSION=2025.2.0
PE_INSTALLER_TAR_PATH=/path/to/puppet-enterprise-${PE_VERSION}.tar.gz

docker build \
  --build-arg PE_VERSION=${PE_VERSION} \
  --build-arg PE_INSTALLER_TAR_PATH=${PE_INSTALLER_TAR_PATH} \
  -t pe-container:${PE_VERSION} \
  container/
```

Expected result:

- Build succeeds only when required inputs are valid.
- Build fails if `PE_INSTALLER_TAR_PATH` is not absolute.
- Output image is version-identifiable and contains lifecycle scripts.
- Installer content is extracted into a container-local staging location for first install.
- Invalid/missing installer path fails build with actionable errors.

## 2. Prepare Persistence Layer

Example workflow:

```bash
docker volume create pe-etc
docker volume create pe-opt
docker volume create pe-logs
```

Expected result:

- Persistence targets are available before first run.

## 3. First Boot (T030 - Validation Steps)

Example workflow:

```bash
docker run --name pe-primary \
  -v pe-etc:/etc/puppetlabs \
  -v pe-opt:/opt/puppetlabs \
  -v pe-logs:/var/log/puppetlabs \
  -v $(pwd)/pe.conf:/config/pe.conf:ro \
  -v $(pwd)/license:/config/license:ro \
  pe-container:${PE_VERSION}
```

### Bootstrap Validation Checklist

After container starts, validate bootstrap progress through these steps:

#### Step 3a: Verify Configuration Validation
```bash
# Expected: preflight_validation succeeds
docker logs pe-primary | grep "preflight_validation"
# Output: [Bootstrap] Success: preflight_validation
```

#### Step 3b: Verify Console Password Validation
```bash
# Expected: console_password validation succeeds
docker logs pe-primary | grep "console_password_validation"
# Output: [Bootstrap] Success: console_password_validation
```

**If this fails**: Check pe.conf contains `console_password=<non-empty-value>`
```bash
grep "^console_password" /path/to/pe.conf | head -1
```

#### Step 3c: Verify Installing State Transition
```bash
# Expected: lifecycle state transitions to "installing"
docker logs pe-primary | grep "set_installing_marker"
# Output: [Bootstrap] Success: set_installing_marker
```

#### Step 3d: Monitor Installer Execution
```bash
# Expected: installer runs (15-30 minutes typical for PE)
# Monitor logs in real-time
docker logs -f pe-primary

# Look for progress indicators from PE installer
# This phase typically outputs lines like:
# - Installation progress checks
# - Service startup messages
# - Database initialization
```

#### Step 3e: Verify Installation Completion
```bash
# Expected: install completion marker persisted
docker logs pe-primary | grep "persist_install_completion"
# Output: [Bootstrap] Success: persist_install_completion
```

#### Step 3f: Verify Installer Cleanup
```bash
# Expected: installer artifacts removed
docker logs pe-primary | grep "cleanup_installer_artifacts"
# Output: [Bootstrap] Success: cleanup_installer_artifacts

# Confirm staging directory is empty:
docker exec pe-primary ls -la /puppet/installer-staging/
# Should be empty or show only subdirectory structure, no tar.gz
```

#### Step 3g: Verify Bootstrap Complete
```bash
# Expected: Final bootstrap success message
docker logs pe-primary | grep "Bootstrap Complete"
# Output: === Bootstrap Complete ===
```

Expected result:

- Startup enters first-install mode.
- All bootstrap validation steps succeed in sequence.
- Lifecycle markers and version marker are persisted on success.
- Installer tar.gz and extracted installer payload are removed from runtime filesystem after install verification.
- Service reaches healthy `/status/v1/simple`.


## 4. Restart Validation (T038 - Restart Behavior)

After successful bootstrap completion, validate restart behavior:

### Step 4a: Initial Health Check
```bash
# Verify container is healthy after bootstrap  
docker ps --format 'table {{.Names}}\t{{.Status}}'
# Expected: Status shows "healthy"

# Verify via health endpoint
docker exec pe-primary /puppet/healthcheck.sh
echo "Exit code: $?"  # Should be 0 (healthy)
```

### Step 4b: Trigger Container Restart
```bash
# Stop and restart the container
docker stop pe-primary
docker start pe-primary

# Monitor startup logs (should skip installer)
docker logs pe-primary | tail -20
# Expected: "Restoring from persisted state" (NOT "Starting: preflight_validation")
```

### Step 4c: Verify Restore, Not Reinstall
```bash
# Confirm no bootstrap re-execution
docker logs pe-primary | grep -c "preflight_validation" || echo "0"
# Expected: Does not show bootstrap steps (or shows 0 matches)

# Confirm restore path was taken
docker logs pe-primary | grep "Restoring from persisted state"
# Expected: Found in logs
```

### Step 4d: Verify Health After Restart
```bash
# Verify container is still healthy
sleep 10  # Wait for services to stabilize
docker ps --format 'table {{.Names}}\t{{.Status}}'
# Expected: Status still shows "healthy"

docker exec pe-primary /puppet/healthcheck.sh
echo "Exit code: $?"  # Should be 0 (healthy)
```

### Step 4e: Verify Persistence Across Restart
```bash
# Check that PE configuration is preserved
docker exec pe-primary [ -f /etc/puppetlabs/pe/pe.conf ] && echo "Found" || echo "Missing"
# Expected: "Found"

# Verify version marker matches
docker exec pe-primary cat /puppet/state/.pe-version 2>/dev/null
# Expected: Shows version number (e.g., "2024.7.0")
```

**Expected Outcome**:
- Container restarts and immediately enters healthy state (no installer re-execution)
- PE services are restored from persisted volumes
- Configuration and installed version are preserved

---

### Invalid Build Inputs

- Omit `PE_VERSION` or point `PE_INSTALLER_TAR_PATH` to missing file.
- Confirm build fails fast and no successful build artifact is reported.

### Version Mismatch on Restart (T038)

- Start a different image version against existing persisted state.
- Confirm startup is blocked with operator-action-required messaging.

```bash
# After successful bootstrap with version 2024.7.0, create new image with 2025.0.0
PE_VERSION_OLD="2024.7.0"
PE_VERSION_NEW="2025.0.0"

# Build new version image
docker build \
  --build-arg PE_VERSION=${PE_VERSION_NEW} \
  --build-arg PE_INSTALLER_TAR_PATH=/path/to/pe-${PE_VERSION_NEW}.tar.gz \
  -t pe-container:${PE_VERSION_NEW} .

# Tag as latest and restart (against old volumes)
docker tag pe-container:${PE_VERSION_NEW} pe-container:latest
docker restart pe-primary

# Verify blocked with version mismatch error
docker logs pe-primary | grep "Version mismatch"  # Expected
docker ps pe-primary  # Should show exited state
```

### Partial Install Recovery (T038)

- Simulate failed first install that leaves partial state (interrupt mid-bootstrap)
- Confirm subsequent starts remain blocked until explicit reset
- Confirm repeated agent runs do not trigger installation retry before reset

```bash
# Simulate interruption during bootstrap
docker run -d ... pe-container:${PE_VERSION}
sleep 15 && docker kill pe-primary  # Kill mid-install

# Verify state = installing (interrupted)
docker logs pe-primary | grep "installing"

# Try to restart (should fail with reset-required message)
docker start pe-primary
sleep 5
docker ps pe-primary  # Should be exited
docker logs pe-primary | grep "reset-required"

# Try restarting again without reset (simulates agent retry)
docker start pe-primary
sleep 5
docker ps pe-primary  # Still exited - no auto-retry!

# Now reset and retry
docker exec pe-primary /puppet/reset-runtime-state.sh
docker restart pe-primary  # Bootstrap retries from beginning
```

### Failed Bootstrap Retry Blocking (T338)

- Bootstrap fails due to invalid config (e.g., missing console_password)
- Verify subsequent starts remain blocked
- Verify explicit reset is required before retry

```bash
#Create broken pe.conf (missing console_password)
cat > /tmp/broken.conf << 'EOF'
puppet_enterprise::profile::master::certname=puppet.example.com
# Missing console_password!
EOF

# First boot fails
docker run -d \
  -v /tmp/broken.conf:/etc/puppetlabs/pe/pe.conf:ro \
  -v pe-state:/puppet/state \
  pe-container:${PE_VERSION}

sleep 20 && docker logs pe-primary | grep "console_password_validation"  # Shows failure

# Try restart (still fails, no retry)
docker restart pe-primary
sleep 5
docker ps pe-primary  # Still exited

# Fix config and reset
cat > /tmp/fixed.conf << 'EOF'
puppet_enterprise::profile::master::certname=puppet.example.com
console_password=SecurePassword123!
EOF

docker exec pe-primary /puppet/reset-runtime-state.sh
docker restart pe-primary  # Bootstrap retries with fixed config
```

### Post-Install `pe.conf` Drift Ignore (T338)

- Change `pe.conf` after successful install
- Restart container  
- Confirm startup restores persisted runtime and does not reinstall with new config

```bash
# After successful bootstrap...
# Modify pe.conf with new settings
cat > /tmp/modified.conf << 'EOF'
puppet_enterprise::profile::master::certname=puppet.example.com
console_password=NewPassword456!  # Changed password
puppet_enterprise::profile::master::code_manager_auto_configure=false  # New setting
EOF

# Restart (using modified config, but should ignore it)
docker stop pe-primary
# (In practice, Docker Compose volume remount or re-exec)
docker start pe-primary

# Verify old configuration is used (not new one)
docker logs pe-primary | grep "Restoring from persisted state"  # Restore message (no reinstall)
# PE continues with original settings, not modified ones


## 6. Reset Workflow

Example workflow:

```bash
docker run --rm \
  -v pe-etc:/etc/puppetlabs \
  -v pe-opt:/opt/puppetlabs \
  -v pe-logs:/var/log/puppetlabs \
  pe-container:${PE_VERSION} reset-runtime-state
```

Expected result:

- Runtime lifecycle markers are cleared through explicit operator action.
- Next start behaves as fresh first boot.

## 9. Final Validation Notes (T046)

The following checklist summarises the complete validated workflow for this feature.

### Build Validation

```bash
# ✅ Valid build
make build PE_VERSION=2024.7.0 PE_INSTALLER_TAR_PATH=/absolute/path/to/installer.tar.gz
docker images pe-container  # Shows pe-container:2024.7.0 and pe-container:latest

# ✅ Fail-fast: relative path rejected before Docker starts
make build PE_VERSION=2024.7.0 PE_INSTALLER_TAR_PATH=relative/path.tar.gz
# Expected: "ERROR: PE_INSTALLER_TAR_PATH must be absolute"

# ✅ Fail-fast: missing file rejected
make build PE_VERSION=2024.7.0 PE_INSTALLER_TAR_PATH=/nonexistent/file.tar.gz
# Expected: "ERROR: PE_INSTALLER_TAR_PATH file not found"
```

### Bootstrap Validation

```bash
# ✅ Valid first boot
docker logs pe-primary | grep "Bootstrap Complete"

# ✅ Invalid first boot (no console_password)
docker logs pe-primary | grep "console_password_validation"
# Expected failure message + failed marker

# ✅ Installed marker exists after successful bootstrap
docker exec pe-primary cat /puppet/state/.installed

# ✅ Installer artifacts removed post-bootstrap
docker exec pe-primary ls /puppet/installer-staging/  # Empty
```

### Restart Validation

```bash
# ✅ Restart restores without reinstall
docker restart pe-primary
docker logs pe-primary | grep "Restoring from persisted state"

# ✅ Version mismatch blocks startup
# (Build new version image, restart against old volumes)
docker logs pe-primary | grep "Version mismatch"  # Expected error

# ✅ Failed state blocks retry
# (Bootstrap with broken pe.conf)
docker restart pe-primary  # Still fails without reset
```

### Reset Validation

```bash
# ✅ Explicit reset returns to uninitialized
docker exec pe-primary /puppet/reset-runtime-state.sh
docker restart pe-primary
docker logs pe-primary | grep "First-time setup detected"  # Bootstrap retries
```

### Connected Nodes Validation

```bash
# ✅ Nodes present before and after restart
diff <(jq -r '.[].certname' nodes-before.json | sort) \
     <(jq -r '.[].certname' nodes-after.json | sort)  # Empty diff

# ✅ Certificates unchanged
diff certs-before.txt certs-after.txt  # Empty diff
```

### ShellCheck Validation

```bash
# ✅ All scripts pass at warning severity
shellcheck --severity=warning container/scripts/**/*.sh container/scripts/*.sh
echo "Exit: $?"  # 0
```

**All success criteria verified.** See [evidence-matrix.md](./contracts/evidence-matrix.md) for per-criterion evidence commands.

---

## 8. Connected-Node Continuity Evidence (T040a)

This section captures evidence that previously connected nodes survive a PE container restart.

### Step 8a: Pre-Restart Snapshot

```bash
# Capture node list before restart
docker exec pe-primary /opt/puppetlabs/bin/puppet query 'nodes[certname,report_timestamp] {}' \
  --format json > /tmp/nodes-before-restart.json

# Capture certificate list
docker exec pe-primary /opt/puppetlabs/bin/puppet cert list --all \
  > /tmp/certs-before-restart.txt

echo "Snapshot timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > /tmp/restart-evidence-log.txt
cat /tmp/nodes-before-restart.json >> /tmp/restart-evidence-log.txt
echo "---" >> /tmp/restart-evidence-log.txt
cat /tmp/certs-before-restart.txt >> /tmp/restart-evidence-log.txt
```

### Step 8b: Restart PE Container

```bash
docker restart pe-primary

# Wait for healthy status (up to 2 min)
for i in {1..24}; do
  docker exec pe-primary /puppet/healthcheck.sh && break || sleep 5
done
echo "PE restarted at: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> /tmp/restart-evidence-log.txt
```

### Step 8c: Post-Restart Comparison

```bash
# Capture node list after restart
docker exec pe-primary /opt/puppetlabs/bin/puppet query 'nodes[certname,report_timestamp] {}' \
  --format json > /tmp/nodes-after-restart.json

# Compare — expect no difference in certnames
diff \
  <(jq -r '.[].certname' /tmp/nodes-before-restart.json | sort) \
  <(jq -r '.[].certname' /tmp/nodes-after-restart.json | sort)
# Expected: empty diff (same nodes before and after)

# Compare certificates
docker exec pe-primary /opt/puppetlabs/bin/puppet cert list --all \
  > /tmp/certs-after-restart.txt
diff /tmp/certs-before-restart.txt /tmp/certs-after-restart.txt
# Expected: empty diff (same certificates)
```

### Step 8d: Verify Agent Connectivity Post-Restart

```bash
# Trigger agent run on a known node to prove it can still reach PE
# (Run from the agent node, not the PE container)
puppet agent -t  # On agent-node-1
# Expected: Run completes and new report appears in PE

# Verify new report in PE
docker exec pe-primary /opt/puppetlabs/bin/puppet node status agent-node-1.example.local
# Expected: Shows report timestamp AFTER the restart
```

**Expected Outcome**:
- ✅ Node list identical before and after restart
- ✅ Certificates unchanged
- ✅ Agents connect and run successfully
- ✅ New run reports appear post-restart
