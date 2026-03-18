# Feature Specification: Containerized Puppet Enterprise

**Feature Branch**: `001-containerize-pe`  
**Created**: 2026-03-18  
**Status**: Draft  
**Input**: User description: "create a containerised version of puppet enterprise. Managing pe.conf as the fundamental configuration tool of setting up the container. The initial launch of the container will install and configure PE and all its components. The design is for the container to only manage itself and any connected nodes. The container will provide persistance on key endpoints in order to survive a reboot e.g. /etc/puppetlabs, /opt/puppetlabs, /var/log/puppetlabs etc. The installation should only occur once and each docker image will be baked with a version of the PE installer"

## Clarifications

### Session 2026-03-18

- Q: How should the container behave if `pe.conf` changes after the initial installation has already completed? → A: Ignore post-install `pe.conf` changes during startup and continue using persisted state; any supported configuration drift is picked up through the normal Puppet agent workflow on the primary.
- Q: How should the container behave if the persisted volumes were created by a different Puppet Enterprise image version? → A: Normal startup must fail; persisted volumes are version-specific, and this design does not support in-place upgrades by changing the core container image version.
- Q: How should the container behave after a failed first installation leaves partial state behind? → A: Normal startup must fail and require an explicit operator reset or cleanup before another installation attempt.
- Q: What installer tar.gz input mode should the build process support? → A: Local absolute file path only.
- Q: How should the installer payload be handled through build and install lifecycle? → A: The build must extract the installer tar.gz into a container-local staging location ready for installation, and once installation is complete and verified the installer payload must be removed from the runtime filesystem.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Build a versioned PE image from operator-provided installer inputs (Priority: P1)

An operator runs a Docker build process that accepts a Puppet Enterprise version and a local absolute tar.gz installer file path, and produces a container image that is ready to execute the required first-boot and restart lifecycle behaviors.

**Why this priority**: The runtime lifecycle depends on having a valid, versioned image artifact; without a reliable build process, the deployment cannot be reproduced or operated safely.

**Independent Test**: Can be fully tested by invoking the documented build process with a valid installer version and local absolute tar.gz file path and verifying that the build completes, extracts installer content into the container staging location, and emits a runnable image tagged with the specified version.

**Acceptance Scenarios**:

1. **Given** a valid Puppet Enterprise version value and a reachable local absolute installer tar.gz file path, **When** the operator runs the build command, **Then** Docker produces an image artifact for that version, extracts the installer to a container-local staging location, and records build metadata needed by runtime lifecycle checks.
2. **Given** a missing, non-absolute, unreadable, or invalid local installer tar.gz file path, **When** the operator runs the build command, **Then** the build fails with actionable feedback and no ambiguous partially-built release artifact is presented as successful.

---

### User Story 2 - Bootstrap a PE container from configuration (Priority: P2)

An operator launches a new Puppet Enterprise container with a prepared `pe.conf` and the required persistent storage attached, and the container installs and configures Puppet Enterprise on first start without manual in-container steps.

**Why this priority**: The feature has no value unless a fresh container can reliably become a working Puppet Enterprise instance from the supplied configuration.

**Independent Test**: Can be fully tested by starting a new container against empty persistent storage with a valid `pe.conf` and verifying that Puppet Enterprise becomes operational after the initial startup sequence.

**Acceptance Scenarios**:

1. **Given** a new container image with no existing Puppet Enterprise runtime state and a valid `pe.conf`, **When** the container starts for the first time, **Then** it performs a one-time installation and configuration of Puppet Enterprise and transitions to an operational state.
2. **Given** a new container image with no existing Puppet Enterprise runtime state, **When** the operator starts the container without a valid `pe.conf` including console password, **Then** startup fails with clear guidance about the missing or invalid configuration and no partial install is presented as healthy.

---

### User Story 3 - Restart without reinstalling (Priority: P3)

An operator restarts the Puppet Enterprise container after a host reboot or container recreation, and the service resumes from persisted state without repeating the installation workflow.

**Why this priority**: Surviving restarts is the core operational requirement for running Puppet Enterprise in a container instead of treating every start as a fresh deployment.

**Independent Test**: Can be fully tested by completing one successful first launch, stopping the container, starting it again with the same persisted storage, and verifying that startup resumes normal service without another install pass.

**Acceptance Scenarios**:

1. **Given** a container that has already completed installation and has intact persisted state, **When** the container starts again, **Then** it skips the installation workflow and restores service using the existing state.
2. **Given** a container that has partially persisted or corrupted runtime state from a failed prior attempt, **When** the container starts or the agent is run repeatedly, **Then** it remains in an operator-action-required blocked state and does not retry installation until explicit reset or cleanup is performed.

---

### User Story 4 - Manage only the PE instance and connected nodes (Priority: P4)

An operator uses the containerized Puppet Enterprise instance as a self-contained management point for the container itself and nodes explicitly connected to it, without taking on broader external infrastructure responsibilities.

**Why this priority**: Clear scope prevents the containerized deployment from being treated as a general-purpose orchestration platform for unrelated infrastructure.

**Independent Test**: Can be fully tested by registering the container itself and one or more connected nodes, then confirming they remain manageable across restarts while no unsupported external control responsibilities are implied by the product.

**Acceptance Scenarios**:

1. **Given** a running Puppet Enterprise container and registered nodes, **When** the operator manages those nodes through the service, **Then** the deployment supports management of the container itself and the connected nodes.
2. **Given** an expectation that the containerized deployment should coordinate unrelated external Puppet Enterprise infrastructure, **When** the operator reviews the product behavior and guidance, **Then** the scope is clearly limited to the containerized instance and its connected nodes.

### Edge Cases

- Build input specifies a Puppet Enterprise version that does not match the provided tar.gz installer contents.
- Installer tar.gz file path is inaccessible during build due to permissions, path errors, missing local artifact, or use of a non-absolute path.
- Build command omits required installer version or installer location inputs.
- `pe.conf` is provided without console password for first-time installation.
- The container starts for the first time with persistent storage mounted but not writable.
- The supplied `pe.conf` conflicts with the bundled installer version or required installation inputs.
- A restart occurs after installation completed for some components but failed for others; startup must fail and require explicit operator reset or cleanup before retry.
- After failed initialization and repeated agent runs, installation retry remains blocked until explicit operator reset or cleanup.
- Existing persisted state was created by a different Puppet Enterprise image version than the one now being started; startup must fail and direct the operator to an explicit upgrade or reset path.
- The operator changes `pe.conf` after the initial installation; startup must continue from persisted state and must not treat the change as a reinstall trigger.
- Required configured persistence targets are missing on restart, causing only part of the prior state to be available.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001a**: The system MUST provide a documented Docker build process that requires operator-provided values for (a) Puppet Enterprise installer version and (b) local absolute installer tar.gz file path.
- **FR-001b**: The build process MUST validate that the local installer tar.gz file path is absolute, accessible, and usable before producing a release image artifact.
- **FR-001c**: The build process MUST produce a Docker image that is version-identifiable from the operator-provided installer version.
- **FR-001d**: For first-time installation, `pe.conf` MUST include the console password; startup MUST fail if this required value is missing or invalid.
- **FR-001e**: The build process MUST extract the installer tar.gz into a container-local staging location ready for installation.
- **FR-001**: The system MUST treat `pe.conf` as the authoritative operator-supplied configuration input for first-time setup of the containerized Puppet Enterprise instance.
- **FR-002**: Each built container image MUST correspond to exactly one bundled Puppet Enterprise installer version for the first-time installation flow.
- **FR-003**: On first launch against empty runtime state, the system MUST install and configure Puppet Enterprise and its required components automatically.
- **FR-003a**: Once installation is complete and verified, the installer tar.gz and extracted installer payload MUST be removed from the runtime filesystem.
- **FR-004**: The system MUST record that first-time installation has completed successfully and use that state to prevent automatic reinstallation on subsequent launches.
- **FR-005**: On subsequent launches with valid existing runtime state, the system MUST restore service from persisted state instead of repeating installation.
- **FR-005a**: After the initial installation has completed, changes to `pe.conf` MUST NOT trigger reinstall or block normal startup when valid persisted runtime state is present.
- **FR-006**: The system MUST preserve the Puppet Enterprise configuration, application data, and logs required to survive a container stop, restart, or host reboot via a persistent storage layer. (Example persistence targets: `/etc/puppetlabs` for configs/certs, `/opt/puppetlabs` for application data, `/var/log/puppetlabs` for logs; operators may configure alternative or additional persistence as needed.)
- **FR-007**: The system MUST validate the presence and integrity of the required persisted state during startup and surface a clear status when the state is missing, incomplete, corrupted, or incompatible with the image being launched.
- **FR-007a**: If the persisted runtime state was created by a different Puppet Enterprise image version than the running image, the system MUST fail normal startup and identify the version mismatch as requiring explicit operator intervention.
- **FR-008**: If first-time installation fails, the system MUST stop in a non-healthy state and provide actionable guidance about the failure without claiming the instance is ready.
- **FR-008a**: If first-time installation leaves partial runtime state behind, subsequent startups MUST NOT automatically retry or resume installation and MUST require an explicit operator-controlled reset or cleanup action before a new installation attempt.
- **FR-008b**: After a failed first-time installation, repeated agent runs (including running the agent twice) MUST NOT trigger installation retry; the process MUST remain halted until explicit operator reset or cleanup.
- **FR-009**: The system MUST support management of the containerized Puppet Enterprise instance itself and nodes that are explicitly connected to it.
- **FR-010**: The system MUST clearly bound its responsibility to the containerized instance and its connected nodes and MUST NOT imply automatic management of unrelated external infrastructure.
- **FR-011**: The system MUST retain enough persisted state for previously connected nodes to remain manageable after a normal restart.
- **FR-012**: The system MUST make the operator-visible startup outcome distinguishable as one of: first-time installation in progress, first-time installation failed, existing installation restored, or persisted state requires operator intervention.
- **FR-013**: The system MUST provide a deliberate operator-controlled path to reset the stored runtime state so a clean reinstall can be performed when desired.
- **FR-014**: The feature documentation MUST identify the required persistent storage locations, the one-time installation behavior, and the expectation that the image already contains the relevant Puppet Enterprise installer version.
- **FR-015**: The feature documentation MUST state that `pe.conf` is authoritative for first-time setup only, and that post-install configuration changes are expected to flow through the normal Puppet management workflow rather than a startup-time reinstall path.
- **FR-016**: The feature documentation MUST state that persisted volumes are tied to the Puppet Enterprise version they were created with and that replacing the core container image with a different version is not a supported in-place upgrade mechanism for this feature.
- **FR-017**: The produced image artifact from the build process MUST be capable of fulfilling the defined runtime lifecycle requirements in this specification (first-time bootstrap, restart behavior, failure-state signaling, and scoped node management).

### Key Entities *(include if feature involves data)*

- **Container Image Release**: A distributable Puppet Enterprise container image that bundles one specific installer version and defines the expected first-run behavior.
- **Build Input Set**: Operator-provided build parameters including Puppet Enterprise version and local absolute installer tar.gz file path used to produce a release image.
- **`pe.conf` Configuration**: The operator-provided configuration source used to define first-time installation and setup behavior for the containerized Puppet Enterprise instance.
- **PE Runtime State**: The persisted configuration, application data, certificates, and logs that allow the installed instance to resume after restart without repeating installation.
- **Persistent Storage Set**: The operator-provided storage locations that retain the required Puppet Enterprise state across container lifecycle events.
- **Connected Node**: A node explicitly registered to and managed by the containerized Puppet Enterprise instance.

### Assumptions

- The initial feature scope targets a single self-contained Puppet Enterprise deployment rather than clustered or multi-primary topologies.
- Operators provide a valid `pe.conf`, licensing material, and required persistent storage before the first successful startup.
- Image-to-image upgrades and migration of persisted state between different Puppet Enterprise versions are out of scope for the initial feature unless a later feature defines that workflow.
- Replacing the container image with a different Puppet Enterprise version while reusing the same persisted volumes is an unsupported operation and must be treated as a startup failure, not an upgrade path.
- Operators supply installer tar.gz input as a local absolute file path available to the Docker build process at build time.
- The feature covers persistence needed to survive restart and reboot, not backup, disaster recovery, or cross-region failover.
- Recovery from a failed first-time installation is limited to explicit operator reset or cleanup; automatic resume and in-place repair are out of scope for the initial feature.
- In-container validation is limited to service health checks via `/status/v1/simple`; deeper behavioral and performance verification requires external test harnesses.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001a**: In 100% of successful build validations with a valid installer version and local absolute tar.gz file path, the Docker build process emits a version-identifiable image artifact, stages extracted installer content ready for installation, and requires no manual image mutation.
- **SC-001b**: In at least 95% of invalid-build-input scenarios (missing version, non-absolute or unreadable local tar.gz file path, or unusable installer artifact), the build fails fast with actionable operator-facing error messaging.
- **SC-001c**: In 100% of successful first-time installation validations, installer payload artifacts are removed from the runtime filesystem after installation verification completes.
- **SC-001**: In at least 90% of first-boot smoke runs using a valid `pe.conf` and prepared persistent storage, all required PE services expose healthy `/status/v1/simple` responses within 45 minutes.
- **SC-002**: In 100% of tested normal restart smoke scenarios with intact persisted state, required services return healthy `/status/v1/simple` responses without triggering a second installation workflow.
- **SC-003**: In at least 95% of startup failure smoke scenarios caused by invalid configuration or invalid persisted state, startup ends in a non-healthy state and exposes operator-action-required messaging without healthy `/status/v1/simple` responses.
- **SC-004**: In 100% of reboot and restart smoke validations, persisted configuration, application data, and logs remain available and corresponding service health checks recover to healthy `/status/v1/simple` responses.
- **SC-005**: Node-manageability continuity metrics (for example agent check-in and post-restart management operations) are captured through an external validation harness and reported alongside in-container `/status/v1/simple` smoke results.
