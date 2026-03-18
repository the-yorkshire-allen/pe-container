# Release Notes (T045)

## Known Limitations and Design Constraints

---

### Version-Locked Persistence

**Summary**: Each container image is locked to a single PE version. Persistence volumes are bound to that version at bootstrap time.

**Detail**:
- PE version is declared as a Docker build argument (`PE_VERSION`) and baked into image metadata.
- At first-boot bootstrap, the installed version is persisted to `/puppet/state/.pe-version`.
- On every subsequent restart, the runtime validates that the image version matches the persisted version.
- **If versions differ, startup is blocked** with a `reset-required` state and operator-visible error.

**Implication for Upgrades**:
There is no in-place upgrade path. To move to a new PE version:
1. Back up persistence volumes (PE config, data, logs).
2. Build a new image with the new `PE_VERSION` and corresponding installer.
3. Perform a data migration (PE-supported backup/restore) to new volumes.
4. Start fresh bootstrap with new image.

---

### No Automatic Retry After Bootstrap Failure

**Summary**: If first-boot installation fails, the container does not retry. An explicit operator reset is required before the next attempt.

**Detail**:
- Bootstrap failures write a `.failed` marker to the state volume.
- All subsequent container starts detect this marker and exit immediately (no installer re-run).
- This is intentional: it prevents cascading failures and forces the operator to review logs, correct root cause, and explicitly acknowledge the failure via `reset-runtime-state.sh`.

**Recovery**:
```bash
docker exec pe-primary /puppet/reset-runtime-state.sh
docker restart pe-primary
```

---

### Installer Tarball at Build Time Only

**Summary**: The PE installer tarball must be available as an absolute local path **at image build time**. Runtime installer fetching is not supported.

**Detail**:
- `PE_INSTALLER_TAR_PATH` must be an absolute path on the build host (starts with `/`).
- Relative paths, URLs, and S3/object-storage paths are not accepted.
- The installer is extracted into the image during the build stage and removed from the final image layer after bootstrap.

**Implication**:
- The build host must have the installer present locally.
- In CI/CD pipelines, download the installer to an absolute path before calling `docker build` or `make build`.

---

### AlmaLinux 9 Base Image

**Summary**: The container uses `almalinux:9` as the base image (RHEL 9 compatible). CentOS 7 is no longer used.

**Detail**:
- Prior versions used `centos:7`. CentOS 7 reached end-of-life and is no longer approved for PE primary deployments.
- `almalinux:9` provides RHEL 9 binary compatibility, long-term support, and current security patches.
- Rocky Linux 9 (`rockylinux:9`) is an equivalent alternative and can be substituted via `--build-arg BASE_IMAGE=rockylinux:9`.
- The package manager is `dnf` (not `yum`).

---

### Single-Primary Topology Only

**Summary**: This container supports a single PE primary. HA, multi-primary, and compile-master topologies are out of scope.

**Detail**:
- The lifecycle scripts, state machine, and persistence model are designed for one PE primary per container.
- Multiple replicas or compile masters would require separate PE topology configuration outside this project.

---

### Bootstrap Script Contains Installer Execution Placeholder

**Summary**: The `execute_installer()` function in `bootstrap-pe.sh` contains a placeholder log line instead of the actual PE installer invocation.

**Detail**:
The T025 task implements the installer execution flow with a comment noting:
```bash
# TODO: Implement actual pe-installer execution or puppet agent run
log_message INFO "[Placeholder] Would run: cd ${PE_INSTALLER_STAGING} && ./puppet-enterprise-installer -c ${PE_CONF_FILE}"
```

**This must be replaced** with the actual installer command before production use:
```bash
cd "${PE_INSTALLER_STAGING}" && ./puppet-enterprise-installer -c "${PE_CONF_FILE}" -y
```

The placeholder exists because the exact invocation depends on the PE version and target platform. Operators must implement and test the actual call for their PE version.

---

### External Validation Handoff Required for Node Continuity

**Summary**: Full node continuity validation (Check 6 in `external-validation.md`) requires live agent nodes to run.

**Detail**:
- Checks 1–5 (node count, certnames, certificates, lifecycle marker, version) can be validated with the PE container alone.
- Check 6 (post-restart agent run) requires at least one connected agent node to be present and able to run.
- CI pipelines using only the PE primary container cannot execute Check 6 without a connected agent.

See [external-validation.md](../specs/001-containerize-pe/contracts/external-validation.md) for the full validation template.
