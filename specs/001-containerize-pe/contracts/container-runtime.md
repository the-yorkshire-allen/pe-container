# Contract: Container Runtime Interface

## Purpose

Define operator-facing runtime behavior for first boot, restart, recovery, and health signaling.

## Required Runtime Inputs

### Configuration Inputs

- A valid `pe.conf` must be mounted and readable before first successful bootstrap.
- `pe.conf` must include console password for first-time installation.
- Installer-required licensing material must be mounted and readable when required by the bundled installer.
- The running image must already contain one PE installer version.

### Persistence Inputs

- A configured persistence layer must be attached for PE configuration/certs, application state, and logs.
- Configured persistence targets must be writable by lifecycle scripts.

## Startup Modes

### First Boot

- **Preconditions**:
  - Persisted lifecycle state is `uninitialized`
  - Required runtime inputs validate successfully
- **Behavior**:
  - Run one-time install/configuration sequence
  - Publish `installing` state until completion/failure
- **Success Result**:
  - Persist lifecycle state `installed`
  - Persist version marker matching running image version
  - Remove installer archive and extracted installer payload from runtime filesystem after verification
  - Transition to healthy service state

### Normal Restart

- **Preconditions**:
  - Persisted lifecycle state is `installed`
  - Persisted version marker matches running image version
  - Persistence validation passes
- **Behavior**:
  - Skip installer execution
  - Restore service from persisted state
- **Success Result**:
  - Publish `restored`/ready outcome

### Blocked Restart

- **Triggered By**:
  - Missing/invalid persistence inputs
  - Persisted state corruption or incompleteness
  - Persisted version mismatch with image version
  - Prior failed install that has not been reset
- **Behavior**:
  - Do not reinstall automatically
  - Do not retry installation even if agent is run repeatedly after failure
  - Do not publish healthy outcome
  - Publish `intervention-required` with actionable guidance

## Supported Operator Actions

- Provide valid build artifact image produced from approved build process.
- Provide `pe.conf` and license material before first boot.
- Reuse same image version with same persistence layer for restart.
- Execute explicit reset flow after `failed`/`reset-required` states.

## Unsupported Operator Actions

- Treating image version change as in-place upgrade with existing persisted state.
- Expecting post-install `pe.conf` edits to trigger startup reconfiguration.
- Expecting automatic resume/retry after failed first install (including repeated agent runs) without explicit reset.

## Observable Outcomes

| Outcome | Meaning | Health Expectation | Operator Action |
|---------|---------|--------------------|-----------------|
| `installing` | First install in progress | Not ready | Wait and monitor logs |
| `install-failed` | First install failed | Not healthy | Remediate and reset |
| `restored` | Existing install restored | Ready | None |
| `intervention-required` | Startup blocked by invalid state/prereqs | Not healthy | Follow surfaced remediation |

## Contract Test Targets

- First boot with valid inputs reaches `installing` then healthy.
- Restart with matching image version restores without reinstall.
- Restart with mismatched image version is blocked and unhealthy.
- Restart after failed bootstrap remains blocked until explicit reset.
- Post-install `pe.conf` updates do not trigger reinstall.
