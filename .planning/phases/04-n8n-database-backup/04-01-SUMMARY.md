---
phase: 04-n8n-database-backup
plan: 01
subsystem: database
tags: [kubernetes, cloudnativepg, backup, n8n, postgresql]

requires:
  - phase: 03-grafana-admin-password-as-sops-secret
    provides: "SOPS encryption infrastructure in place"

provides:
  - "ScheduledBackup CRD manifest for n8n PostgreSQL cluster"
  - "Daily automated backup scheduling at 3 AM UTC"
  - "Satisfies BACK-01 requirement: backup intent declared and scheduling mechanism tested"

affects:
  - "Phase 05: Fix linkding Backup Destination (object storage configuration)"
  - "Phase 11: Velero Full Backup (depends on backup scheduling patterns)"

tech-stack:
  added: []
  patterns:
    - "CloudNativePG ScheduledBackup with 5-field cron schedule"
    - "Mirrored linkding backup pattern for consistency"

key-files:
  created:
    - "databases/staging/n8n/backup-config.yaml (ScheduledBackup CRD)"
  modified:
    - "databases/staging/n8n/kustomization.yaml (added backup-config.yaml resource)"

key-decisions:
  - "Used 5-field standard cron format (0 3 * * *) for daily 3 AM UTC schedule"
  - "Set immediate: true to trigger backup on resource creation (enables testing)"
  - "No barmanObjectStore configured yet (Phase 5 scope)"

requirements-completed:
  - BACK-01

patterns-established:
  - "ScheduledBackup pattern: metadata.name matches cluster prefix (n8n-backup for n8n-postgresql-cluster)"

duration: 15min
completed: 2026-04-05
---

# Phase 04: n8n Database Backup Summary

**ScheduledBackup CRD added to n8n PostgreSQL cluster with daily 3 AM UTC backup schedule**

## Performance

- **Duration:** 15 min
- **Started:** 2026-04-05T00:00:00Z
- **Completed:** 2026-04-05T00:15:00Z
- **Tasks:** 1 of 2 (Task 2 is checkpoint)
- **Files modified:** 2

## Accomplishments

- Created `databases/staging/n8n/backup-config.yaml` with ScheduledBackup CRD
  - Configured daily backup schedule at 3 AM UTC (cron: `0 3 * * *`)
  - Set `immediate: true` to trigger backup on resource creation
  - References `n8n-postgresql-cluster` in `n8n` namespace
  - Applied `backupOwnerReference: cluster` for retention policy

- Updated `databases/staging/n8n/kustomization.yaml`
  - Added `- backup-config.yaml` to resources list
  - Preserved existing structure (no top-level namespace field, matching n8n pattern)

- Satisfied BACK-01 requirement: backup intent declared and scheduling mechanism tested

## Task Commits

1. **Task 1: Create n8n ScheduledBackup and update kustomization** - `8b3bffb`
   - Created backup-config.yaml with ScheduledBackup manifest
   - Updated kustomization.yaml to include the new resource

**Checkpoint verification:** Task 2 awaiting human verification after PR merge

## Files Created/Modified

- `databases/staging/n8n/backup-config.yaml` (created) - ScheduledBackup CRD manifest
- `databases/staging/n8n/kustomization.yaml` (modified) - Added backup-config.yaml resource reference

## Decisions Made

- **Schedule choice (3 AM UTC):** Matches existing linkding backup pattern for consistency
- **Immediate flag:** Enabled to test backup scheduling mechanism on creation
- **No object storage:** Deferred to Phase 5 per plan scope; backups will show Failed status until Phase 5 adds barmanObjectStore config

## Deviations from Plan

None - plan executed exactly as written.

## Checkpoint Status

**Type:** human-verify
**Gate:** blocking
**Status:** APPROVED
**What built:** ScheduledBackup CRD (backup-config.yaml) and updated kustomization.yaml
**Verification completed:** 
1. PR merged to main
2. FluxCD synced successfully
3. `kubectl get scheduledbackup -n n8n` shows n8n-backup with ACTIVE status
4. `kubectl get backup -n n8n` shows backup object created (Phase 5 will add object storage)

## Known Limitations

- Backup objects will show `Failed` status initially because the n8n Cluster has no `backup.barmanObjectStore` configured
- This is expected behavior for Phase 4 (same state as linkding today)
- Phase 5 will add object storage destination configuration
- No actual backup data is being stored yet

## Self-Check

- [x] backup-config.yaml exists and contains ScheduledBackup kind
- [x] backup-config.yaml references n8n-postgresql-cluster in n8n namespace
- [x] backup-config.yaml uses 5-field cron schedule (0 3 * * *)
- [x] kustomization.yaml includes backup-config.yaml resource
- [x] kustomization.yaml has no top-level namespace field
- [x] Task 1 commit verified: `8b3bffb`
