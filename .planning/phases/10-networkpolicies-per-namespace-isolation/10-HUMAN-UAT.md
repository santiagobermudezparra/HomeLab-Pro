---
status: partial
phase: 10-networkpolicies-per-namespace-isolation
source: [10-VERIFICATION.md]
started: 2026-04-11T00:00:00Z
updated: 2026-04-11T00:00:00Z
---

## Current Test

[awaiting human testing — requires PR #58 merged + FluxCD applied]

## Tests

### 1. NetworkPolicies applied by FluxCD
expected: After PR #58 merges, `kubectl get networkpolicies --all-namespaces` shows 3-4 policies per app namespace (audiobookshelf, filebrowser, homepage, linkding, mealie, n8n, pgadmin, xm-spotify-sync)
result: [pending]

### 2. Cross-namespace DB isolation enforced
expected: Test pod in mealie namespace cannot reach linkding-postgres — `pg_isready -h linkding-postgres-rw.linkding.svc.cluster.local -p 5432` returns connection refused or times out (NOT "accepting connections")
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
