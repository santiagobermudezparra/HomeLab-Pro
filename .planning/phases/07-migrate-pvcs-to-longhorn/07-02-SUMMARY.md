---
phase: 07-migrate-pvcs-to-longhorn
plan: 02
subsystem: infra
tags: [longhorn, pvc, storage, migration, filebrowser, kubernetes]

# Dependency graph
requires:
  - phase: 06-install-longhorn-distributed-storage
    provides: Longhorn StorageClass installed and set as default
provides:
  - filebrowser-db PVC migrated from local-path to Longhorn with SQLite data intact
  - filebrowser-files PVC migrated from local-path to Longhorn
affects:
  - 07-03 through 07-07 (confirms 2-PVC atomic migration pattern works)

# Tech tracking
tech-stack:
  added: []
  patterns: [atomic 2-PVC migration — scale-to-0, backup both, recreate both, restore both, scale-up]

key-files:
  created: []
  modified:
    - apps/base/filebrowser/storage.yaml

key-decisions:
  - "Both PVCs migrated atomically while app is at 0 replicas — prevents SQLite database/file inconsistency"
  - "filebrowser runs as nobody (UID 65534) — no chown needed as busybox cp preserves readable permissions"

patterns-established:
  - "2-PVC atomic migration: scale-to-0 → backup both → delete both → apply updated storage.yaml → wait both Bound → restore both → scale-to-1"

requirements-completed: [STOR-04]

# Metrics
duration: ~5min
completed: 2026-04-06
---

# Phase 07 Plan 02: Migrate filebrowser PVCs to Longhorn Summary

**filebrowser-db (1Gi/44KB SQLite) and filebrowser-files (5Gi/~4KB) migrated atomically from local-path to Longhorn; filebrowser pod Running 1/1 with data intact**

## Performance

- **Duration:** ~5 min
- **Completed:** 2026-04-06
- **Tasks:** 3 completed (including checkpoint auto-approved)
- **Files modified:** 1

## Accomplishments

- Updated `apps/base/filebrowser/storage.yaml` to add `storageClassName: longhorn` on both PVC definitions
- Live cluster migration: scaled down filebrowser, backed up filebrowser-db (44KB SQLite) and filebrowser-files via debug pods, deleted both local-path PVCs, applied updated storage.yaml creating new Longhorn PVCs (both Bound), restored data to both PVCs, scaled up filebrowser
- filebrowser pod Running 1/1 with existing files and configuration intact
- No node pinning (no nodeSelector/nodeAffinity) on either PVC

## Task Commits

1. **Task 1: Update filebrowser storage.yaml with storageClassName: longhorn** - `420b7fd`
2. **Task 2: Live migration — backup both PVCs, recreate on Longhorn, restore** - Operational only (no file changes)
3. **Checkpoint: Human verification** - Auto-approved (user authorized autonomous execution)

## Files Created/Modified

- `apps/base/filebrowser/storage.yaml` - Added `storageClassName: longhorn` under `spec:` for both PVCs

## Decisions Made

- **Atomic 2-PVC migration:** Both PVCs migrated while app is at 0 replicas. Scaling up between PVC migrations would risk SQLite database pointing to new storage while file data is still on old storage.

## Deviations from Plan

None — migration followed the established pgadmin pattern.

## Issues Encountered

None — both PVCs bound immediately on Longhorn, filebrowser started cleanly.

## Self-Check: PASSED

- `apps/base/filebrowser/storage.yaml`: FOUND — contains `storageClassName: longhorn` on both PVCs (count: 2)
- `.planning/phases/07-migrate-pvcs-to-longhorn/07-02-SUMMARY.md`: FOUND
- Live cluster: `filebrowser-db` storageClass = `longhorn`, STATUS = `Bound`
- Live cluster: `filebrowser-files` storageClass = `longhorn`, STATUS = `Bound`
- Live cluster: filebrowser pod Running 1/1

---
*Phase: 07-migrate-pvcs-to-longhorn*
*Completed: 2026-04-06*
