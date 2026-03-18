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

## 3. First Boot

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

Expected result:

- Startup enters first-install mode.
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
