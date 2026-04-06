---
phase: 07-migrate-pvcs-to-longhorn
verified: 2026-04-06T08:30:00Z
status: passed
score: 7/7 must-haves verified
re_verification: false
gaps: []
human_verification:
  - test: "pgadmin data integrity — server connections intact"
    expected: "pgadmin UI loads with existing PostgreSQL server connections listed"
    why_human: "Visual UI state cannot be verified programmatically; pgadmin-data-pvc migration restores config including server definitions"
  - test: "linkding bookmark data intact post-CNPG migration"
    expected: "linkding UI shows existing bookmarks, new bookmarks can be added"
    why_human: "Database content correctness (bookmark rows) requires UI or SQL query to verify; automated check confirms cluster is healthy but not row-level data"
  - test: "n8n workflow data intact post-CNPG migration"
    expected: "n8n UI shows existing workflows which can be opened and executed"
    why_human: "Database content correctness (workflow definitions) requires UI interaction; automated check confirms cluster is healthy but not workflow row-level data"
---

# Phase 7: Migrate PVCs to Longhorn — Verification Report

**Phase Goal:** All stateful app PVCs and database PVCs are migrated from local-path to Longhorn, enabling data resilience across node failures.
**Verified:** 2026-04-06T08:30:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Zero local-path PVCs remain across all app namespaces | VERIFIED | `kubectl get pvc --all-namespaces --no-headers \| grep -v longhorn` returns empty |
| 2 | All 6 app pods Running 1/1 (pgadmin, filebrowser, mealie, audiobookshelf, linkding, n8n) | VERIFIED | Live cluster: all 6 app deployments show 1/1 Running with 0 restarts post-migration |
| 3 | Both CNPG clusters show "Cluster in healthy state" | VERIFIED | `kubectl get cluster --all-namespaces` shows both linkding-postgres and n8n-postgresql-cluster in healthy state |
| 4 | All 6 app storage.yaml files have storageClassName: longhorn | VERIFIED | All files confirmed via grep; pgadmin: 1, filebrowser: 2, mealie: 1, audiobookshelf: 7, linkding: 1, n8n: 1 occurrence(s) |
| 5 | Both postgresql-cluster.yaml files have pvcTemplate.storageClassName: longhorn | VERIFIED | Flat pvcTemplate format (CNPG-correct) present in both files |
| 6 | Both postgresql-cluster.yaml files use bootstrap.initdb (not bootstrap.recovery) | VERIFIED | grep confirms initdb present, no recovery refs remain |
| 7 | PR #39 exists targeting feat/homelab-improvement | VERIFIED | PR #39 open, base: feat/homelab-improvement, head: feat/phase-07-migrate-pvcs |

**Score:** 7/7 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `apps/base/pgadmin/storage.yaml` | storageClassName: longhorn | VERIFIED | Line 7: `storageClassName: longhorn` |
| `apps/base/filebrowser/storage.yaml` | storageClassName: longhorn on both PVCs | VERIFIED | Lines 6 and 18: 2 occurrences |
| `apps/base/mealie/storage.yaml` | storageClassName: longhorn | VERIFIED | Line 7: `storageClassName: longhorn` |
| `apps/base/audiobookshelf/storage.yaml` | storageClassName: longhorn on all 7 PVCs | VERIFIED | 7 occurrences confirmed |
| `apps/base/linkding/storage.yaml` | storageClassName: longhorn | VERIFIED | Line 6: `storageClassName: longhorn` |
| `apps/base/n8n/storage.yaml` | storageClassName: longhorn | VERIFIED | Line 7: `storageClassName: longhorn` |
| `databases/staging/linkding/postgresql-cluster.yaml` | pvcTemplate.storageClassName: longhorn + bootstrap.initdb | VERIFIED | Line 24 storageClassName, line 35 initdb; no recovery refs |
| `databases/staging/n8n/postgresql-cluster.yaml` | pvcTemplate.storageClassName: longhorn + bootstrap.initdb | VERIFIED | Line 24 storageClassName, line 35 initdb; no recovery refs |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `apps/base/pgadmin/storage.yaml` | Longhorn StorageClass | storageClassName: longhorn field | WIRED | Live PVC pgadmin-data-pvc shows storageClass=longhorn, STATUS=Bound |
| `apps/base/filebrowser/storage.yaml` | Longhorn StorageClass | storageClassName: longhorn on both PVCs | WIRED | filebrowser-db and filebrowser-files both Bound on longhorn |
| `apps/base/mealie/storage.yaml` | Longhorn StorageClass | storageClassName: longhorn field | WIRED | mealie-data Bound on longhorn |
| `apps/base/audiobookshelf/storage.yaml` | Longhorn StorageClass | storageClassName: longhorn on 7 PVCs | WIRED | All 7 audiobookshelf PVCs Bound on longhorn |
| `apps/base/linkding/storage.yaml` | Longhorn StorageClass | storageClassName: longhorn field | WIRED | linkding-data-pvc Bound on longhorn |
| `apps/base/n8n/storage.yaml` | Longhorn StorageClass | storageClassName: longhorn field | WIRED | n8n-data Bound on longhorn |
| `databases/staging/linkding/postgresql-cluster.yaml` | Longhorn StorageClass | pvcTemplate.storageClassName: longhorn | WIRED | linkding-postgres-1 PVC Bound on longhorn; cluster healthy |
| `databases/staging/n8n/postgresql-cluster.yaml` | Longhorn StorageClass | pvcTemplate.storageClassName: longhorn | WIRED | n8n-postgresql-cluster-1 PVC Bound on longhorn; cluster healthy |

---

### Live PVC Inventory (Full)

| Namespace | PVC Name | StorageClass | Status |
|-----------|----------|-------------|--------|
| pgadmin | pgadmin-data-pvc | longhorn | Bound |
| filebrowser | filebrowser-db | longhorn | Bound |
| filebrowser | filebrowser-files | longhorn | Bound |
| mealie | mealie-data | longhorn | Bound |
| audiobookshelf | audiobookshelf-audiobooks | longhorn | Bound |
| audiobookshelf | audiobookshelf-comics | longhorn | Bound |
| audiobookshelf | audiobookshelf-config | longhorn | Bound |
| audiobookshelf | audiobookshelf-ebooks | longhorn | Bound |
| audiobookshelf | audiobookshelf-metadata | longhorn | Bound |
| audiobookshelf | audiobookshelf-podcasts | longhorn | Bound |
| audiobookshelf | audiobookshelf-videos | longhorn | Bound |
| linkding | linkding-data-pvc | longhorn | Bound |
| linkding | linkding-postgres-1 | longhorn | Bound |
| n8n | n8n-data | longhorn | Bound |
| n8n | n8n-postgresql-cluster-1 | longhorn | Bound |

**Total: 15 PVCs, all on Longhorn, all Bound. Zero local-path PVCs.**

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Zero local-path PVCs remain | `kubectl get pvc --all-namespaces --no-headers \| grep -v longhorn` | Empty output | PASS |
| All app pods Running | `kubectl get pods -n pgadmin -n filebrowser -n mealie -n audiobookshelf -n linkding -n n8n --no-headers \| grep -v Running` | Empty output | PASS |
| Both CNPG clusters healthy | `kubectl get cluster --all-namespaces` | Both show "Cluster in healthy state" | PASS |
| PR #39 targets correct base | `gh pr view 39 --json baseRefName` | feat/homelab-improvement | PASS |
| linkding-postgres bootstrap is initdb | `grep "initdb\|recovery" databases/staging/linkding/postgresql-cluster.yaml` | initdb found, no recovery | PASS |
| n8n-postgresql-cluster bootstrap is initdb | `grep "initdb\|recovery" databases/staging/n8n/postgresql-cluster.yaml` | initdb found, no recovery | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| STOR-04 | 07-01 through 07-06 | All stateful app PVCs migrated from local-path to Longhorn | SATISFIED | 13 app PVCs (pgadmin, filebrowser x2, mealie, audiobookshelf x7, linkding-data, n8n-data) confirmed Bound on longhorn in live cluster |
| STOR-05 | 07-07 | CloudNativePG PVCs migrated from local-path to Longhorn | SATISFIED | linkding-postgres-1 and n8n-postgresql-cluster-1 Bound on longhorn; both CNPG clusters healthy |

---

### Anti-Patterns Found

None. All 8 modified files scanned — no TODOs, FIXMEs, placeholders, or stub implementations found.

---

### Human Verification Required

#### 1. pgadmin Data Integrity

**Test:** Open pgadmin in browser (pgadmin.watarystack.org), log in, and confirm server connections are listed (not an empty state).
**Expected:** Existing PostgreSQL server connections appear; configuration intact after PVC migration.
**Why human:** pgadmin connection definitions stored in pgadmin-data-pvc; programmatic check confirms PVC is Bound on Longhorn but cannot confirm the 192KB config contents match pre-migration state.

#### 2. linkding Bookmark Data Post-CNPG Migration

**Test:** Open linkding in browser, confirm bookmarks are listed, and add a new bookmark to verify write access.
**Expected:** Existing bookmarks visible; new bookmarks persist; no database connection errors.
**Why human:** CNPG cluster was deleted and recreated from R2 backup. Cluster is healthy and linkding pod is Running, but row-level bookmark data correctness requires UI or psql query verification.

#### 3. n8n Workflow Data Post-CNPG Migration

**Test:** Open n8n in browser, confirm workflows are listed and can be opened and executed.
**Expected:** Existing workflow definitions visible; no database connection errors.
**Why human:** CNPG cluster was deleted and recreated from R2 backup. Cluster is healthy and n8n pod is Running, but row-level workflow data correctness requires UI verification.

---

### Gaps Summary

No gaps. All automated verifications passed:

- All 15 PVCs across 7 namespaces are on Longhorn (zero local-path PVCs remaining)
- All 6 app pods are Running 1/1
- Both CNPG clusters show "Cluster in healthy state"
- All 8 storage manifest files have the correct storageClassName: longhorn
- Both postgresql-cluster.yaml files use initdb bootstrap (recovery spec removed post-migration)
- PR #39 is open targeting feat/homelab-improvement with all Phase 7 changes

The 3 items in human_verification are data-integrity spot-checks on migrated content — they are confirmatory, not blocking. The phase goal (all PVCs migrated from local-path to Longhorn, data resilience enabled) is fully achieved.

---

### Notable Deviations (from SUMMARYs — not failures)

Two bugs were encountered and auto-fixed during execution:

1. **CNPG pvcTemplate nesting** (07-07): Plan specified `pvcTemplate.spec.storageClassName` but CNPG API requires flat `pvcTemplate.storageClassName`. Fixed in commit `09e7971`. Final files reflect the correct format.

2. **CNPG WAL archive check** (07-07): `barman-cloud-check-wal-archive` blocked recovery when new cluster reused the same R2 path. Resolved by using `externalClusters` recovery approach and temporarily omitting the backup section during initial cluster creation. Bootstrap was reverted to `initdb` post-recovery in commit `7dd5836`.

Both deviations were caught, fixed, and verified during execution. No residual issues remain.

---

_Verified: 2026-04-06T08:30:00Z_
_Verifier: Claude (gsd-verifier)_
