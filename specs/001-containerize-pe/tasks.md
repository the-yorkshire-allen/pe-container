# Tasks: Containerized Puppet Enterprise

**Input**: Design documents from `/specs/001-containerize-pe/`
**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/`

**Tests**: In-container validation tasks are limited to `/status/v1/simple` smoke checks and build-interface validation steps. Deeper behavioral and node-manageability verification is produced as an external validation handoff package.

**Organization**: Tasks are grouped by user story to enable independent implementation and validation of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., [US1], [US2], [US3], [US4])
- Every task includes an exact file path

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize container project structure and baseline tooling.

- [ ] T001 Create repository placeholders for container and tests roots in container/.gitkeep and tests/.gitkeep
- [ ] T002 Create baseline Docker image scaffold with lifecycle script copy points in container/Dockerfile
- [ ] T003 [P] Add container build exclusions in container/.dockerignore
- [ ] T004 [P] Add operator command wrappers for build, run, restart-check, and reset in Makefile
- [ ] T005 [P] Configure shell lint defaults for lifecycle scripts in .shellcheckrc
- [ ] T006 [P] Add installer artifact handling and local path usage notes in container/assets/examples/README.md

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Implement shared primitives required before any user story work.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T007 Define lifecycle constants, marker paths, and state transition helpers in container/scripts/lib/state.sh
- [ ] T008 [P] Implement structured logging/status helper functions in container/scripts/lib/logging.sh
- [ ] T009 Implement configured persistence path validation and writability checks in container/scripts/validate-runtime-state.sh
- [ ] T010 Implement entrypoint command dispatcher (`start`, `healthcheck`, `reset-runtime-state`) in container/scripts/entrypoint.sh
- [ ] T011 [P] Implement startup health outcome mapping in container/scripts/healthcheck.sh
- [ ] T012 [P] Add `/status/v1/simple` probe helper for startup and smoke checks in container/scripts/lib/status-probe.sh
- [ ] T013 Implement explicit runtime reset operation for lifecycle markers in container/scripts/reset-runtime-state.sh
- [ ] T014 Wire PID 1 init, startup command, and healthcheck invocation in container/Dockerfile
- [ ] T015 Add baseline runtime compose profile with persistence and config mounts in container/compose/docker-compose.example.yml

**Checkpoint**: Foundation ready; user story implementation can begin.

---

## Phase 3: User Story 1 - Build a versioned PE image from operator-provided installer inputs (Priority: P1) 🎯 MVP

**Goal**: Build process accepts PE version and local absolute installer tar.gz path, validates inputs, stages extracted installer payload, and emits runnable version-identifiable image artifacts.

**Independent Test**: Run build with valid inputs and verify a tagged image is produced with staged installer content; run with invalid or non-absolute installer path and verify fail-fast behavior with actionable output.

### Implementation for User Story 1

- [ ] T016 [US1] Implement Docker build arguments (`PE_VERSION`, `PE_INSTALLER_TAR_PATH`) and input guardrails in container/Dockerfile
- [ ] T017 [US1] Add build-time installer path validation helper logic in container/scripts/lib/state.sh
- [ ] T017a [US1] Enforce absolute-path-only validation for `PE_INSTALLER_TAR_PATH` in container/scripts/lib/state.sh
- [ ] T018 [US1] Implement build wrapper command enforcing required input args in Makefile
- [ ] T018a [US1] Implement installer tar.gz extraction into container-local staging path during image build in container/Dockerfile
- [ ] T019 [P] [US1] Add build contract examples and required input documentation in specs/001-containerize-pe/contracts/build-interface.md
- [ ] T019a [US1] Implement mandatory installer artifact/version identity verification during build in container/scripts/lib/state.sh
- [ ] T020 [US1] Persist image/version build metadata for runtime compatibility checks in container/scripts/lib/state.sh
- [ ] T021 [P] [US1] Document local-absolute-path installer build workflow in container/README.md
- [ ] T022 [US1] Add quickstart build validation steps for valid and invalid inputs in specs/001-containerize-pe/quickstart.md

**Checkpoint**: Build pipeline is independently usable and validates required inputs.

---

## Phase 4: User Story 2 - Bootstrap a PE container from configuration (Priority: P2)

**Goal**: First launch with valid `pe.conf` performs one-time installation and records deterministic installed/failed state.

**Independent Test**: Start from empty persistence with valid config and verify bootstrap reaches healthy `/status/v1/simple`; run without valid config and verify non-healthy actionable failure outcome.

### Implementation for User Story 2

- [ ] T023 [P] [US2] Add first-boot preflight validation for `pe.conf` and license material in container/scripts/bootstrap-pe.sh
- [ ] T023a [US2] Add explicit console-password-in-`pe.conf` validation and fail-fast messaging in container/scripts/bootstrap-pe.sh
- [ ] T024 [US2] Implement transition to `installing` marker prior to installer execution in container/scripts/bootstrap-pe.sh
- [ ] T025 [US2] Implement one-time PE installer execution and configuration flow in container/scripts/bootstrap-pe.sh
- [ ] T026 [US2] Persist successful install completion and runtime version marker in container/scripts/bootstrap-pe.sh
- [ ] T026a [US2] Remove installer archive and extracted payload after verified install completion in container/scripts/bootstrap-pe.sh
- [ ] T027 [P] [US2] Implement bootstrap failure handling that writes `failed` state and remediation guidance in container/scripts/bootstrap-pe.sh
- [ ] T028 [US2] Integrate first-boot orchestration branch in container/scripts/entrypoint.sh
- [ ] T029 [P] [US2] Add first-boot operator runbook with expected status outcomes in container/README.md
- [ ] T030 [US2] Add first-boot smoke-check commands for `/status/v1/simple` in specs/001-containerize-pe/quickstart.md

**Checkpoint**: First-boot install flow is independently functional.

---

## Phase 5: User Story 3 - Restart without reinstalling (Priority: P3)

**Goal**: Restart restores from persisted state, blocks unsupported version mismatches, and enforces explicit reset for partial-failure states.

**Independent Test**: Restart after successful install and verify no reinstall; run mismatch and failed-partial-state scenarios and verify blocked startup with operator-action-required outcomes.

### Implementation for User Story 3

- [ ] T031 [US3] Implement restart state classifier (`installed`, `failed`, `reset-required`, `uninitialized`) in container/scripts/validate-runtime-state.sh
- [ ] T032 [US3] Enforce persisted-state version marker match against image metadata in container/scripts/validate-runtime-state.sh
- [ ] T033 [US3] Block auto-retry after failed bootstrap until explicit reset, including repeated agent runs, in container/scripts/entrypoint.sh
- [ ] T034 [US3] Implement restore path that skips installer on valid installed state in container/scripts/entrypoint.sh
- [ ] T035 [P] [US3] Implement post-install `pe.conf` drift ignore logic in container/scripts/entrypoint.sh
- [ ] T036 [US3] Implement intervention-required startup messaging categories in container/scripts/lib/logging.sh
- [ ] T037 [US3] Update runtime contract for restart, mismatch, and reset-required behavior in specs/001-containerize-pe/contracts/container-runtime.md
- [ ] T038 [US3] Add restart and blocked-state smoke validation procedures in specs/001-containerize-pe/quickstart.md

**Checkpoint**: Restart behavior is deterministic and independently verifiable.

---

## Phase 6: User Story 4 - Manage only the PE instance and connected nodes (Priority: P4)

**Goal**: Delivery clearly supports management of the PE container and connected nodes only, with documented boundaries.

**Independent Test**: Run node-onboarding scenario and verify continuity across restart; verify documentation clearly limits scope to connected-node management.

### Implementation for User Story 4

- [ ] T039 [US4] Add node-simulation compose profile for primary and connected node workflow in container/compose/docker-compose.node-example.yml
- [ ] T040 [US4] Add connected-node onboarding and continuity runbook in container/docs/connected-nodes.md
- [ ] T041 [P] [US4] Add explicit in-scope/out-of-scope boundary documentation in container/docs/scope-boundaries.md
- [ ] T042 [US4] Add operator quick-reference commands for connected-node flow in container/README.md
- [ ] T043 [US4] Align runtime contract scope language for connected-node boundaries in specs/001-containerize-pe/contracts/container-runtime.md
- [ ] T044 [US4] Produce external validation handoff template for node continuity metrics in specs/001-containerize-pe/contracts/external-validation.md

**Checkpoint**: Connected-node scope is documented and operationally demonstrable.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final hardening, traceability, and release readiness across stories.

- [ ] T045 [P] Add release notes and known limitations for version-locked persistence in container/docs/release-notes.md
- [ ] T046 Run full quickstart walkthrough and capture final validation notes in specs/001-containerize-pe/quickstart.md
- [ ] T047 [P] Verify ShellCheck conformance and record findings in container/docs/linting.md
- [ ] T048 [P] Produce requirement-to-implementation traceability mapping in specs/001-containerize-pe/contracts/traceability.md
- [ ] T049 [P] Add success criteria evidence matrix for build and runtime validation outcomes in specs/001-containerize-pe/contracts/evidence-matrix.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies; start immediately.
- **Phase 2 (Foundational)**: Depends on Phase 1 and blocks all user stories.
- **Phase 3 (US1)**: Depends on Phase 2.
- **Phase 4 (US2)**: Depends on Phase 2 and US1 build-output conventions.
- **Phase 5 (US3)**: Depends on Phase 2 and US2 lifecycle markers.
- **Phase 6 (US4)**: Depends on Phase 2 and stable runtime behavior from US2/US3.
- **Phase 7 (Polish)**: Depends on completion of all user stories.

### User Story Dependencies

- **US1 (P1)**: Starts after Foundational; no dependency on other stories.
- **US2 (P2)**: Depends on US1 image build contract and artifact expectations.
- **US3 (P3)**: Depends on US2 bootstrap state and version markers.
- **US4 (P4)**: Depends on US2/US3 operational primary behavior.

### Within Each User Story

- Build/runtime state primitives before user-facing documentation updates.
- Startup behavior before smoke-validation instructions.
- Story checkpoint validation before moving to next priority story.

## Parallel Opportunities

- **Setup**: T003, T004, T005, and T006 can run in parallel after T001/T002.
- **Foundational**: T008, T011, and T012 can run in parallel once T007 is established.
- **US1**: T019 and T021 can run in parallel with T016/T017a/T018a.
- **US2**: T023 and T023a can run in parallel with bootstrap core tasks.
- **US3**: T035 can run in parallel with T032/T033 after T031 exists.
- **US4**: T041 can run in parallel with T039/T040.
- **Polish**: T045, T047, T048, and T049 can run in parallel.

---

## Parallel Example: User Story 1

```bash
# Parallel track A (contract and docs)
Task T019: Update build interface contract in specs/001-containerize-pe/contracts/build-interface.md
Task T021: Document build workflow in container/README.md

# Parallel track B (build implementation)
Task T016: Add build args and guardrails in container/Dockerfile
Task T018a: Add installer extraction staging in container/Dockerfile
```

## Parallel Example: User Story 2

```bash
# Parallel track A (bootstrap execution)
Task T024: Set installing marker in container/scripts/bootstrap-pe.sh
Task T025: Implement one-time installer flow in container/scripts/bootstrap-pe.sh

# Parallel track B (failure handling)
Task T023a: Add console-password validation in container/scripts/bootstrap-pe.sh
Task T027: Write failed-state handling in container/scripts/bootstrap-pe.sh
Task T029: Add first-boot runbook in container/README.md
```

## Parallel Example: User Story 3

```bash
# Parallel track A (state and startup logic)
Task T032: Enforce version marker match in container/scripts/validate-runtime-state.sh
Task T034: Implement restore path in container/scripts/entrypoint.sh

# Parallel track B (operator visibility)
Task T036: Add intervention-required messaging in container/scripts/lib/logging.sh
Task T038: Add restart blocked-state validation in specs/001-containerize-pe/quickstart.md
```

## Parallel Example: User Story 4

```bash
# Parallel track A (runtime examples)
Task T039: Add node example compose profile in container/compose/docker-compose.node-example.yml
Task T040: Add connected-node runbook in container/docs/connected-nodes.md

# Parallel track B (scope boundaries)
Task T041: Add scope boundary documentation in container/docs/scope-boundaries.md
Task T043: Align scope language in specs/001-containerize-pe/contracts/container-runtime.md
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (Setup).
2. Complete Phase 2 (Foundational).
3. Complete Phase 3 (US1).
4. Validate build success/failure contract behavior before proceeding.

### Incremental Delivery

1. Deliver US1 build pipeline and contract.
2. Add US2 first-boot lifecycle behavior.
3. Add US3 restart and blocked-state enforcement.
4. Add US4 connected-node scope and operational guidance.
5. Complete Phase 7 polish and traceability.

### Parallel Team Strategy

1. Team completes Setup + Foundational.
2. After foundation: one stream implements build flow (US1), another stream prepares bootstrap logic (US2 prework), and a docs stream prepares contracts/examples.
3. Reconverge for US3 restart safety and US4 scope docs, then polish.

---

## Notes

- All tasks follow strict checklist format with task ID and file path.
- `[P]` indicates tasks that can proceed in parallel with low merge-conflict risk.
- `[US1]` through `[US4]` labels provide traceability from tasks to user stories.
- Suggested MVP scope is through Phase 3 (US1) after foundational completion.
