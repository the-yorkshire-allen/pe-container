# Data Model: Containerized Puppet Enterprise Build and Runtime

## Entity: BuildInputSet

- **Purpose**: Captures operator-provided build parameters required to produce a PE image artifact.
- **Fields**:
  - `peVersion`: requested Puppet Enterprise version (string, required)
  - `installerTarPath`: local absolute filesystem path to installer tar.gz (string, required)
  - `buildContextPath`: Docker build context root path (string, required)
  - `validationStatus`: `pending`, `valid`, `invalid`
  - `validationMessage`: operator-facing reason when invalid
- **Validation Rules**:
  - `peVersion` must be non-empty and version-formatted per project build rules.
  - `installerTarPath` must be absolute and resolve to a readable local file at build time.
  - `installerTarPath` must refer to a `.tar.gz` artifact compatible with PE installer expectations.

## Entity: InstallerStaging

- **Purpose**: Represents installer payload state inside container image/runtime lifecycle.
- **Fields**:
  - `stagingPath`: container-local extraction location
  - `archivePresent`: boolean indicating tar.gz presence
  - `extractedPresent`: boolean indicating extracted payload presence
  - `cleanupStatus`: `pending`, `completed`, `failed`
- **Validation Rules**:
  - Before first install: extracted payload must be present in staging path.
  - After successful install verification: archive and extracted payload must be removed from runtime filesystem.

## Entity: ContainerImageRelease

- **Purpose**: Represents the built OCI image containing one PE installer version and lifecycle scripts.
- **Fields**:
  - `imageTag`: operator-visible image tag
  - `peVersion`: bundled PE version
  - `buildId`: trace identifier for build run
  - `createdAt`: build timestamp
  - `installerDigest`: digest/fingerprint of bundled installer artifact
- **Relationships**:
  - Produced from one `BuildInputSet`
  - Used by one or more `RuntimeInstance` objects

## Entity: BootstrapConfig

- **Purpose**: Represents first-boot runtime configuration mounted by operator.
- **Fields**:
  - `peConfPath`: mounted location of `pe.conf`
  - `consolePasswordPresent`: boolean
  - `licensePath`: mounted location of licensing material (if required)
  - `validationStatus`: `valid`, `missing`, `invalid`
- **Relationships**:
  - Consumed by `RuntimeInstance` only during first successful bootstrap flow
- **Validation Rules**:
  - `consolePasswordPresent` must be true for first-time installation.

## Entity: PersistentStorageSet

- **Purpose**: Represents the operator-managed persistence layer used to survive restart and host migration.
- **Fields**:
  - `configPath`: configured persistence target for PE config/certs
  - `dataPath`: configured persistence target for application state
  - `logPath`: configured persistence target for logs
  - `writableStatus`: `valid`, `invalid`
- **Validation Rules**:
  - Required configured persistence targets must be present and writable.

## Entity: RuntimeState

- **Purpose**: Captures persisted lifecycle and compatibility state for startup decisions.
- **Fields**:
  - `lifecycleState`: `uninitialized`, `installing`, `installed`, `failed`, `reset-required`
  - `versionMarker`: PE version associated with persisted state
  - `retryBlocked`: boolean indicating install retry is disabled until explicit reset
  - `lastErrorCode`: categorized startup/bootstrap failure code
  - `lastErrorMessage`: operator-facing failure explanation
  - `updatedAt`: timestamp of latest state transition
- **Relationships**:
  - Belongs to one `PersistentStorageSet`
  - Evaluated by one `RuntimeInstance` on each start

## Entity: RuntimeInstance

- **Purpose**: Represents a running/starting container process.
- **Fields**:
  - `containerId`: runtime ID
  - `startupMode`: `first-boot`, `restart`, `blocked`
  - `agentRunCountSinceFailure`: integer counter for post-failure agent runs
  - `healthState`: `starting`, `ready`, `not-healthy`, `operator-action-required`
  - `statusEndpoint`: `/status/v1/simple`
- **Relationships**:
  - Uses one `ContainerImageRelease`
  - Reads one `BootstrapConfig`
  - Attaches one `PersistentStorageSet`
  - Produces one `StartupOutcome`

## Entity: StartupOutcome

- **Purpose**: Operator-visible outcome for a startup attempt.
- **Fields**:
  - `outcomeType`: `installing`, `install-failed`, `restored`, `intervention-required`
  - `message`: summarized status
  - `recommendedAction`: `fix-build-input`, `fix-config`, `fix-persistence`, `reset-state`, `use-matching-image`, `none`

## Entity: ConnectedNode

- **Purpose**: Node explicitly registered to this PE primary.
- **Fields**:
  - `certname`: node identifier
  - `registrationStatus`: `pending`, `active`, `revoked`
  - `lastCheckInAt`: timestamp
  - `managedByPrimary`: boolean

## State Transitions

```text
BuildInputSet.pending -> BuildInputSet.valid -> ContainerImageRelease.created
BuildInputSet.pending -> BuildInputSet.invalid

RuntimeState.uninitialized -> RuntimeState.installing -> RuntimeState.installed
RuntimeState.installing -> RuntimeState.failed
RuntimeState.failed -> RuntimeState.reset-required
RuntimeState.reset-required -> RuntimeState.uninitialized
RuntimeState.installed -> RuntimeState.installed (normal restart)
RuntimeState.installed -> StartupOutcome.intervention-required (mismatch/missing/corrupt state)
RuntimeState.failed + repeated agent runs -> RuntimeState.reset-required (remains blocked until explicit reset)
```
