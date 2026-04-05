---
phase: 07-migrate-pvcs-to-longhorn
plan: 01
subsystem: infra
tags: [longhorn, pvc, storage, migration, pgadmin, kubernetes]

# Dependency graph
requires:
  - phase: 06-install-longhorn-distributed-storage
    provides: Longhorn StorageClass installed and set as default, all 3 nodes schedulable
provides:
  - pgadmin-data-pvc migrated from local-path to Longhorn with data intact
  - Validated end-to-end PVC migration procedure (scale-down, backup, recreate on Longhorn, restore, scale-up)
affects:
  - 07-02 through 07-07 (filebrowser, mealie, audiobookshelf, linkding, n8n, CNPG — all use same procedure)

# Tech tracking
tech-stack:
  added: []
  patterns: [kubectl debug pod pattern for PVC data copy, chown to app UID before scale-up]

key-files:
  created: []
  modified:
    - apps/base/pgadmin/storage.yaml

key-decisions:
  - "Proactively chown restored files to 5050:5050 (pgadmin UID) before scale-up — prevents permission denied errors on startup"
  - "Debug pod restore + chown pattern: copy data in via busybox debug pod, fix ownership, delete pod, then scale up app"

patterns-established:
  - "PVC migration pattern: scale-to-0 → debug pod + kubectl cp out → delete PVC → apply updated storage.yaml → wait Bound → debug pod + kubectl cp in + chown → delete pod → scale-to-1"
  - "Always pre-fix file ownership to app UID after kubectl cp restore (kubectl cp preserves local user ownership, not container UID)"

requirements-completed: [STOR-04]

# Metrics
duration: 2min
completed: 2026-04-05
---

# Phase 07 Plan 01: Migrate pgadmin PVC to Longhorn Summary

**pgadmin-data-pvc (1Gi, 192KB data) migrated from local-path to Longhorn with data intact; validated full PVC migration procedure including ownership fix for UID 5050**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-04-05T19:41:54Z
- **Completed:** 2026-04-05T19:43:44Z (paused at checkpoint for human verification)
- **Tasks:** 2 completed, 1 checkpoint awaiting human verification
- **Files modified:** 1

## Accomplishments

- Updated `apps/base/pgadmin/storage.yaml` to add `storageClassName: longhorn` (kustomize build validated)
- Live cluster migration: scaled down pgadmin, backed up 192KB data via debug pod, deleted old local-path PVC, created new Longhorn PVC (Bound immediately), restored data via second debug pod with ownership fix, scaled up pgadmin
- pgadmin pod is Running 1/1 on Longhorn PVC with no permission errors

## Task Commits

Each task was committed atomically:

1. **Task 1: Update pgadmin storage.yaml with storageClassName: longhorn** - `7e07943` (feat)
2. **Task 2: Live migration — backup, recreate PVC on Longhorn, restore data** - Operational only (no file changes to commit)

## Files Created/Modified

- `apps/base/pgadmin/storage.yaml` - Added `storageClassName: longhorn` under `spec:`

## Decisions Made

- **Preemptive ownership fix:** After `kubectl cp` restores data, files are owned by the local user (UID 1000 in this case), not the pgadmin container UID (5050). The research noted this as a potential pitfall. Rather than waiting for a permission error after scale-up, we proactively ran `chown -R 5050:5050 /pgadmin-data/` in the debug pod before deleting it. pgadmin started cleanly on first attempt with no permission denied errors.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Proactively fixed file ownership before scale-up**
- **Found during:** Task 2 (Live migration — restore step)
- **Issue:** After `kubectl cp` into the debug pod, files were owned by UID 1000 (local santi user). pgadmin runs as UID 5050 and would fail with "permission denied" on `/var/lib/pgadmin` (noted as a pitfall in the research)
- **Fix:** Added `kubectl exec -n pgadmin debug-pgadmin -- chown -R 5050:5050 /pgadmin-data/` before deleting the restore debug pod
- **Files modified:** None (live cluster operation)
- **Verification:** pgadmin pod started Running 1/1 with no permission errors in logs
- **Committed in:** N/A (operational fix, no file change)

---

**Total deviations:** 1 auto-fixed (1 missing critical — preemptive ownership fix)
**Impact on plan:** Ownership fix was documented as a potential pitfall in the research; applying it proactively prevents app startup failure. No scope creep.

## Issues Encountered

None — migration proceeded smoothly. The ownership fix was applied proactively based on the research pitfall documentation.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- pgadmin PVC migration validated end-to-end — procedure is confirmed working
- Ownership fix pattern established: always `chown` to app UID in restore debug pod before scale-up
- Ready to proceed with Plan 02 (filebrowser — 2 PVCs on worker-01)
- Blocker: Human verification checkpoint for pgadmin UI data integrity must be approved first

---
*Phase: 07-migrate-pvcs-to-longhorn*
*Completed: 2026-04-05*
