# External Validation Handoff: Node Continuity Metrics (T044)

## Purpose

This template defines the artifacts and evidence an external validation team needs to verify that connected Puppet agent nodes survive a PE container restart without re-onboarding.

## Validation Objective

Confirm that after a PE container restart:
1. All previously connected nodes remain in PE inventory
2. Agent certificates are intact and valid
3. Agents can re-connect and complete a Puppet run
4. Run history (reports) is preserved

---

## Pre-Restart Data Collection

The operator or CI pipeline captures these artifacts **before** restarting the container.

### Required Artifacts

```bash
EVIDENCE_DIR="/tmp/pe-continuity-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${EVIDENCE_DIR}"

# 1. Node inventory snapshot
docker exec pe-primary \
  /opt/puppetlabs/bin/puppet query 'nodes[certname,report_timestamp,latest_report_status] {}' \
  --format json > "${EVIDENCE_DIR}/nodes-before.json"

# 2. Certificate list
docker exec pe-primary \
  /opt/puppetlabs/bin/puppet cert list --all \
  > "${EVIDENCE_DIR}/certs-before.txt"

# 3. Lifecycle marker state
docker exec pe-primary cat /puppet/state/.installed \
  > "${EVIDENCE_DIR}/lifecycle-marker-before.txt" 2>/dev/null || echo "missing" >> "${EVIDENCE_DIR}/lifecycle-marker-before.txt"

# 4. Version metadata
docker exec pe-primary cat /puppet/state/.pe-version \
  > "${EVIDENCE_DIR}/pe-version-before.txt" 2>/dev/null
docker exec pe-primary cat /puppet/state/.image-version \
  > "${EVIDENCE_DIR}/image-version-before.txt" 2>/dev/null

# 5. Container health snapshot
docker inspect pe-primary --format '{{json .State.Health}}' \
  > "${EVIDENCE_DIR}/health-before.json"

echo "Pre-restart evidence captured: ${EVIDENCE_DIR}"
```

---

## Restart Procedure

```bash
# Stop container cleanly
docker stop pe-primary
sleep 5

# Start container
docker start pe-primary

# Wait for healthy (timeout 3 min)
HEALTHY=false
for i in {1..36}; do
  if docker exec pe-primary /puppet/healthcheck.sh 2>/dev/null; then
    echo "PE healthy at attempt ${i} ($(date -u +%H:%M:%S))"
    HEALTHY=true
    break
  fi
  sleep 5
done

if [ "$HEALTHY" != "true" ]; then
  echo "ERROR: PE did not become healthy within timeout"
  docker logs pe-primary | tail -30
  exit 1
fi

echo "Restart complete at: $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  >> "${EVIDENCE_DIR}/restart-log.txt"
```

---

## Post-Restart Data Collection

```bash
# 1. Node inventory post-restart
docker exec pe-primary \
  /opt/puppetlabs/bin/puppet query 'nodes[certname,report_timestamp,latest_report_status] {}' \
  --format json > "${EVIDENCE_DIR}/nodes-after.json"

# 2. Certificate list post-restart
docker exec pe-primary \
  /opt/puppetlabs/bin/puppet cert list --all \
  > "${EVIDENCE_DIR}/certs-after.txt"

# 3. Lifecycle marker state post-restart
docker exec pe-primary cat /puppet/state/.installed \
  > "${EVIDENCE_DIR}/lifecycle-marker-after.txt" 2>/dev/null || echo "missing"

# 4. Version metadata post-restart
docker exec pe-primary cat /puppet/state/.pe-version \
  > "${EVIDENCE_DIR}/pe-version-after.txt" 2>/dev/null

# 5. Container health post-restart
docker inspect pe-primary --format '{{json .State.Health}}' \
  > "${EVIDENCE_DIR}/health-after.json"
```

---

## Validation Checks

The external validation team runs these assertions against collected artifacts.

### Check 1: Node Count Unchanged

```bash
BEFORE=$(jq 'length' "${EVIDENCE_DIR}/nodes-before.json")
AFTER=$(jq 'length' "${EVIDENCE_DIR}/nodes-after.json")

if [ "$BEFORE" -eq "$AFTER" ]; then
  echo "PASS: Node count unchanged (${BEFORE} nodes)"
else
  echo "FAIL: Node count changed: before=${BEFORE} after=${AFTER}"
fi
```

### Check 2: No Nodes Lost

```bash
# Every node present before restart must still be present after
MISSING=$(jq -r '.[].certname' "${EVIDENCE_DIR}/nodes-before.json" | sort > /tmp/before-names.txt && \
          jq -r '.[].certname' "${EVIDENCE_DIR}/nodes-after.json"  | sort > /tmp/after-names.txt && \
          comm -23 /tmp/before-names.txt /tmp/after-names.txt)

if [ -z "$MISSING" ]; then
  echo "PASS: All pre-restart nodes present after restart"
else
  echo "FAIL: Nodes missing after restart:"
  echo "$MISSING"
fi
```

### Check 3: Certificates Unchanged

```bash
if diff "${EVIDENCE_DIR}/certs-before.txt" "${EVIDENCE_DIR}/certs-after.txt" > /dev/null; then
  echo "PASS: Certificate list identical before and after restart"
else
  echo "FAIL: Certificate list changed:"
  diff "${EVIDENCE_DIR}/certs-before.txt" "${EVIDENCE_DIR}/certs-after.txt"
fi
```

### Check 4: Lifecycle Marker Still `installed`

```bash
if [ -f "${EVIDENCE_DIR}/lifecycle-marker-after.txt" ] && \
   [ "$(cat "${EVIDENCE_DIR}/lifecycle-marker-after.txt")" != "missing" ]; then
  echo "PASS: .installed marker present after restart"
else
  echo "FAIL: .installed marker missing after restart — state regression"
fi
```

### Check 5: PE Version Unchanged

```bash
V_BEFORE=$(cat "${EVIDENCE_DIR}/pe-version-before.txt" 2>/dev/null)
V_AFTER=$(cat "${EVIDENCE_DIR}/pe-version-after.txt" 2>/dev/null)

if [ "$V_BEFORE" = "$V_AFTER" ]; then
  echo "PASS: PE version unchanged (${V_BEFORE})"
else
  echo "FAIL: PE version changed: before=${V_BEFORE} after=${V_AFTER}"
fi
```

### Check 6: Agent Reconnects and Runs Successfully

```bash
# Run from one agent node (or via Bolt from PE container)
# Replace AGENT_CERTNAME with actual certname
AGENT_CERTNAME="agent-1.example.local"

docker exec pe-primary \
  /opt/puppetlabs/bin/bolt task run puppet_agent::run \
  --targets "pcp://${AGENT_CERTNAME}" \
  --timeout 120

# Verify new report appeared (timestamp after restart)
RESTART_TS=$(cat "${EVIDENCE_DIR}/restart-log.txt" | grep -o '[0-9T:Z-]*' | tail -1)
REPORT_TS=$(docker exec pe-primary \
  /opt/puppetlabs/bin/puppet query \
  "reports[receive_time]{ certname='${AGENT_CERTNAME}'} order by receive_time desc limit 1" \
  --format json | jq -r '.[0].receive_time')

echo "Restart time:     ${RESTART_TS}"
echo "Latest report:    ${REPORT_TS}"

if [[ "$REPORT_TS" > "$RESTART_TS" ]]; then
  echo "PASS: Agent produced a new run report after restart"
else
  echo "WARN: No post-restart run report found yet (may need to wait for run interval)"
fi
```

---

## Evidence Package Format

Archive all collected artifacts for handoff:

```bash
tar czf "pe-continuity-evidence-$(date +%Y%m%d).tar.gz" "${EVIDENCE_DIR}/"

# Contents:
# ├── nodes-before.json          Node inventory pre-restart
# ├── nodes-after.json           Node inventory post-restart
# ├── certs-before.txt           Certificate list pre-restart
# ├── certs-after.txt            Certificate list post-restart
# ├── lifecycle-marker-before.txt  .installed marker pre-restart
# ├── lifecycle-marker-after.txt   .installed marker post-restart
# ├── pe-version-before.txt      PE version pre-restart
# ├── pe-version-after.txt       PE version post-restart
# ├── health-before.json         Docker health status pre-restart
# ├── health-after.json          Docker health status post-restart
# └── restart-log.txt            Restart timestamps
```

---

## Pass Criteria

All six checks must pass for continuity to be verified:

| Check | Metric | Pass Condition |
|-------|--------|----------------|
| 1 | Node count | Before == After |
| 2 | No nodes lost | All pre-restart certnames present post-restart |
| 3 | Certificates | Cert list identical (diff empty) |
| 4 | Lifecycle marker | `.installed` marker present |
| 5 | PE version | Version string unchanged |
| 6 | Agent runs | At least one agent produces post-restart run report |

**Overall**: PASS only when all 6 checks pass.
