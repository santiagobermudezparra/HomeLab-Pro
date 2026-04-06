---
phase: 07-migrate-pvcs-to-longhorn
plan: "04"
subsystem: infra
tags: [kubernetes, longhorn, pvcs, audiobookshelf, storage-migration]

requires:
  - phase: 06-install-longhorn
    provides: Longhorn StorageClass deployed and operational in cluster

provides:
  - All 7 audiobookshelf PVCs migrated from local-path to Longhorn storageClass
  - audiobookshelf-config (1Gi) and audiobookshelf-metadata (1Gi) data intact on Longhorn
  - audiobookshelf pod Running 1/1 post-migration

affects:
  - 07-migrate-pvcs-to-longhorn (subsequent plans: mealie, n8n, linkding, homepage, xm-spotify-sync)

tech-stack:
  added: []
  patterns:
    - "Atomic 7-PVC migration: scale-to-0, backup data PVCs, delete all 7, recreate on Longhorn, restore, chown, scale-to-1"
    - "chown -R 99:100 for audiobookshelf (lscr.io/linuxserver image uses UID 99/nobody, GID 100/users)"
    - "Empty media PVCs (audiobooks, podcasts, ebooks, comics, videos) require no backup — delete and recreate"

key-files:
  created: []
  modified:
    - apps/base/audiobookshelf/storage.yaml

key-decisions:
  - "All 7 PVCs migrated atomically in a single scale-to-0 operation — app stayed at 0 replicas for the entire migration window to prevent mount failures"
  - "Only audiobookshelf-config (SQLite DB, 320KB) and audiobookshelf-metadata (logs/cache/backups, 80KB) required backup; 5 empty media PVCs deleted and recreated fresh"
  - "chown -R 99:100 applied in debug pod before scale-up — lscr.io/linuxserver/audiobookshelf runs as UID 99 (nobody), GID 100 (users)"
  - "storage.yaml lacks namespace field — must apply with -n audiobookshelf flag explicitly; applying without namespace sent PVCs to current context namespace (monitoring), requiring correction"

patterns-established:
  - "Multi-PVC atomic migration: all PVCs of an app must be migrated together in one scale-to-0 window"
  - "Always explicitly specify -n <namespace> when applying PVC manifests that lack namespace metadata"

requirements-completed:
  - STOR-04

duration: 10min
completed: 2026-04-06
---

# Phase 07 Plan 04: Audiobookshelf PVC Migration Summary

**All 7 audiobookshelf PVCs atomically migrated from local-path to Longhorn, with SQLite config database and metadata intact, using busybox debug pods and chown to UID 99/GID 100**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-06T00:05:00Z
- **Completed:** 2026-04-06T00:14:21Z
- **Tasks:** 2 (+ 1 auto-approved checkpoint)
- **Files modified:** 1

## Accomplishments
- Updated apps/base/audiobookshelf/storage.yaml with storageClassName: longhorn on all 7 PVCs
- Backed up audiobookshelf-config (SQLite database + migrations directory, 320KB) and audiobookshelf-metadata (backups/cache/logs/streams, 80KB)
- Deleted all 7 old local-path PVCs and recreated on Longhorn — all 7 Bound within seconds
- Restored config and metadata with correct ownership (chown -R 99:100) before scale-up
- audiobookshelf pod started Running 1/1 on first attempt with library data intact

## Task Commits

Each task was committed atomically:

1. **Task 1: Update audiobookshelf storage.yaml with storageClassName: longhorn on all 7 PVCs** - `480abe3` (feat)
2. **Task 2: Live migration — scale down, backup, recreate on Longhorn, restore, scale up** - no git commit (live cluster imperative ops)

## Files Created/Modified
- `apps/base/audiobookshelf/storage.yaml` - Added storageClassName: longhorn to all 7 PVC definitions

## Decisions Made
- All 7 PVCs migrated atomically — audiobookshelf mounts all 7 simultaneously, so partial migration would cause mount failures
- Only config (SQLite DB) and metadata needed backup; 5 media PVCs (audiobooks, podcasts, ebooks, comics, videos) were empty (~4KB lost+found) and recreated fresh
- chown -R 99:100 applied in busybox debug pod before deletion — lscr.io/linuxserver/audiobookshelf uses UID 99 (nobody), GID 100 (users)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] PVCs applied to wrong namespace due to missing namespace metadata**
- **Found during:** Task 2 (Step 4 — Delete all 7 old PVCs and apply updated storage.yaml)
- **Issue:** `kubectl apply -f apps/base/audiobookshelf/storage.yaml` without `-n audiobookshelf` flag sent all 7 PVCs to the current kubectl context namespace (monitoring), not the audiobookshelf namespace
- **Fix:** Deleted the 7 incorrectly-namespaced PVCs from monitoring namespace, then re-applied with `kubectl apply -f apps/base/audiobookshelf/storage.yaml -n audiobookshelf`
- **Files modified:** None (runtime fix only)
- **Verification:** `kubectl get pvc -n audiobookshelf` showed all 7 PVCs Bound in correct namespace
- **Committed in:** N/A (live cluster fix)

---

**Total deviations:** 1 auto-fixed (1 bug — namespace targeting)
**Impact on plan:** Namespace fix was caught immediately before any restore steps; no data loss, no impact on migration outcome.

## Issues Encountered
- storage.yaml has no namespace metadata on PVC definitions (by design, for base/overlay pattern portability). When applied without an explicit `-n` flag in wrong kubectl context, PVCs go to the context-default namespace. Future mitigation: always apply PVC manifests with explicit `-n <namespace>` flag.

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- audiobookshelf is Running 1/1 with all 7 PVCs on Longhorn, verified Bound
- Ready for Plan 07-05 (next app PVC migration)
- Pattern confirmed: atomic multi-PVC migration works; chown to app UID required for lscr.io/linuxserver images

## Self-Check: PASSED

- FOUND: apps/base/audiobookshelf/storage.yaml
- FOUND: .planning/phases/07-migrate-pvcs-to-longhorn/07-04-SUMMARY.md
- FOUND: commit 480abe3 (feat(07-04): add storageClassName: longhorn to all 7 audiobookshelf PVCs)
- VERIFIED: All 7 PVCs in audiobookshelf namespace show storageClassName: longhorn, STATUS: Bound
- VERIFIED: audiobookshelf pod Running 1/1
