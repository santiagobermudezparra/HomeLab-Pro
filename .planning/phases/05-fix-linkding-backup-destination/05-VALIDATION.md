---
phase: 5
slug: fix-linkding-backup-destination
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-05
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | kubectl + kustomize (no unit test framework — infra manifests) |
| **Config file** | none — kubectl/kustomize CLI only |
| **Quick run command** | `kubectl kustomize databases/staging/linkding/` |
| **Full suite command** | `kubectl apply -k databases/staging/linkding/ --dry-run=client` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `kubectl kustomize databases/staging/linkding/`
- **After every plan wave:** Run `kubectl apply -k databases/staging/linkding/ --dry-run=client`
- **Before `/gsd:verify-work`:** Full suite must exit 0
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | BACK-02 | manifest | `kubectl kustomize databases/staging/linkding/ \| grep barmanObjectStore` | ❌ W0 | ⬜ pending |
| 05-01-02 | 01 | 1 | BACK-02 | secret | `kubectl apply -k databases/staging/linkding/ --dry-run=client` | ❌ W0 | ⬜ pending |
| 05-01-03 | 01 | 1 | BACK-02 | human | `kubectl get backup -n linkding` shows Completed | manual | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `databases/staging/linkding/linkding-backup-s3-secret.yaml` — SOPS-encrypted S3 credentials secret
- [ ] `databases/staging/linkding/postgresql-cluster.yaml` — patched with `spec.backup.barmanObjectStore`
- [ ] `databases/staging/linkding/kustomization.yaml` — backup-config.yaml uncommented + secret added

*Existing infrastructure (CNPG, SOPS, kustomize) covers all tooling requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Backup object shows `Completed` status | BACK-02 | Requires actual S3 bucket, live CNPG reconciliation, and barman-cloud-backup execution — cannot be dry-run tested | After PR merge + FluxCD sync: `kubectl get backup -n linkding` — expect at least one backup with `status.phase: completed` and an S3 destination path |
| S3 bucket contains backup files | BACK-02 | Requires live bucket inspection | Check R2/S3 bucket — expect `linkding/` prefix with WAL files and base backup |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
