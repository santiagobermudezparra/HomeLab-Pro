---
phase: 10
slug: networkpolicies-per-namespace-isolation
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-11
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | kubectl (cluster verification scripts) |
| **Config file** | none — kubectl commands used directly |
| **Quick run command** | `kubectl get networkpolicies --all-namespaces` |
| **Full suite command** | `kubectl get networkpolicies --all-namespaces && kubectl run test-isolation --image=busybox --rm -it --restart=Never -- sh` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `kubectl get networkpolicies --all-namespaces`
- **After every plan wave:** Run full suite command above
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 1 | SEC-03 | infra | `kubectl get networkpolicy default-deny-ingress -n linkding` | ✅ | ⬜ pending |
| 10-01-02 | 01 | 1 | SEC-03 | infra | `kubectl get networkpolicy default-deny-ingress -n n8n` | ✅ | ⬜ pending |
| 10-01-03 | 01 | 1 | SEC-04 | infra | `kubectl get networkpolicy allow-app-to-postgres -n linkding` | ✅ | ⬜ pending |
| 10-01-04 | 01 | 1 | SEC-04 | infra | `kubectl get networkpolicy allow-app-to-postgres -n n8n` | ✅ | ⬜ pending |
| 10-02-01 | 02 | 1 | SEC-04 | infra | `kubectl get networkpolicy allow-prometheus-scrape -n linkding` | ✅ | ⬜ pending |
| 10-03-01 | 03 | 3 | SEC-05 | manual | Cross-namespace block test via test pod | ⚠️ manual | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements — kubectl available, cluster accessible.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| mealie cannot reach linkding's postgres | SEC-05 | Requires spawning test pod and running connection attempt | `kubectl run test-pod --image=busybox --rm -it --restart=Never -n mealie -- nc -zv linkding-postgres-rw.linkding.svc.cluster.local 5432; expect connection refused` |
| Cross-namespace DB access is blocked | SEC-05 | Same as above — live cluster verification | Run test pod from non-authorized namespace, verify timeout/refused |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
