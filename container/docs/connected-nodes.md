# Connected Nodes Management Runbook

## Overview

This runbook demonstrates how the PE container manages connected agent nodes. The containerized PE acts as the Puppet primary server, with agent nodes connecting and running Puppet code orchestrated from the container.

## Scope: What This Container Manages

### IN SCOPE ✅

- **The PE Container/Primary**: Building, bootstrapping, restarting, and persisting PE primary server
- **Connected Agent Nodes**: Nodes that connect to PE for agent runs
- **Node Classification**: Using PE console to classify nodes and assign configurations
- **Agent Runs**: Triggering and managing Puppet agent execution on connected nodes
- **Certificate Management**: Handling agent certificates and PE certificate authority
- **Reporting**: Viewing run reports and node inventory from PE console

### OUT OF SCOPE ❌

- Agent node operating systems or infrastructure (assumes pre-built agent nodes)
- Installation of PE agents on remote systems (operator responsibility)
- Puppet code development (use external VCS and Puppet modules)
- PE upgrades or multi-version deployments
- Infrastructure outside the container (network, DNS, firewalls)
- PE components outside the container (external databases, load balancers)

## Prerequisites

### PE Container
- Built and bootstrapped successfully (see FIRST-BOOT-RUNBOOK.md)
- Healthy and accepting connections on port 8140 (default Puppet agent port)
- Console accessible on port 8143

### Agent Nodes
- Linux systems with network connectivity to PE container
- Internet or network access to install Puppet Agent
- Valid hostname or FQDN resolvable from PE container

## Architecture: PE Primary + Connected Nodes

```
┌─────────────────────────────────────────┐
│         PE Container (Primary)          │
│         ┌──────────────────────┐        │
│         │  PE Console (8143)   │        │
│         │  Puppet Agent (8140) │        │
│         │  PostgreSQL Database │        │
│         │  Bolt/Orchestration  │        │
│         └──────────────────────┘        │
└─────────────────────────────────────────┘
        ▲                  ▲                ▲
        │                  │                │
   [agent run]         [agent run]      [agent run]
        │                  │                │
    ┌───────────┐      ┌────────────┐   ┌──────────┐
    │  Node A   │      │   Node B   │   │  Node C  │
    │(Linux VM) │      │(Linux Box) │   │(Cloud)   │
    └───────────┘      └────────────┘   └──────────┘
```

## First-Time Node Onboarding

### Step 1: Prepare Agent Node

On the agent node (or use automation to prepare):

```bash
# 1a. On the agent node, install Puppet Agent
# (exact steps depend on OS - see https://puppet.com/docs/puppet/latest/install_agents.html)

# Linux example:
wget https://apt.puppet.com/puppet8-release-$(lsb_release -cs).deb
dpkg -i puppet8-release-$(lsb_release -cs).deb
apt-get update
apt-get install -y puppet-agent

# 1b. Configure PE server address
cat > /etc/puppetlabs/puppet/puppet.conf << 'EOF'
[main]
certname = agent-node-1.example.com
server = pe-primary.example.com  # Must resolve to PE container
environment = production

[agent]
runinterval = 30m
EOF
```

### Step 2: Generate Agent Certificate

From PE container:

```bash
# Option A: Let agent auto-request certificate during first run
docker exec pe-primary puppet cert list  # Wait for pending requests
# Output: "agent-node-1.example.com" (unapproved)

# Option B: Pre-generate certificate
docker exec pe-primary puppet cert generate agent-node-1.example.com
```

### Step 3: Approve Agent Certificate

From PE container:

```bash
# View pending certificates
docker exec pe-primary puppet cert list

# Approve specific agent
docker exec pe-primary puppet cert sign agent-node-1.example.com

# Verify approved
docker exec pe-primary puppet cert list --all  # Should now show agent-node-1
```

### Step 4: Run Agent on Node

On agent node:

```bash
# First agent run (certificate exchange)
puppet agent -t  # Test run (one-time, verbose)

# Or trigger from PE console:
# Login to PE console → Agent jobs → Run PxP job
```

### Step 5: Verify Node in PE Console

1. Open PE Console: `https://<container-host>:8143`
2. Navigate to: **Infrastructure > Nodes**
3. Verify agent node appears in list
4. Check last run status: **Last report**

## Connected Nodes Continuity After Restart

### Continuity Guarantee

After PE container restart, connected nodes remain associated:

```
Node A ──┐                                   
         │  (agent certs, inventory data)   
Node B ──┼──→ [PE persisted volumes]
         │    - /etc/puppetlabs (certs)
Node C ──┘    - /opt/puppetlabs (database)
              - /var/log/puppetlabs (logs)
```

**Result**: Container restart does NOT remove node associations or require re-onboarding

### Verifying Continuity After Restart

```bash
# 1. Restart container
docker restart pe-primary
sleep 30  # Wait for PE to stabilize

# 2. Verify agents remain in PE
docker exec pe-primary puppet cert list --all | grep "agent-node-1"
# Expected: Agent still listed and approved

# 3. Trigger agent run from console
# PE console → Infrastructure > Nodes → "Run PxP job"
# Expected: Nodes respond and complete run

# 4. Verify run reports exist
docker exec pe-primary puppet node status agent-node-1
# Expected: Shows recent run reports from before AND after restart
```

## Managed Agent Operations

### View Node Inventory

```bash
# Via PE container CLI
docker exec pe-primary puppet query 'nodes { }' --format json

# Via PE Console
# Infrastructure → Nodes → (view all nodes with status)
```

### Trigger Agent Runs

```bash
# From PE Console (recommended):
# Infrastructure → Nodes → Select node(s) → Run PxP job

# From container CLI:
docker exec pe-primary /opt/puppetlabs/bin/bolt task run puppet_agent::run \
  --targets pcp://agent-node-1.example.com
```

### View Configuration Management

```bash
# Puppet code location (inside container)
docker exec pe-primary ls -la /etc/puppetlabs/code/environments/production

# Add modules
docker exec pe-primary puppet module install puppetlabs-apt

# Apply manifests
docker exec pe-primary puppet apply -e 'include apache'
```

### View Run Reports

```bash
# From PE Console:
# Infrastructure → Nodes → Select node → Reports

# From CLI:
docker exec pe-primary puppet node status agent-node-1
# Or access PostgreSQL database for detailed metrics
```

## Continuity Evidence Capture

To verify node continuity works after restart, capture and compare this data:

### Pre-Restart Evidence

```bash
# Capture current node state
docker exec pe-primary puppet query 'nodes[certname] { }' \
  --format json > /tmp/nodes-before.json

# Capture run reports
docker exec pe-primary curl -k https://localhost:8081/pdb/query/v4/reports \
  --header "X-Authentication: $(cat /etc/puppetlabs/puppet/puppetdb-access.key)" \
  > /tmp/reports-before.json  # (pseudocode; actual endpoint varies)

# Sample known agents
for node in agent-node-1 agent-node-2; do
  docker exec pe-primary puppet cert list --all | grep "$node" > /tmp/cert-$node-before.txt
done
```

### Perform Restart

```bash
docker restart pe-primary
sleep 30  # Wait for services to stabilize
```

### Post-Restart Verification

```bash
# Verify same nodes still present
docker exec pe-primary puppet query 'nodes[certname] { }' \
  --format json > /tmp/nodes-after.json

# Validate node list unchanged
diff /tmp/nodes-before.json /tmp/nodes-after.json
# Expected: No differences (same node list)

# Verify certificates still valid
for node in agent-node-1 agent-node-2; do
  docker exec pe-primary puppet cert list --all | grep "$node" > /tmp/cert-$node-after.txt
  diff /tmp/cert-$node-before.txt /tmp/cert-$node-after.txt
  # Expected: Same certification status
done

# Trigger post-restart agent runs
docker exec pe-primary /opt/puppetlabs/bin/bolt task run puppet_agent::run \
  --targets pcp://agent-node-1.example.com 

# Verify new reports appear (proving connectivity)
sleep 5
docker exec pe-primary puppet node status agent-node-1 | grep "Report time"
# Expected: New report timestamp after restart
```

## Operations Runbook

### Add a New Agent Node

```bash
# 1. On agent machine: install agent
puppet resource package puppet-agent ensure=present

# 2. Set server address and reboot to apply
puppet config set server pe-primary.example.com
puppet agent -t

# 3. In PE container: approve certificate  
docker exec pe-primary puppet cert sign agent-node-1.example.com

# 4. Verify in PE Console
# Navigate to Infrastructure → Nodes
```

### Remove an Agent Node

```bash
# 1. In PE container: revoke certificate
docker exec pe-primary puppet cert disable agent-node-1.example.com

# 2. Clean up node data (optional)
docker exec pe-primary puppet api create-secret --service=puppetdb \
  --create='{"type":"api_key"}'  # Pseudocode

# 3. Remove from console classification (if desired)
# PE Console → Node Groups → Remove node from groups
```

### Ensure Connected Nodes Receive Updates

```bash
# 1. Deploy Puppet code
docker exec pe-primary git -C /etc/puppetlabs/code/environments/production pull

# 2. Trigger agent runs on all nodes
docker exec pe-primary /opt/puppetlabs/bin/bolt task run puppet_agent::run \
  --targets pcp://\*  # All connected nodes

# 3. Monitor run results
docker exec pe-primary puppet task run puppet_agent::run \
  --targets pcp://\* --wait-for-complete 300  # Wait up to 5 min
```

## Boundaries: What Requires Extra Tooling

The PE container provides the **primary server only**. These are out-of-scope and require external tooling:

| Operation | Scope | Tooling |
|-----------|-------|---------|
| Build agent nodes | OUT | Terraform, Vagrant, cloud APIs |
| Install PE agent | OUT | Configuration management, shell scripts |
| Manage PE code repository | OUT | Git, GitOps, external VCS |
| Backup PE database | IN (methodology) | `puppet db export`, Docker volume snapshots |
| Monitor PE services | IN (basic logging) | Prometheus, Grafana, ELK stack |
| Scale PE across regions | OUT | Load balancing, multi-primary setup |
| PE to PE replication | OUT | Requires multiple PE primary containers |

## Troubleshooting Connected Nodes

### Agent Node Cannot Connect

```bash
# 1. Verify network connectivity
agent-node$ ping pe-primary.example.com
agent-node$ puppet agent -t --trace

# 2. Check PE logs for certificate issues
docker logs pe-primary | grep "certificate"

# 3. Verify agent certificate not revoked
docker exec pe-primary puppet cert list agent-node-1  # Should be signed, not revoked
```

### Node Disappears After PE Restart

```bash
# This should NOT happen; if it does, check:

# 1. Persistence volumes exist
docker volume ls | grep pe-

# 2. State is "installed" not "reset-required"
docker exec pe-primary cat /puppet/state/.installed 2>/dev/null && echo "OK" || echo "PROBLEM"

# 3. Database is intact
docker exec pe-primary psql -U pe-postgres << 'EOF'
SELECT COUNT(*) FROM certnames;  -- Should show your agent count
EOF
```

### Agent Runs Slow or Timeout

```bash
# Typical reasons:
# 1. Resource constraints on container
docker stats pe-primary  # Check CPU, memory

# 2. Large catalog compilation
docker exec pe-primary puppet config print environment
# Check Puppetfile for heavy modules

# Mitigation:
# - Allocate more resources to container
# - Optimize Puppet code
# - Use role-based classification to reduce catalog size
```

## Exporting Connected Node Evidence for External Validation

To hand off node continuity validation to external testing:

```bash
# Export node list and certificates
mkdir -p /tmp/validation-export
docker exec pe-primary puppet query 'nodes[certname,report_timestamp] { }' \
  --format json > /tmp/validation-export/nodes.json

# Export certicate list
docker exec pe-primary puppet cert list --all \
  > /tmp/validation-export/certificates.list

# Export recent reports
docker exec pe-primary curl -sk https://localhost:8081/pdb/query/v4/reports \
  > /tmp/validation-export/reports.json 2>/dev/null || echo "PuppetDB query requires auth"

# Archive for handoff
tar czf ~/pe-node-validation-export.tar.gz /tmp/validation-export/
# Send to external validation team
```

See [external-validation.md](./external-validation.md) for validation handoff template.

## Summary

✅ **In-Scope Managed**: PE primary, connected agents, agent runs, node classification, reporting  
❌ **Out-of-Scope**: Agent node infrastructure, PE code development, external systems  
✅ **Continuity Guaranteed**: Nodes remain allocated and operational after PE restart  
✅ **Operations Supported**: Add/remove nodes, trigger runs, view results
