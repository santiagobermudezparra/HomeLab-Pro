---
status: verified
phase: 01-fix-fluxcd-bootstrap-race-condition
source: [01-VERIFICATION.md]
started: 2026-04-04T00:00:00Z
updated: 2026-04-04T00:00:00Z
---

## Current Test

Verified via manual apply to staging cluster on 2026-04-04.

## Tests

### 1. Open PR for feat/phase-1-fix-fluxcd-bootstrap-race-condition
expected: PR exists targeting feat/homelab-improvement with the apps.yaml dependsOn change
result: passed — PR merged into feat/homelab-improvement

### 2. Verify live cluster after merge
expected: `kubectl get kustomization apps -n flux-system -o jsonpath='{.spec.dependsOn}'` returns `[{"name":"databases"}]` and `flux get kustomizations` shows all READY=True
result: passed — `kubectl apply -f clusters/staging/apps.yaml` applied cleanly, dependsOn confirmed as `[{"name":"databases"}]`, all 7 kustomizations READY=True

## Summary

total: 2
passed: 2
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

NOTE: Change is on feat/homelab-improvement, not main. FluxCD will revert on next sync until feat/homelab-improvement is merged to main.
