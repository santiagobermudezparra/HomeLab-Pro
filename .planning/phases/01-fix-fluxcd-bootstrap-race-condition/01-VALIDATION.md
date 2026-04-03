---
phase: 1
slug: fix-fluxcd-bootstrap-race-condition
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-04-04
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | kubectl dry-run (no unit test framework — pure YAML change) |
| **Config file** | none |
| **Quick run command** | `kubectl apply -f clusters/staging/apps.yaml --dry-run=client` |
| **Full suite command** | `kubectl get kustomization apps -n flux-system -o jsonpath='{.spec.dependsOn}'` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `kubectl apply -f clusters/staging/apps.yaml --dry-run=client`
- **After every plan wave:** Run `kubectl get kustomization apps -n flux-system -o jsonpath='{.spec.dependsOn}'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | CRIT-01 | smoke | `kubectl apply -f clusters/staging/apps.yaml --dry-run=client` | N/A (existing file) | ⬜ pending |
| 1-01-02 | 01 | 1 | CRIT-01 | smoke | `kubectl get kustomization apps -n flux-system -o jsonpath='{.spec.dependsOn}'` → `[{"name":"databases"}]` | N/A (cluster state) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

None — no test files to create. Validation is purely cluster state inspection via kubectl.

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| apps Kustomization has dependsOn: databases in live cluster after merge | CRIT-01 | Cluster state — only verifiable post-merge when FluxCD reconciles | After PR merge: `kubectl get kustomization apps -n flux-system -o jsonpath='{.spec.dependsOn}'` should return `[{"name":"databases"}]` |
| flux get kustomizations shows all kustomizations READY | CRIT-01 | Requires live cluster reconciliation | After merge: `flux get kustomizations` — all should show READY=True |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (N/A — no test files)
- [x] No watch-mode flags
- [x] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
