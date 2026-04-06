---
phase: 07-migrate-pvcs-to-longhorn
plan: 03
subsystem: infra
tags: [longhorn, kubernetes, pvc, storage, mealie]

# Dependency graph
requires:
  - phase: 07-migrate-pvcs-to-longhorn/07-01
    provides: PVC migration procedure validated end-to-end (scale-to-0, debug pod backup/restore, chown, scale-to-1)
provides:
  - mealie-data PVC migrated from local-path to Longhorn (replicated, node-agnostic)
  - mealie can now schedule on any cluster node (no local-path node affinity)
affects: [08-balance-workloads-to-workers, mealie scheduling]

# Tech tracking
tech-stack:
  added: []
  patterns: [debug pod backup/restore with chown fix (UID 911 for linuxserver mealie image)]

key-files:
  created: []
  modified:
    - apps/base/mealie/storage.yaml

key-decisions:
  - "mealie linuxserver image uses UID 911 (abc user) — chown -R 911:911 applied after kubectl cp restore"
  - "Chown pattern confirmed again: kubectl cp does not preserve container UID ownership; always chown after restore"

patterns-established:
  - "PVC migration pattern: scale-to-0 → backup via debug pod → delete PVC → apply updated storage.yaml → wait Bound → restore via debug pod + chown to app UID → scale-to-1"

requirements-completed:
  - STOR-04

# Metrics
duration: 10min
completed: 2026-04-06
---

# Phase 07 Plan 03: Migrate mealie PVC to Longhorn Summary

**mealie-data PVC migrated from local-path to Longhorn with 1.4MB recipe data intact; mealie now schedules on any node with 2-replica storage**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-06T00:00:00Z
- **Completed:** 2026-04-06T00:11:49Z
- **Tasks:** 2 (Task 1 pre-committed ac96ac1; Task 2 live migration executed)
- **Files modified:** 1

## Accomplishments
- mealie-data PVC deleted from local-path and recreated on Longhorn StorageClass
- 1.4MB recipe data (mealie.db, secrets, logs, users, recipes dirs) backed up and restored via busybox debug pod
- File ownership fixed to UID 911:911 (linuxserver mealie abc user) before scale-up
- mealie pod Running 1/1 with zero restarts after migration
- No node affinity pinning — mealie is now schedulable on worker nodes

## Task Commits

Each task was committed atomically:

1. **Task 1: Update mealie storage.yaml with storageClassName: longhorn** - `ac96ac1` (feat)
2. **Task 2: Live migration — backup, recreate PVC on Longhorn, restore data** - live cluster ops (no Git artifact)

**Plan metadata:** (this SUMMARY commit)

## Files Created/Modified
- `apps/base/mealie/storage.yaml` - Added `storageClassName: longhorn` to mealie-data PVC definition

## Decisions Made
- Applied chown -R 911:911 after kubectl cp restore — linuxserver/mealie image uses UID 911 for the `abc` user; kubectl cp preserves local user ownership, not container UID
- Pattern reused from 07-01 (pgadmin used 5050:5050); confirmed generalized pattern: always chown to app UID after restore

## Deviations from Plan

None — plan executed exactly as written, with learned chown pattern from 07-01 context applied as specified in execution context.

## Issues Encountered
None — migration succeeded on first attempt with no errors.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- mealie-data is now on Longhorn with 2-replica replication
- mealie pod Running 1/1 with recipe data intact
- Ready to continue with 07-04 (next PVC migration plan)
- Checkpoint auto-approved per autonomous execution authorization

---
*Phase: 07-migrate-pvcs-to-longhorn*
*Completed: 2026-04-06*

## Self-Check

**Files exist:**
- `apps/base/mealie/storage.yaml`: FOUND (storageClassName: longhorn confirmed)
- `.planning/phases/07-migrate-pvcs-to-longhorn/07-03-SUMMARY.md`: FOUND (this file)

**Commits exist:**
- ac96ac1 (Task 1 - feat(07-03): add storageClassName: longhorn to mealie-data PVC): FOUND

**Live cluster state:**
- `kubectl get pvc mealie-data -n mealie -o jsonpath='{.spec.storageClassName}'` → `longhorn`
- `kubectl get pvc mealie-data -n mealie -o jsonpath='{.status.phase}'` → `Bound`
- mealie pod: `1/1 Running` (0 restarts)
- nodeAffinity: empty

## Self-Check: PASSED
