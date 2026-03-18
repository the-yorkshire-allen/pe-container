# Scope Boundaries: What This Container Manages (T041)

This document defines explicit in-scope and out-of-scope concerns for the PE container.
It exists to prevent over-engineering and keep operator expectations calibrated.

## IN SCOPE ✅

### PE Primary Server
- Building a versioned PE image from an operator-supplied installer tarball
- First-time PE installation (bootstrap) from `pe.conf`
- Restarting PE and restoring from persisted volumes without reinstalling
- Failure detection and operator-guided recovery (reset workflow)
- Version-locked persistence (image version = installed version)
- Health signaling via `/status/v1/simple` and Docker healthcheck

### Connected Agent Nodes
- Accepting Puppet agent connections on port 8140
- Signing and managing agent certificates via PE CA
- Running Puppet code against connected agents (classification, catalog, reports)
- Persisting node inventory and run reports in PE database across restarts
- Operator visibility into connected node continuity after restart

### Operator Tooling
- `Makefile` build targets with input validation
- Docker Compose profiles for PE primary and node-simulation topologies
- Lifecycle scripts: entrypoint, healthcheck, bootstrap, reset, validate-state
- Structured startup logging with outcome categories and remediation guidance

---

## OUT OF SCOPE ❌

### Infrastructure Below the Container
| Concern | Why Out of Scope |
|---------|-----------------|
| Agent node OS provisioning | Operator-managed; any Linux node that can install puppet-agent works |
| Network and DNS configuration | Operator infrastructure; PE needs resolvable hostnames only |
| TLS certificate authority (external) | PE has its own internal CA; external CA integration is PE configuration |
| Firewall rules and port exposure | Host/cloud networking concern, not container lifecycle |
| Docker/container runtime installation | Prerequisite; not managed by this project |

### PE Features and Topology
| Concern | Why Out of Scope |
|---------|-----------------|
| In-place PE version upgrades | Requires new image build; no upgrade-in-place path |
| HA / multi-primary PE | Single-primary only; HA is a separate PE topology concern |
| External PostgreSQL | Bundled PE database; external DB configuration not supported |
| PE load balancing / compile masters | Single node scope; compilers require separate architecture |
| PE Code Manager / GitOps | PE feature available once running; not a container responsibility |
| PE RBAC / SSO configuration | PE Console feature; configure post-bootstrap via PE UI |
| Puppet module development | Operators maintain code in external VCS |

### Operational Concerns
| Concern | Why Out of Scope |
|---------|-----------------|
| PE agent installation on remote nodes | Operator installs agent; container only hosts the primary |
| Backup and disaster recovery | Operator volumes; methodology documented but not automated here |
| Log shipping / SIEM integration | Operator connects log volumes to preferred tooling |
| Monitoring / alerting | Healthcheck endpoint exposed; alerting is operator-configured |
| PE license management | Operator mounts license file; container does not manage renewal |

---

## Design Decisions That Enforce These Boundaries

### Version-Locked Persistence
PE version is fixed at **build time**. The container cannot upgrade PE in-place. This keeps the container a single-purpose artifact (one PE version, one lifecycle). Upgrades require a new image build and data migration performed by the operator.

### No Auto-Retry
The container never automatically retries a failed bootstrap. This boundary ensures the operator reviews the failure before proceeding, preventing silent cascading failures.

### Build-First Model
The installer is baked into the image at build time, not fetched at runtime. This eliminates runtime network dependencies and ensures the image is a hermetic, auditable artifact.

### Connected Nodes: Visibility, Not Provision
The container makes connected node status *visible* at startup (continuity signal) but does not *provision* agent nodes. Agent nodes are external infrastructure managed by the operator.

---

## Validating Scope at Runtime

```bash
# Confirm PE primary is running (in-scope)
docker exec pe-primary /puppet/healthcheck.sh
echo "Exit: $?"  # 0 = healthy, 1 = unhealthy

# Confirm connected nodes still present after restart (in-scope)
docker exec pe-primary puppet cert list --all

# Confirm installer artifacts removed post-bootstrap (in-scope)
docker exec pe-primary ls /puppet/installer-staging/
# Expected: empty (cleaned up after bootstrap)
```
