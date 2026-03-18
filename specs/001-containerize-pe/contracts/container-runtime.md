# PE Container Runtime Contract: Restart, Restore, and Reset Behavior (T037)

## Overview

This contract specifies the deterministic behavior of restarted PE containers, including supported scenarios, failure states, and required operator actions.

## Scope (T043)

### This Contract Covers
- **Restart**: Lifecycle after successful first-boot bootstrap
- **Restore**: Recovering PE from persisted volumes
- **Reset**: Manual operator-triggered state cleanup
- **Connected Nodes**: Agent nodes that connect to this PE primary for Puppet runs and classification

### Out of Scope
- In-place PE version upgrades (requires new image build)
- Automatic retry after installation failure
- Configuration drift application from pe.conf after bootstrap
- Agent node infrastructure (OS provisioning, network, DNS)
- PE agent installation on remote nodes (operator responsibility)
- Running multiple PE versions simultaneously
- HA/multi-primary PE deployments

## Required Runtime Inputs

### Configuration Inputs

- A valid `pe.conf` must be mounted and readable before first successful bootstrap.
- `pe.conf` must include console password for first-time installation.
- Installer-required licensing material must be mounted and readable when required by the bundled installer.
- The running image must already contain one PE installer version.

### Persistence Inputs

- A configured persistence layer must be attached for PE configuration/certs, application state, and logs.
- Configured persistence targets must be writable by lifecycle scripts.

## Restart Scenarios (T032-T035)

### Scenario 1: Restart After Successful Installation

**Preconditions**:
- Container has completed successful bootstrap (lifecycle state = `installed`)
- All persistence volumes are accessible (`pe-config`, `pe-data`, `pe-logs`, `pe-state`)
- Same PE version image is used for restart

**Behavior - (T034: Restore)** :
- Checks lifecycle state = installed
- Validates version marker matches image version (T032)
- Restores PE from persisted volumes
- Skips installer re-execution
- Emits startup outcome: "Restoring from persisted state"
- Services start and healthcheck returns healthy

**Contract Guarantee**: ✅ Deterministic restart without reinstall

---

### Scenario 2: Restart Finds Persisted State but Version Mismatch

**Preconditions**:
- Container has successfully completed bootstrap with PE version X
- New container image is built with PE version Y (Y ≠ X)
- Restart is attempted using new image against volume from old version

**Behavior - (T032: Version Enforcement)**:
- Checks lifecycle state = installed
- **Validates version marker against image version**
- DETECTS: persisted_version ≠ image_version
- Transitions state to reset-required
- Exits with operator-action-required status

**Contract Guarantee**: ✅ Prevents silent version mismatches

---

### Scenario 3: Restart from Interrupted Installation State

**Preconditions**:
- Prior bootstrap attempt was interrupted
- Lifecycle marker remains in `installing` state
- Persistence volumes are partially populated

**Behavior - (T033: Block Auto-Retry)**:
- Checks lifecycle state = installing
- **DETECTS: interrupted state**
- **Automatic retry is NOT performed** (T033)
- Transitions state to reset-required
- Exits with operator-action-required status

**Contract Guarantee**: ✅ No cascading failures from interrupted installs

---

### Scenario 4: Restart After Failed Bootstrap

**Preconditions**:
- Bootstrap execution completed but hit error
- Lifecycle marker is in `failed` state
- Persistence volumes may contain partial data

**Behavior - (T033: No Auto-Retry)**:
- Checks lifecycle state = failed
- **Detects: prior failure**
- **Automatic retry is explicitly NOT performed** (T033)
- Exits with error status

**Contract Guarantee**: ✅ No silent repeating failures

---

### Scenario 5: Change pe.conf After Installation

**Preconditions**:
- Container has successfully completed bootstrap
- Operator modifies pe.conf on volume
- Container is restarted

**Behavior - (T035: Post-Install Drift Ignore)**:
- Checks lifecycle state = installed
- **Restores from persisted state (ignores pe.conf changes)** (T035)
- Emits startup outcome: "Restoring from persisted state"
- PE runs with original configuration, not new config

**Contract Guarantee**: ✅ Configuration consistency across restarts

---

## Supported Operator Actions

- ✅ Provide valid build artifact image produced from approved build process.
- ✅ Provide `pe.conf` and license material before first boot.
- ✅ Reuse same image version with same persistence layer for restart.
- ✅ Execute explicit reset flow after `failed`/`reset-required` states.

## Unsupported Operator Actions

- ❌ Treating image version change as in-place upgrade with existing persisted state.
- ❌ Expecting post-install `pe.conf` edits to trigger startup reconfiguration.
- ❌ Expecting automatic resume/retry after failed first install (including repeated agent runs) without explicit reset.

## Observable Outcomes (T036: Operator-Visible Messaging)

| Outcome | Meaning | Health Status | Operator Action |
|---------|---------|---------------|-----------------|
| `installing` | First install in progress | starting | Wait and monitor logs |
| `install-failed` | First install failed | unhealthy | Remediate and reset |
| `restored` | Existing install restored from persisted state | healthy | None |
| `intervention-required` | Startup blocked by invalid state/prereqs | unhealthy | Follow surfaced remediation |

## Node Continuity Signal (T036a)

When restart occurs in `installed` state, the startup outcome message includes:
- Last known check-in timestamp of previously connected nodes
- Count of connected nodes still in PE database
- Example: "Connected nodes continuity signal: 5 known nodes, last check-in at 2024-01-15T14:32:00Z"

This signal provides operators visibility into whether managed nodes remain accessible after restart.

## Container State Machine Diagram

```
  uninitialized ──(bootstrap with valid pe.conf)──> installing
       ▲                                                  │
       │                                     ┌──success──┴──failure──┐
       │                                     ▼                       ▼
       │                              installed (healthy)    failed (unhealthy)
       │                                    │                         │
       └─(explicit reset)─ reset-required ──┴─────────────────────────┘
                               ▲
                               │
                       version mismatch OR
                    interrupted/partial state
```

## Contract Test Targets

- ✅ First boot with valid inputs reaches `installing` then healthy (T023-T027).
- ✅ Restart with matching image version restores without reinstall (T034).
- ✅ Restart with mismatched image version is blocked and unhealthy (T032).
- ✅ Restart after failed bootstrap remains blocked until explicit reset (T033).
- ✅ Post-install `pe.conf` updates do not trigger reinstall (T035).
- ✅ Startup outcome messages clearly categorize state (T036).
- ✅ Connected node continuity signals visible on restart (T036a).
