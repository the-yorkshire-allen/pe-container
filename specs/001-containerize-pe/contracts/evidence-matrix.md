# Success Criteria Evidence Matrix (T049)

Validates that each success criterion from `spec.md` has observable, testable evidence.

---

## SC-001: Build — Fail-Fast on Invalid Inputs

### SC-001a: Non-absolute path rejected at build time

| Evidence Type | Command | Expected Output |
|---------------|---------|-----------------|
| Build fails | `make build PE_VERSION=2024.7.0 PE_INSTALLER_TAR_PATH=relative/path.tar.gz` | `ERROR: PE_INSTALLER_TAR_PATH must be an absolute path` |
| Build fails | `docker build --build-arg PE_VERSION=2024.7.0 --build-arg PE_INSTALLER_TAR_PATH=./installer.tar.gz container/` | Build exits non-zero with path validation error |
| Makefile validates | `make build PE_VERSION=2024.7.0 PE_INSTALLER_TAR_PATH=relative/path.tar.gz` | `ERROR: PE_INSTALLER_TAR_PATH must be absolute` before Docker build starts |

**Status**: ✅ Implemented — `validate_installer_tar_at_build_time()` in `lib/state.sh`, Makefile pre-check

---

### SC-001b: Valid inputs produce tagged, runnable image

| Evidence Type | Command | Expected Output |
|---------------|---------|-----------------|
| Image tagged | `docker images pe-container` | Shows `pe-container:2024.7.0` and `pe-container:latest` |
| Metadata present | `docker exec pe-primary cat /puppet/state/.build-metadata` | Shows `PE_VERSION=2024.7.0`, `BUILD_TIMESTAMP=…` |
| Entrypoint wired | `docker run --rm pe-container:2024.7.0 --help` | Container executes `start/healthcheck/reset-runtime-state` dispatch |

**Status**: ✅ Implemented — Dockerfile multi-stage build with metadata persistence

---

## SC-002: Bootstrap — First Boot from Valid `pe.conf`

### SC-002a: Bootstrap succeeds with valid `pe.conf` including `console_password`

| Evidence Type | Command | Expected Output |
|---------------|---------|-----------------|
| Preflight passes | `docker logs pe-primary \| grep preflight_validation` | `[Bootstrap] Success: preflight_validation` |
| Password validated | `docker logs pe-primary \| grep console_password_validation` | `[Bootstrap] Success: console_password_validation` |
| Installing marker set | `docker exec pe-primary cat /puppet/state/.installing 2>/dev/null \|\| docker exec pe-primary cat /puppet/state/.installed` | File exists |
| Installed marker written | `docker exec pe-primary cat /puppet/state/.installed` | File exists after bootstrap |
| Version persisted | `docker exec pe-primary cat /puppet/state/.pe-version` | Shows version string (e.g., `2024.7.0`) |
| Installer cleaned | `docker exec pe-primary ls /puppet/installer-staging/` | Directory empty |
| Healthcheck healthy | `docker exec pe-primary /puppet/healthcheck.sh; echo $?` | `0` |

### SC-002b: Bootstrap fails without `console_password` in `pe.conf`

| Evidence Type | Command | Expected Output |
|---------------|---------|-----------------|
| Fail-fast error | `docker logs pe-primary \| grep console_password_validation` | `[Bootstrap] Failed: console_password_validation` |
| Failed marker set | `docker exec pe-primary cat /puppet/state/.failed` | File exists |
| Not healthy | `docker exec pe-primary /puppet/healthcheck.sh; echo $?` | `1` |
| Guidance shown | `docker logs pe-primary \| grep "INSTALLATION FAILED"` | Remediation block visible in logs |

**Status**: ✅ Implemented — `bootstrap-pe.sh` (T023, T023a, T024–T027)

---

## SC-003: Restart — Restore Without Reinstall

### SC-003a: Second start skips installer and restores

| Evidence Type | Command | Expected Output |
|---------------|---------|-----------------|
| No bootstrap re-run | `docker logs pe-primary \| grep -c "preflight_validation"` | `1` (only from first boot, not second start) |
| Restore message | `docker logs pe-primary \| grep "Restoring from persisted state"` | Line present |
| Still healthy | `docker exec pe-primary /puppet/healthcheck.sh; echo $?` | `0` |
| Version unchanged | `docker exec pe-primary cat /puppet/state/.pe-version` | Same version as before restart |

**Status**: ✅ Implemented — `entrypoint.sh` `installed` branch (T034)

---

## SC-004: Restart — Version Mismatch Blocked

| Evidence Type | Command | Expected Output |
|---------------|---------|-----------------|
| Mismatch detected | `docker logs pe-primary \| grep "Version mismatch"` | `[ERROR] Version mismatch detected…` |
| Startup blocked | `docker ps pe-primary` | Container shows `Exited` status |
| State marker | `docker exec pe-primary cat /puppet/state/.reset-required` | File exists |
| Action guidance | `docker logs pe-primary \| grep "reset-runtime-state"` | Reset command shown in logs |

**Status**: ✅ Implemented — `entrypoint.sh` version check (T032)

---

## SC-005: Failed/Partial State — Retry Blocked

### SC-005a: Failed state blocks all subsequent starts

| Evidence Type | Command | Expected Output |
|---------------|---------|-----------------|
| Blocked message | `docker logs pe-primary \| grep "failed.*state"` | `Container found in 'failed' state…` |
| No reinstall | `docker logs pe-primary \| grep -c "preflight_validation"` | Count does NOT increase on re-start |
| Exit with error | `docker inspect pe-primary --format '{{.State.ExitCode}}'` | Non-zero |
| Guidance shown | `docker logs pe-primary \| grep "reset-runtime-state"` | Reset command in logs |

### SC-005b: Interrupted (installing) state requires explicit reset

| Evidence Type | Command | Expected Output |
|---------------|---------|-----------------|
| Blocked message | `docker logs pe-primary \| grep "reset-required"` | Message present |
| State escalated | `docker exec pe-primary cat /puppet/state/.reset-required` | File exists |
| Reset restores clean state | After `reset-runtime-state.sh`, `get_lifecycle_state` | Returns `uninitialized` |

**Status**: ✅ Implemented — `entrypoint.sh` `failed`/`installing` branches (T033)

---

## SC-006: Connected Nodes — Continuity After Restart

| Evidence Type | Command | Expected Output |
|---------------|---------|-----------------|
| Node list unchanged | `diff <(jq -r '.[].certname' nodes-before.json \| sort) <(jq -r '.[].certname' nodes-after.json \| sort)` | Empty diff |
| Certs unchanged | `diff certs-before.txt certs-after.txt` | Empty diff |
| Agent connects | `puppet agent -t` on agent node post-restart | Run completes, new report in PE |
| Continuity signal | `docker logs pe-primary \| grep "continuity signal"` | Signal line with node count |

**Status**: ✅ Implemented — persistence volumes retain node data; `log_node_continuity_signal()` in `logging.sh` (T036a); full procedure in `external-validation.md` (T044)

---

## SC-007: Scope Documentation Unambiguous

| Evidence Type | Artifact | Expected Content |
|---------------|----------|-----------------|
| Explicit IN scope list | `container/docs/scope-boundaries.md` | Sections: PE Primary, Connected Agents, Operator Tooling |
| Explicit OUT of scope table | `container/docs/scope-boundaries.md` | Tables for Infrastructure, PE Features, Operational Concerns |
| Runtime contract scope | `specs/001-containerize-pe/contracts/container-runtime.md` | Scope section with IN/OUT list |
| Quickstart boundaries | `specs/001-containerize-pe/quickstart.md` | "Unsupported Operations" section |

**Status**: ✅ Implemented — T041 (scope-boundaries.md), T043 (contract scope update)

---

## Overall Evidence Summary

| SC | Title | Status | Evidence Location |
|----|-------|--------|-------------------|
| SC-001a | Non-absolute path rejected | ✅ | `lib/state.sh`, `Makefile` |
| SC-001b | Valid inputs → tagged image | ✅ | `Dockerfile`, build metadata |
| SC-002a | Bootstrap with valid config | ✅ | `bootstrap-pe.sh`, logs |
| SC-002b | Bootstrap fails without password | ✅ | `bootstrap-pe.sh`, failed marker |
| SC-003 | Restart restores without reinstall | ✅ | `entrypoint.sh`, restore branch |
| SC-004 | Version mismatch blocked | ✅ | `entrypoint.sh`, reset-required marker |
| SC-005a | Failed state blocks retries | ✅ | `entrypoint.sh`, failed branch |
| SC-005b | Interrupted state requires reset | ✅ | `entrypoint.sh`, installing branch |
| SC-006 | Node continuity after restart | ✅ | volumes, `logging.sh`, `external-validation.md` |
| SC-007 | Scope docs unambiguous | ✅ | `scope-boundaries.md`, `container-runtime.md` |

**All 10 success criteria have documented, testable evidence.**
