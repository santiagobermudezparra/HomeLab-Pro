---
status: partial
phase: 08-balance-workloads-to-worker-nodes
source: [08-VERIFICATION.md]
started: 2026-04-06T00:00:00Z
updated: 2026-04-06T00:00:00Z
---

## Current Test

[awaiting human testing — run after PR #45 merges and FluxCD syncs]

## Tests

### 1. Live pod distribution across worker nodes
expected: `kubectl get pods --all-namespaces -o wide` shows app pods distributed across all 3 nodes; Worker-02 running at least 5 non-system pods; control-plane no longer hosts majority of app pods
result: [pending]

### 2. cloudflared replica spread across different nodes
expected: Each app's 2 cloudflared replicas land on different nodes (topologySpreadConstraints with DoNotSchedule enforces co-location prevention)
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
