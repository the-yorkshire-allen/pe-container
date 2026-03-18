# Research: Containerized Puppet Enterprise Build and Runtime

## Decision 1: Build-first workflow with strict installer inputs

- **Decision**: The delivery flow starts with `docker build` and requires Puppet Enterprise version plus a local absolute installer tar.gz path.
- **Rationale**: Deterministic image creation and predictable CI behavior require explicit and stable build inputs.
- **Alternatives considered**:
  - URL-based installer retrieval: rejected due to network dependency and non-deterministic build behavior.
  - Relative/local-optional path modes: rejected to avoid ambiguous path resolution across environments.

## Decision 2: Build must stage extracted installer content

- **Decision**: Build process extracts installer tar.gz into a container-local staging location ready for first-time installation.
- **Rationale**: Avoids runtime extraction complexity and ensures bootstrap flow starts from known prepared artifacts.
- **Alternatives considered**:
  - Extract during startup: rejected as slower and less deterministic for initial container initialization.

## Decision 3: Remove installer artifacts after verified installation

- **Decision**: After first installation is complete and verified, remove installer tar.gz and extracted installer payload from runtime filesystem.
- **Rationale**: Reduces runtime footprint and avoids retaining unnecessary installer material in long-lived containers.
- **Alternatives considered**:
  - Keep installer artifacts permanently: rejected due to avoidable runtime bloat and artifact hygiene concerns.

## Decision 4: Enforce one-version-per-image and persisted-state compatibility

- **Decision**: Each image represents one PE version and startup validates persisted version markers before restore.
- **Rationale**: Prevents unsupported in-place upgrade behavior via image swaps.
- **Alternatives considered**:
  - Best-effort startup with mismatched versions: rejected as unsafe and unpredictable.

## Decision 5: Fail-closed lifecycle after failed initialization

- **Decision**: After failed first initialization, startup and repeated agent runs (including running agent twice) remain halted until explicit reset/cleanup.
- **Rationale**: Prevents hidden retries and preserves deterministic recovery semantics.
- **Alternatives considered**:
  - Automatic retry/resume after failure: rejected due to potential state corruption and opaque failure loops.

## Decision 6: Require console password in `pe.conf` for first install

- **Decision**: First-time installation requires console password to be present in `pe.conf`; otherwise startup fails with actionable guidance.
- **Rationale**: Captures an operator-critical configuration prerequisite as an explicit contract.
- **Alternatives considered**:
  - Optional console password fallback behavior: rejected as ambiguous and potentially insecure.

## Decision 7: Keep `pe.conf` authoritative only for first bootstrap

- **Decision**: `pe.conf` is consumed for initial setup and ignored for startup-time reconfiguration after install completion.
- **Rationale**: Restart behavior remains stable; ongoing drift is handled by normal Puppet workflows.
- **Alternatives considered**:
  - Reprocess `pe.conf` at each restart: rejected because it converts restart into a reconfiguration path.

## Decision 8: Contract-driven operator interface

- **Decision**: Maintain explicit build and runtime contracts for input validation, startup modes, failure semantics, and recovery actions.
- **Rationale**: Enables independent validation and keeps plan/tasks/implementation aligned.
- **Alternatives considered**:
  - README-only guidance: rejected as insufficiently precise for testable behavior.
