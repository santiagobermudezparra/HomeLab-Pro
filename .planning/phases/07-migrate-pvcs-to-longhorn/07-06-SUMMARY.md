---
phase: 07-migrate-pvcs-to-longhorn
plan: "06"
subsystem: infra
tags: [kubernetes, longhorn, pvc, storage, n8n, migration]

# Dependency graph
requires:
  - phase: 07-migrate-pvcs-to-longhorn
    provides: Longhorn StorageClass available for PVC migration
provides:
  - n8n-data PVC migrated from local-path to Longhorn with workflow data intact
affects:
  - 07-07 (remaining PVC migrations)

# Tech tracking
tech-stack:
  added: []
  patterns: [scale-to-0 PVC migration, busybox debug pod data transfer, chown restore pattern]

key-files:
  created: []
  modified:
    - apps/base/n8n/storage.yaml

key-decisions:
  - "n8n runs as UID 1000 (node user) - chown -R 1000:1000 applied after kubectl cp restore to prevent permission denied errors"
  - "storage.yaml has namespace: n8n in metadata - kubectl apply -f works directly without explicit -n flag"

patterns-established:
  - "PVC migration pattern: scale-to-0 → debug pod backup → delete PVC → apply updated storage.yaml → wait Bound → debug pod restore + chown → scale-to-1"
  - "App UID ownership fix: always chown restored data to app UID before deleting debug pod"

requirements-completed:
  - STOR-04

# Metrics
duration: 8min
completed: 2026-04-06
---

# Phase 07 Plan 06: n8n PVC Migration Summary

**n8n-data PVC (2Gi, workflow data) migrated from local-path to Longhorn storageClass with ownership fix to UID 1000**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-06T00:18:00Z
- **Completed:** 2026-04-06T00:26:00Z
- **Tasks:** 2 (+ 1 checkpoint auto-approved)
- **Files modified:** 1

## Accomplishments

- Updated `apps/base/n8n/storage.yaml` with `storageClassName: longhorn`
- Live migrated n8n-data PVC from local-path to Longhorn with 1.1MB workflow data intact
- Applied chown 1000:1000 fix after data restore — n8n pod started cleanly on first attempt

## Task Commits

1. **Task 1: Update n8n storage.yaml with storageClassName: longhorn** - `f836a13` (feat)
2. **Task 2: Live migration - backup, recreate PVC on Longhorn, restore data** - live cluster ops (no code commit)

## Files Created/Modified

- `apps/base/n8n/storage.yaml` - Added `storageClassName: longhorn` to PVC spec

## Decisions Made

- n8n runs as UID 1000 (node user in n8n Docker image) — chown -R 1000:1000 applied to restored data before debug pod deletion, preventing permission denied on startup
- `storage.yaml` includes `namespace: n8n` in metadata so `kubectl apply -f` routes correctly without explicit `-n n8n` flag

## Deviations from Plan

None - plan executed exactly as written. Ownership fix (chown 1000:1000) was documented in the execution context and applied as specified.

## Issues Encountered

None - migration completed cleanly on first attempt.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- n8n-data PVC is on Longhorn with `storageClassName: longhorn` and `STATUS: Bound`
- n8n pod is `Running 1/1` with workflow data intact
- Ready for Plan 07-07 (remaining PVC migrations)

---
*Phase: 07-migrate-pvcs-to-longhorn*
*Completed: 2026-04-06*

## Self-Check: PASSED

- `apps/base/n8n/storage.yaml` — FOUND
- `07-06-SUMMARY.md` — FOUND
- Commit `f836a13` — FOUND
- PVC `n8n-data` storageClassName: `longhorn` — VERIFIED
- PVC `n8n-data` status: `Bound` — VERIFIED
- Pod `n8n-76f8c5c6fc-z5lcf` — `1/1 Running` — VERIFIED
