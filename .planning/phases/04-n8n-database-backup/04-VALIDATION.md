---
phase: 4
slug: n8n-database-backup
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-05
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | kubectl + kustomize (infrastructure-as-code validation) |
| **Config file** | none — using existing cluster tooling |
| **Quick run command** | `kubectl get scheduledbackup -n n8n` |
| **Full suite command** | `kubectl apply -k databases/staging/n8n/ --dry-run=client && kubectl get scheduledbackup -n n8n` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `kubectl get scheduledbackup -n n8n`
- **After every plan wave:** Run `kubectl apply -k databases/staging/n8n/ --dry-run=client && kubectl get scheduledbackup -n n8n`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 4-01-01 | 01 | 1 | BACK-01 | manifest | `kubectl apply -k databases/staging/n8n/ --dry-run=client` | ❌ W0 | ⬜ pending |
| 4-01-02 | 01 | 1 | BACK-01 | live | `kubectl get scheduledbackup -n n8n` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `databases/staging/n8n/backup-config.yaml` — ScheduledBackup manifest for n8n-postgresql-cluster
- [ ] `databases/staging/n8n/kustomization.yaml` — updated to include backup-config.yaml

*Both files created in Wave 1.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| ScheduledBackup resource accepted by CNPG operator | BACK-01 | Requires live cluster (no integration test harness) | `kubectl describe scheduledbackup linkding-backup -n n8n` — check Events for no errors |

*Note: "At least one completed backup" from ROADMAP done criterion requires object storage (Phase 5 scope) — verification scoped to ScheduledBackup existence only in Phase 4.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
