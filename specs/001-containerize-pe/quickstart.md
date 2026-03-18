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


## 4. Restart Validation

Example workflow:

```bash
docker stop pe-primary
docker start pe-primary
```

Expected result:

- Restart skips installer.
- Service restores from persisted state.
- Healthy `/status/v1/simple` is observed again.

## 5. Failure Scenarios

### Invalid Build Inputs

- Omit `PE_VERSION` or point `PE_INSTALLER_TAR_PATH` to missing file.
- Confirm build fails fast and no successful build artifact is reported.

### Version Mismatch on Restart

- Start a different image version against existing persisted state.
- Confirm startup is blocked with operator-action-required messaging.

### Partial Install Recovery

- Simulate failed first install that leaves partial state.
- Confirm subsequent starts remain blocked until explicit reset.
- Confirm repeated agent runs do not trigger installation retry before reset.

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

## 7. Post-Install `pe.conf` Behavior

- Change `pe.conf` after successful install.
- Restart container.
- Confirm startup restores persisted runtime and does not reinstall.
