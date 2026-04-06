---
phase: 07-migrate-pvcs-to-longhorn
plan: "05"
subsystem: infra
tags: [kubernetes, longhorn, pvc, storage, linkding]

requires:
  - phase: 07-migrate-pvcs-to-longhorn/07-01
    provides: PVC migration procedure validated (scale-to-0, debug pod backup, delete PVC, recreate on Longhorn, restore, chown, scale-to-1)

provides:
  - linkding-data-pvc bound on Longhorn StorageClass (1Gi, ReadWriteOnce)
  - linkding app pod Running 1/1 with bookmark data intact after migration

affects:
  - 07-06
  - 07-07

tech-stack:
  added: []
  patterns:
    - "chown -R 1000:1000 after kubectl cp restore for linkding (sethcottle/linkding image UID 1000)"

key-files:
  created: []
  modified:
    - apps/base/linkding/storage.yaml

key-decisions:
  - "linkding runs as UID 1000 (sethcottle/linkding image default) — chown -R 1000:1000 applied after kubectl cp restore"
  - "storage.yaml has no namespace metadata — applied PVC manifest with explicit -n linkding flag"

patterns-established:
  - "UID pattern for linkding: chown -R 1000:1000 /ld-data/ after data restore"

requirements-completed:
  - STOR-04

duration: 3min
completed: "2026-04-06"
---

# Phase 07 Plan 05: Migrate linkding PVC to Longhorn Summary

**linkding-data-pvc (48KB SQLite bookmark database) migrated from local-path to Longhorn with UID 1000 ownership fix and pod verified Running 1/1**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-06T00:17:54Z
- **Completed:** 2026-04-06T00:21:00Z
- **Tasks:** 2 (+ checkpoint auto-approved)
- **Files modified:** 1

## Accomplishments

- Updated `apps/base/linkding/storage.yaml` to include `storageClassName: longhorn`
- Executed live PVC migration: scaled to 0, backed up 48KB SQLite data, deleted local-path PVC, created Longhorn PVC, restored data with correct UID 1000 ownership, scaled back to 1
- linkding pod Running 1/1 with bookmark database intact; PVC Bound on Longhorn

## Task Commits

Each task was committed atomically:

1. **Task 1: Update linkding storage.yaml with storageClassName: longhorn** - `9baced7` (feat)
2. **Task 2: Live migration** - no new files (live cluster operation; covered by Task 1 commit)

**Plan metadata:** (docs commit below)

## Files Created/Modified

- `apps/base/linkding/storage.yaml` - Added `storageClassName: longhorn` under spec

## Decisions Made

- linkding runs as UID 1000 (sethcottle/linkding image default) — applied `chown -R 1000:1000` after `kubectl cp` restore to prevent permission denied errors
- `storage.yaml` has no namespace metadata — used explicit `-n linkding` flag on all `kubectl apply/delete` commands

## Deviations from Plan

None - plan executed exactly as written (ownership fix was called out in the execution context).

## Issues Encountered

None — migration completed cleanly on first attempt.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- linkding-data-pvc is now on Longhorn, surviving any single node failure
- Ready for Plan 07-06 (n8n PVC migration to Longhorn)

---
*Phase: 07-migrate-pvcs-to-longhorn*
*Completed: 2026-04-06*

## Self-Check: PASSED

- FOUND: apps/base/linkding/storage.yaml
- FOUND: 07-05-SUMMARY.md
- FOUND: commit 9baced7
