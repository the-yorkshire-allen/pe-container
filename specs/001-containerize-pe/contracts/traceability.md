# Requirement-to-Implementation Traceability (T048)

Maps every functional requirement from `spec.md` to the implementation files and tasks that satisfy it.

| Requirement | Description (condensed) | Implementation File(s) | Task(s) |
|-------------|--------------------------|------------------------|---------|
| FR-001a | Build process requires PE_VERSION + absolute installer path | `container/Dockerfile`, `Makefile` | T016, T018 |
| FR-001b | Build validates absolute path, accessibility, tar format before producing image | `container/scripts/lib/state.sh` (`validate_installer_tar_at_build_time`), `Makefile` | T017, T017a, T018 |
| FR-001c | Image is version-identifiable from operator-provided version | `container/Dockerfile` (build args, metadata), `container/scripts/lib/state.sh` | T016, T020 |
| FR-001d | `pe.conf` MUST include `console_password`; startup fails if missing/empty | `container/scripts/bootstrap-pe.sh` (`validate_console_password`) | T023a |
| FR-001e | Build extracts installer to container-local staging location | `container/Dockerfile` (multi-stage extraction to `/puppet/installer-staging`) | T018a |
| FR-001 | `pe.conf` is authoritative for first-time setup | `container/scripts/bootstrap-pe.sh` (`preflight_validation`) | T023 |
| FR-002 | Each image corresponds to exactly one PE installer version | `container/Dockerfile` (`PE_VERSION` build arg), `container/scripts/lib/state.sh` | T016, T020 |
| FR-003 | First launch installs and configures PE automatically | `container/scripts/bootstrap-pe.sh` (`main`), `container/scripts/entrypoint.sh` | T025, T028 |
| FR-003a | Installer artifacts removed after verified install | `container/scripts/bootstrap-pe.sh` (`cleanup_installer_artifacts`) | T026a |
| FR-004 | Installation completion recorded; prevents automatic reinstall | `container/scripts/bootstrap-pe.sh` (`persist_install_completion`), `container/scripts/lib/state.sh` (`set_installed_state`) | T026 |
| FR-005 | Subsequent launches restore from persisted state | `container/scripts/entrypoint.sh` (`startup_orchestrator`, `installed` branch) | T034 |
| FR-005a | Post-install `pe.conf` changes do not trigger reinstall | `container/scripts/entrypoint.sh` (`installed` branch notes drift ignore) | T035 |
| FR-006 | PE config, data, logs persisted across restart/reboot | `container/compose/docker-compose.pe-primary.yml` (volumes), `container/scripts/validate-runtime-state.sh` (`validate_persistence_paths`) | T009, T015 |
| FR-007 | Validate presence and integrity of persisted state at startup | `container/scripts/validate-runtime-state.sh` (`check_integrity`, `validate_markers`, `validate_marker_parseability`, `validate_version_metadata`) | T031, T031a |
| FR-007a | Version mismatch between persisted state and image blocks startup | `container/scripts/entrypoint.sh` (`verify_installer_version_match` call in restore path), `container/scripts/validate-runtime-state.sh` | T032 |
| FR-008 | Failed install → non-healthy state + actionable guidance | `container/scripts/bootstrap-pe.sh` (`handle_bootstrap_failure`), `container/scripts/lib/state.sh` (`set_failed_state`) | T027 |
| FR-008a | Partial state after failure → blocked until explicit reset | `container/scripts/entrypoint.sh` (`failed` branch, no auto-retry) | T033 |
| FR-008b | Repeated agent runs after failure do NOT trigger retry | `container/scripts/entrypoint.sh` (`failed` branch always exits 1) | T033 |
| FR-009 | Manage PE instance and connected nodes | `container/docs/connected-nodes.md`, `container/compose/docker-compose.connected-nodes.yml` | T039, T040 |
| FR-010 | Scope bounded to PE instance + connected nodes; no external infra | `container/docs/scope-boundaries.md`, `specs/001-containerize-pe/contracts/container-runtime.md` | T041, T043 |
| FR-011 | Persisted state retains connected node manageability across restart | `container/compose/docker-compose.pe-primary.yml` (volumes include `/etc/puppetlabs`), `container/scripts/validate-runtime-state.sh` | T009, T015 |
| FR-011a | Operator-visible node continuity signal on restart | `container/scripts/lib/logging.sh` (`log_node_continuity_signal`), `container/scripts/entrypoint.sh` | T036a |
| FR-012 | Startup outcome is distinguishable: installing / failed / restored / intervention-required | `container/scripts/lib/logging.sh` (`startup_outcome_message`), `container/scripts/entrypoint.sh` | T036 |
| FR-013 | Operator-controlled reset path | `container/scripts/reset-runtime-state.sh` | T013 |
| FR-014 | Docs identify persistence locations, one-time install, image-baked installer | `container/README.md`, `specs/001-containerize-pe/quickstart.md` | T021, T022 |
| FR-015 | Docs state `pe.conf` is first-time only; post-install via Puppet workflow | `container/README.md`, `specs/001-containerize-pe/contracts/container-runtime.md` | T021, T037 |
| FR-016 | Docs state persisted volumes are version-tied; image swap is not upgrade | `container/docs/release-notes.md`, `specs/001-containerize-pe/contracts/container-runtime.md` | T037, T045 |
| FR-017 | Produced image fulfills bootstrap, restart, failure-signaling, scoped node mgmt | `container/Dockerfile` (full build), all lifecycle scripts | T016–T049 |

---

## Success Criteria Coverage

| SC | Criterion | Satisfying Tasks |
|----|-----------|-----------------|
| SC-001a | Build fails if `PE_INSTALLER_TAR_PATH` is not absolute | T017a, T018 |
| SC-001b | 100% of builds with valid inputs produce a tagged, runnable image | T016–T020 |
| SC-002 | First launch with valid `pe.conf` (incl. `console_password`) reaches healthy state | T023–T028 |
| SC-003 | Restart with same version and intact state restores without reinstall | T031–T035 |
| SC-004 | Version mismatch blocks startup with clear operator message | T032 |
| SC-005 | Failed partial state blocks all retries until explicit reset | T033 |
| SC-006 | Connected nodes remain manageable after restart | T039–T040, T044 |
| SC-007 | Scope documentation unambiguous about in/out of scope | T041, T043 |

---

## Coverage Summary

- **28 functional requirements tracked**
- **All 28 have ≥1 implementing file and ≥1 task**
- **Coverage: 100%**
