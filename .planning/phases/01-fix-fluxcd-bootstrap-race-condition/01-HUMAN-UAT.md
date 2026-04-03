---
status: partial
phase: 01-fix-fluxcd-bootstrap-race-condition
source: [01-VERIFICATION.md]
started: 2026-04-04T00:00:00Z
updated: 2026-04-04T00:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Open PR for feat/phase-1-fix-fluxcd-bootstrap-race-condition
expected: PR exists targeting feat/homelab-improvement with the apps.yaml dependsOn change
result: [pending]

### 2. Verify live cluster after merge
expected: `kubectl get kustomization apps -n flux-system -o jsonpath='{.spec.dependsOn}'` returns `[{"name":"databases"}]` and `flux get kustomizations` shows all READY=True
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
