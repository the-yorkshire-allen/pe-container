# Contract: Build Interface

## Purpose

Define the operator-facing build contract that produces a runnable PE container image.

## Required Build Inputs

- `PE_VERSION` (required): Puppet Enterprise version to embed in image metadata.
- `PE_INSTALLER_TAR_PATH` (required): local absolute file path to Puppet Enterprise installer tar.gz.

## Input Constraints

- `PE_INSTALLER_TAR_PATH` must be an absolute path.
- `PE_INSTALLER_TAR_PATH` must reference a readable local file available to Docker build workflow.
- Installer artifact must be a valid PE installer tar.gz for the requested workflow.
- Build must fail fast if required inputs are missing or invalid.

## Build-Time Installer Handling

- Build MUST extract installer tar.gz into a container-local staging location ready for first-time installation.
- Build MUST record enough metadata for runtime to validate installer/version compatibility.

## Build Invocation Shape (Logical)

```bash
docker build \
  --build-arg PE_VERSION=<version> \
  --build-arg PE_INSTALLER_TAR_PATH=<local-path> \
  -t pe-container:<version> \
  container/
```

This command shape is contractual guidance; implementation may wrap it in `make` while preserving the same required inputs and behavior.

## Build Outputs

- A version-identifiable OCI image tag.
- Embedded lifecycle scripts required for runtime behavior.
- Embedded installer payload staged and extracted for first-time installation corresponding to exactly one PE version.
- Build metadata sufficient for runtime version compatibility checks.

## Failure Contract

Build MUST fail with actionable messaging when:

- `PE_VERSION` is missing/invalid.
- `PE_INSTALLER_TAR_PATH` is missing/non-absolute/unreadable/not local.
- Installer artifact is malformed or unusable.
- Requested version does not match artifact identity checks.

## Runtime Post-Install Artifact Cleanup Contract

- After first-time installation completes and verification succeeds, runtime MUST remove installer archive and extracted installer payload from runtime filesystem.

## Non-Goals

- URL retrieval of installer artifact during build.
- Implicit multi-version build output from one invocation.
- Silent fallback to stale/cached installer artifact when required input is invalid.
