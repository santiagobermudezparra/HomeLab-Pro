---
phase: 7
slug: migrate-pvcs-to-longhorn
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-06
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | kubectl + flux CLI (operational verification) |
| **Config file** | none — cluster live state |
| **Quick run command** | `kubectl get pvc -n {app-namespace} -o wide` |
| **Full suite command** | `kubectl get pvc --all-namespaces -o wide \| grep -v longhorn` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run per-app PVC status check
- **After every plan wave:** Run `kubectl get pvc --all-namespaces -o wide | grep -v longhorn` — must return zero rows
- **Before `/gsd:verify-work`:** All apps healthy, zero local-path PVCs
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 7-01-01 | 01 | 1 | STOR-04 | operational | `kubectl get pvc -n pgadmin -o wide \| grep longhorn` | ✅ | ⬜ pending |
| 7-02-01 | 02 | 1 | STOR-04 | operational | `kubectl get pvc -n filebrowser -o wide \| grep longhorn` | ✅ | ⬜ pending |
| 7-03-01 | 03 | 1 | STOR-04 | operational | `kubectl get pvc -n mealie -o wide \| grep longhorn` | ✅ | ⬜ pending |
| 7-04-01 | 04 | 1 | STOR-04 | operational | `kubectl get pvc -n audiobookshelf -o wide \| grep longhorn` | ✅ | ⬜ pending |
| 7-05-01 | 05 | 2 | STOR-04 | operational | `kubectl get pvc -n linkding -o wide \| grep longhorn` | ✅ | ⬜ pending |
| 7-06-01 | 06 | 2 | STOR-04 | operational | `kubectl get pvc -n n8n -o wide \| grep longhorn` | ✅ | ⬜ pending |
| 7-07-01 | 07 | 3 | STOR-05 | operational | `kubectl get pvc -n linkding -l cnpg.io/cluster -o wide \| grep longhorn` | ✅ | ⬜ pending |
| 7-07-02 | 07 | 3 | STOR-05 | operational | `kubectl get pvc -n n8n -l cnpg.io/cluster -o wide \| grep longhorn` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*None — no test framework needed. Verification is operational (kubectl commands against live cluster).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| App data integrity post-migration | STOR-04 | Requires human review of app UI/data | Log into each app and verify data is intact |
| CNPG cluster resumes replication | STOR-05 | Requires observing CNPG status over time | `kubectl get cluster -n linkding; kubectl get cluster -n n8n` — check `status.readyInstances` |
| Zero local-path PVCs remain | STOR-04/05 | Final state check | `kubectl get pvc --all-namespaces -o wide \| grep local-path` must return empty |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
