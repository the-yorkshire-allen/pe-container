
# Project Constitution: Puppet Enterprise in a Container (Self‑Managed Master)

- **Constitution Version:** 1.0.0  
- **Ratified:** 2026-03-18  
- **Last Amended:** 2026-03-18  
- **Status:** Validation phase

> **Authoritative intent** — This constitution encodes *non‑negotiable* principles for a
> architecture that runs **Puppet Enterprise (PE)** inside a container as a
> self‑contained appliance. It is designed for use with **GitHub Spec Kit** where
> the constitution is read by `/speckit.*` commands as the governing constraints
> for all specs, plans, tasks, and implementation. Place this file at
> `.specify/memory/constitution.md` in a Spec Kit repo.  
> Reference: Spec Kit constitution workflow and file locations (command template,
> deep dive, and overview). citeturn3search8turn3search7turn3search10

---

## 1. Scope & Support Boundaries

1. **This PE instance manages only itself and registered external agents.** It
   **MUST NOT** manage the underlying Docker host (no host classification).
2. **Design intent vs. vendor support** — where this constitution constrains
   behavior, these are
   *project decisions* to make the system stable; they do not imply vendor
   support.

## 2. Architecture & Runtime

1. **Container base:** Use a Linux base image that supports all required PE
   services and lifecycle scripts. The implementation may use systemd-oriented
   patterns where needed, but systemd, privileged mode, and explicit cgroup
   mount requirements are not mandatory constitutional constraints.
2. **Monolithic PE install** inside the container.
3. **Networking:** Expose PE services on standard ports. Use TLS by default.
4. **Data & state persistence:** PE state must survive container restarts and
   migrations to other hosts via a persistence layer (e.g., named volumes,
   external storage). Operators are responsible for configuring and managing
   the persistence mechanism. (Project decision.)

## 3. Security Posture

1. **Do not manage the Docker host.** No classes or groups target the host’s
   certname.
2. **Minimal surface:** Do not bind‑mount the Docker daemon socket.
3. **State integrity:** Preserve PE state across restarts and migrations.
   Back up the persistence layer before major operations.
4. **RBAC & users:** Use PE RBAC for console access; avoid default passwords.


## 4. Governance for Host Independence

1. **Hard rule:** The PE container **MUST NOT** enforce configuration on the
   Docker host. This is enforced by classification policy — do not add the host’s
   node to groups with manifest enforcement.
2. **Self‑management scope:** It is acceptable to classify the master container’s
   own certname **only** for internal PE tuning (e.g., `puppet_enterprise` class
   params) that do not alter the underlying host.

## 5. Agent Onboarding & Classification

1. **External agents connect to the PE instance.** (Project decision.)
2. **Node groups:** Define groups for lab roles (e.g., `linux_web`, `windows_core`).
3. **Containerized nodes:** If managing other containers, prefer the
   `puppetlabs/docker` module for Docker orchestration from PE. The module is
   actively maintained and compatible with PE 2023.x–2025.x. citeturn1search1

## 6. Observability & Logs

1. **Logs are retained** in the PE persistence layer and MAY be tailed
   to container stdout/stderr for aggregation. (Project decision.)
2. **PuppetDB enabled** with reports and storeconfigs routed accordingly. The
   (deprecated) `puppetserver` image demonstrates the typical `PUPPETDB_*`
   wiring used by containerized masters. citeturn1search5
3. **Structured logging** (JSON) is preferred for any auxiliary services.

## 7. Upgrades & Lifecycle

1. **Version pinning:** Do not perform in‑place rolling upgrades without a tested
   backup. Snapshot all PE volumes before upgrading. (Project decision.)
2. **Rebuild over mutate:** Prefer re‑building the image with a newer PE
   installer and reusing persistent volumes over ad‑hoc in‑container changes.
3. **CA continuity:** Preserve the CA volume; re‑issuing the CA breaks trust for
   all registered agents.

## 8. Performance & Sizing

1. **JRuby pool:** Size CPU/memory for `puppetserver` JVM heuristics; pin CPUs if
   noisy neighbors are present. (Project decision.)
2. **PostgreSQL IOPS:** Ensure the data volume provides adequate I/O for PE’s
   PostgreSQL (catalog, reports, RBAC).

## 9. Compliance Gates for Specs/Plans/Tasks

Any `/speckit.specify`, `/speckit.plan`, `/speckit.tasks`, or `/speckit.implement`
artifacts **MUST** pass these checks:

- **Host Independence:** No tasks or manifests may target the Docker host.
- **Persistence:** PE state must survive container restarts and migrations to
  other hosts via the persistence layer. No plan may discard or re‑initialize
  state without explicit operator action.
- **Observability:** All changes that affect PuppetDB, reports, or logging must
  preserve existing data retention.

## 10. Governance & Versioning of This Constitution

1. **Amendments:** Proposed via PR, requiring review by the repo maintainers.
2. **Versioning:** Semantic versioning:
   - **MAJOR:** breaking governance changes or removal/redefinition of a
     principle.
   - **MINOR:** new principle/section or materially expanded guidance.
   - **PATCH:** clarifications or non‑semantic edits.  
   (Versioning policy aligns with Spec Kit command template guidance.) citeturn3search8
3. **Dates:** `Ratified` is the original adoption date; `Last Amended` updates on
   every accepted change. (Per Spec Kit command guidance.) citeturn3search8

## 11. References

- **Spec Kit – templates & constitution command** (file locations, semantics,
  and workflow). citeturn3search8
- **Spec Kit – constitution phase overview** (why the constitution governs all
  subsequent steps). citeturn3search10
- **OSS Puppet Server Docker image (deprecated)** — shows containerization
  patterns, certificate identity variables, and Pupperware reference; confirms
  lack of a PE container image and deprecation of the legacy server image.
  citeturn1search5
- **Puppet Docker module** — supported module for managing container ecosystems
  from Puppet/PE. citeturn1search1

---

### Appendix A — Example Runtime Notes (Non‑binding)

- Example Docker run flags:
   - Runtime privileges and cgroup mounts are deployment-dependent and optional.
  - Persistence layer: Operator-managed named volumes or external storage.

(These are implementation hints; the *Principles* above are the enforceable
rules.)
