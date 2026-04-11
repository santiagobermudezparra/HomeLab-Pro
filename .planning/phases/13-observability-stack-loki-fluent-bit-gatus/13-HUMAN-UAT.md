---
status: partial
phase: 13-observability-stack-loki-fluent-bit-gatus
source: [13-VERIFICATION.md]
started: 2026-04-11T07:45:00Z
updated: 2026-04-11T07:45:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. FluxCD HelmRelease reconciliation
expected: `kubectl get helmreleases -n monitoring` shows loki and fluent-bit with READY=True
result: [pending]

### 2. Loki pod Running
expected: `kubectl get pods -n monitoring | grep loki` shows pod in Running state
result: [pending]

### 3. Fluent Bit DaemonSet on all nodes
expected: `kubectl get ds fluent-bit -n monitoring` shows DESIRED=3 READY=3
result: [pending]

### 4. Grafana Loki datasource queryable
expected: Grafana Explore shows Loki datasource returning logs for {job="fluent-bit"}
result: [pending]

### 5. Gatus accessible at https://status.watarystack.org
expected: Status page loads and shows service health indicators (requires DNS CNAME — see below)
result: [pending — waiting on DNS]

### 6. Headlamp accessible at https://headlamp.watarystack.org
expected: Headlamp UI loads at new domain after FluxCD reconciles ingress change
result: [pending]

## Summary

total: 6
passed: 0
issues: 0
pending: 6
skipped: 0
blocked: 0

## Gaps

## Action Required

**Before test 5 will work**, add this DNS record in Cloudflare Dashboard:
- Type: CNAME
- Name: `status`
- Target: `c2a903eb-4c21-4191-a94b-3ea234a53bed.cfargotunnel.com`
- Proxy: enabled (orange cloud)
