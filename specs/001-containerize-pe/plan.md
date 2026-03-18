# Implementation Plan: Containerized Puppet Enterprise

**Branch**: `001-containerize-pe` | **Date**: 2026-03-18 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-containerize-pe/spec.md`

## Summary

Deliver a build-first containerization flow where operators provide a Puppet Enterprise version and a local absolute installer tar.gz path, producing a version-identifiable Docker image that stages the installer for initialization, enforces strict bootstrap/restart state handling, and removes installer artifacts from the runtime filesystem once installation is verified.

## Technical Context

**Language/Version**: Bash 5.x lifecycle scripts, Dockerfile syntax 1.x, GNU coreutils
**Primary Dependencies**: Docker/OCI build tooling, Puppet Enterprise installer tar.gz artifact, `tini` as PID 1, ShellCheck
**Storage**: Operator-managed persistence targets for PE configuration/certs, application data, and logs; persisted lifecycle and version markers
**Testing**: ShellCheck for static validation, Docker smoke checks via `/status/v1/simple`, external validation harness for connected-node continuity
**Target Platform**: Linux x86_64 hosts running Docker Engine or compatible OCI runtime
**Project Type**: Single container-image project with runtime lifecycle scripts and operator-facing contracts
**Performance Goals**: Build fails fast on invalid input paths; first bootstrap reaches healthy `/status/v1/simple` in spec-defined window; restart path restores without reinstall
**Constraints**: Local absolute installer path only, one PE version per image, no in-place upgrade by image swap, no automatic retry after failed initialization (including repeated agent runs), console password required in `pe.conf` for first install
**Scale/Scope**: Single PE primary managing itself and explicitly connected nodes; no HA clustering or cross-version state migration orchestration

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Pre-Phase 0**: PASS against Constitution v1.0.0.
  - Host-independence is preserved: no host-targeting behavior is introduced.
  - Persistence semantics are preserved: state survives restart/migration through operator-managed persistence targets.
  - Observability data retention is preserved across restart and recovery paths.
- **Post-Phase 1 re-check**: PASS.
  - Build and runtime contracts maintain host-independence and persistence constraints.
  - No design flow discards state without explicit operator reset action.
  - No observability retention regressions are introduced.

## Project Structure

### Documentation (this feature)

```text
specs/001-containerize-pe/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── build-interface.md
│   └── container-runtime.md
└── tasks.md
```

### Source Code (repository root)

```text
container/
├── Dockerfile
├── .dockerignore
├── assets/
│   ├── pe-installer/
│   └── examples/
├── scripts/
│   ├── entrypoint.sh
│   ├── bootstrap-pe.sh
│   ├── validate-runtime-state.sh
│   ├── reset-runtime-state.sh
│   ├── healthcheck.sh
│   └── lib/
│       ├── state.sh
│       ├── logging.sh
│       └── status-probe.sh
└── compose/
    ├── docker-compose.example.yml
    └── docker-compose.node-example.yml

tests/
├── contract/
├── integration/
└── unit/
```

**Structure Decision**: Use one container-centric project layout so build-time input validation (absolute installer path), installer staging/cleanup semantics, and runtime state enforcement remain tightly coupled and testable.

## Complexity Tracking

No constitution violations or design exceptions currently require justification.
