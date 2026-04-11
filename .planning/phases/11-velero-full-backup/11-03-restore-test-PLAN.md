---
plan: 11-03
phase: 11
wave: 3
depends_on:
  - 11-01
  - 11-02
autonomous: false
files_modified:
  - .planning/phases/11-velero-full-backup/RESTORE-PROCEDURE.md
requirements:
  - BACK-05

must_haves:
  truths:
    - "velero backup get shows at least one completed backup for xm-spotify-sync namespace"
    - "Test restore of xm-spotify-sync namespace completes without errors"
    - "xm-spotify-sync pod comes back Running after restore"
    - "Restore procedure is documented with exact commands"
  artifacts:
    - path: ".planning/phases/11-velero-full-backup/RESTORE-PROCEDURE.md"
      provides: "Step-by-step restore runbook with exact velero CLI commands"
      contains: "velero restore create"
  key_links:
    - from: "velero backup"
      to: "Cloudflare R2 bucket velero"
      via: "BackupStorageLocation default → R2 endpoint"
      pattern: "velero backup get"
---

<objective>
Perform a live test restore of the xm-spotify-sync namespace from a completed Velero backup, verify the pod returns to Running state, and produce a documented restore runbook. This plan has a human-verify checkpoint because restore validation requires live cluster observation.

Purpose: Satisfy BACK-05 — prove that backups are restorable, not just created. A backup system is only as good as its last successful restore.
Output: Confirmed restore, running pod, and RESTORE-PROCEDURE.md runbook committed to the planning directory.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/ROADMAP.md
@.planning/phases/11-velero-full-backup/11-01-SUMMARY.md
@.planning/phases/11-velero-full-backup/11-02-SUMMARY.md
</context>

<interfaces>
<!-- Velero CLI commands for backup and restore -->

Check backups exist and are complete:
```bash
velero backup get
# Look for xm-spotify-sync backup with STATUS=Completed
```

Trigger an ad-hoc backup if the scheduled one has not run yet (schedules run at 2am):
```bash
velero backup create xm-spotify-sync-test \
  --include-namespaces xm-spotify-sync \
  --default-volumes-to-fs-backup \
  --storage-location default \
  --wait
```

Scale down the app before restore (to avoid resource conflicts):
```bash
kubectl scale deployment xm-spotify-sync -n xm-spotify-sync --replicas=0
kubectl scale deployment cloudflared -n xm-spotify-sync --replicas=0 2>/dev/null || true
```

Delete namespace (restore recreates it):
```bash
kubectl delete namespace xm-spotify-sync
```

Perform restore:
```bash
velero restore create xm-spotify-sync-restore-001 \
  --from-backup xm-spotify-sync-test \
  --wait
```

Verify restore:
```bash
velero restore describe xm-spotify-sync-restore-001
kubectl get pods -n xm-spotify-sync
kubectl get pvc -n xm-spotify-sync
```

Check restore status:
```bash
velero restore get
# Look for STATUS=Completed (not PartiallyFailed)
```

xm-spotify-sync was chosen as test target because:
- It is stateless (no database — just a cloudflared sidecar + sync job with no PVC)
- Deleting and restoring it has zero data-loss risk
- It demonstrates Velero's namespace restore capability without risking stateful data
</interfaces>

<tasks>

<task type="auto">
  <name>Task 1: Trigger ad-hoc backup of xm-spotify-sync and wait for completion</name>
  <read_first>
    - (no files — verify live cluster state with kubectl/velero CLI commands)
  </read_first>
  <files>
    (no files modified — live cluster operation)
  </files>
  <action>
First, verify Velero is healthy after FluxCD deployed Plan 01:
```bash
kubectl get pods -n velero
velero backup-location get
# BackupStorageLocation default should show PHASE=Available
```

If BackupStorageLocation is not Available, diagnose:
```bash
kubectl logs -n velero deployment/velero | tail -30
```

Once Available, trigger an ad-hoc backup:
```bash
velero backup create xm-spotify-sync-test-$(date +%Y%m%d) \
  --include-namespaces xm-spotify-sync \
  --default-volumes-to-fs-backup \
  --storage-location default \
  --wait
```

Wait for STATUS=Completed. If STATUS=PartiallyFailed or Failed:
```bash
velero backup describe xm-spotify-sync-test-$(date +%Y%m%d) --details
velero backup logs xm-spotify-sync-test-$(date +%Y%m%d)
```

Fix any issues before proceeding to restore.
  </action>
  <verify>
    <automated>velero backup get | grep xm-spotify-sync | grep -i completed</automated>
  </verify>
  <acceptance_criteria>
    - `velero backup-location get` shows `default` with PHASE `Available`
    - `velero backup get` shows at least one xm-spotify-sync backup with STATUS `Completed`
    - Backup was completed within the last 30 minutes (fresh, not stale)
  </acceptance_criteria>
  <done>An xm-spotify-sync backup exists with STATUS=Completed in the default storage location</done>
</task>

<task type="auto">
  <name>Task 2: Perform test restore — delete xm-spotify-sync namespace and restore from backup</name>
  <read_first>
    - (no files — live cluster operation)
  </read_first>
  <files>
    (no files modified — live cluster operation)
  </files>
  <action>
Record the backup name from Task 1 (e.g., `xm-spotify-sync-test-20260411`). Use it in the restore command below.

Step 1 — Scale down to avoid conflicts during delete:
```bash
kubectl scale deployment xm-spotify-sync -n xm-spotify-sync --replicas=0 2>/dev/null || true
kubectl scale deployment cloudflared -n xm-spotify-sync --replicas=0 2>/dev/null || true
```

Step 2 — Delete the namespace (Velero restore recreates it):
```bash
kubectl delete namespace xm-spotify-sync
# Wait until namespace is fully deleted
kubectl get namespace xm-spotify-sync 2>&1   # Should say "not found"
```

Step 3 — Trigger restore:
```bash
velero restore create xm-spotify-sync-restore-001 \
  --from-backup <BACKUP_NAME_FROM_TASK_1> \
  --wait
```

Step 4 — Verify restore:
```bash
velero restore describe xm-spotify-sync-restore-001
velero restore get   # STATUS should be Completed
kubectl get pods -n xm-spotify-sync
kubectl get all -n xm-spotify-sync
```

Expected result: xm-spotify-sync pod Running (or Completed if it's a Job), namespace exists, all original resources restored.

If STATUS=PartiallyFailed, check:
```bash
velero restore logs xm-spotify-sync-restore-001 | grep -i error
```

Common issue: NetworkPolicy restore may require Cilium to be ready — this is expected and non-blocking for the restore itself.
  </action>
  <verify>
    <automated>velero restore get | grep xm-spotify-sync-restore-001 | grep -i completed</automated>
  </verify>
  <acceptance_criteria>
    - `velero restore get` shows `xm-spotify-sync-restore-001` with STATUS `Completed` (not PartiallyFailed)
    - `kubectl get namespace xm-spotify-sync` exists after restore
    - `kubectl get pods -n xm-spotify-sync` shows at least one pod (Running or Succeeded)
    - No critical errors in restore logs (warnings about cluster-scoped resources are acceptable)
  </acceptance_criteria>
  <done>Restore STATUS=Completed, xm-spotify-sync namespace exists with running pod</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <what-built>Velero test restore of xm-spotify-sync namespace. The namespace was deleted and fully restored from backup including all Kubernetes objects.</what-built>
  <how-to-verify>
    1. Run: `kubectl get pods -n xm-spotify-sync` — confirm pod is Running or Completed
    2. Run: `velero restore describe xm-spotify-sync-restore-001` — confirm no critical errors
    3. Run: `velero backup get` — confirm the backup used for restore is still listed
    4. Optional: `velero schedule get` — confirm all 8 daily schedules appear (may need FluxCD sync first)
    5. Verify in Cloudflare R2 dashboard that backup artifacts exist in the `velero` bucket
  </how-to-verify>
  <resume-signal>Type "approved" when restore is confirmed working, or describe any failures</resume-signal>
</task>

<task type="auto">
  <name>Task 3: Write RESTORE-PROCEDURE.md runbook</name>
  <read_first>
    - (no files — write based on commands executed in Tasks 1 and 2)
  </read_first>
  <files>
    .planning/phases/11-velero-full-backup/RESTORE-PROCEDURE.md
  </files>
  <action>
Create `.planning/phases/11-velero-full-backup/RESTORE-PROCEDURE.md` documenting the exact restore procedure. Include:

1. **Prerequisites** — velero CLI installed, KUBECONFIG set, BackupStorageLocation Available
2. **List available backups** — `velero backup get`
3. **Full namespace restore** — exact commands with placeholders for namespace and backup name
4. **Selective restore** — how to restore only specific resources (e.g., `--include-resources PersistentVolumeClaim`)
5. **Verification steps** — how to confirm restore success
6. **Troubleshooting** — PartiallyFailed common causes and fixes
7. **Schedule management** — how to check and manually trigger scheduled backups

The runbook must use the actual commands tested in Tasks 1 and 2. Do not invent commands — use exactly what worked. Include the real backup name format observed.

This file is committed to git as institutional knowledge (not a secret — no credentials).
  </action>
  <verify>
    <automated>test -f .planning/phases/11-velero-full-backup/RESTORE-PROCEDURE.md && wc -l .planning/phases/11-velero-full-backup/RESTORE-PROCEDURE.md</automated>
  </verify>
  <acceptance_criteria>
    - File exists at `.planning/phases/11-velero-full-backup/RESTORE-PROCEDURE.md`
    - Contains all 7 sections: Prerequisites, List backups, Full restore, Selective restore, Verification, Troubleshooting, Schedule management
    - Commands are literal (no placeholders left unresolved from actual test)
    - File is at least 50 lines (substantive documentation, not stub)
  </acceptance_criteria>
  <done>RESTORE-PROCEDURE.md exists with complete runbook, at least 50 lines, covering full restore lifecycle</done>
</task>

</tasks>

<verification>
1. `velero backup get` — shows completed backup for xm-spotify-sync
2. `velero restore get` — shows xm-spotify-sync-restore-001 with STATUS Completed
3. `kubectl get pods -n xm-spotify-sync` — pod Running after restore
4. `velero schedule get` — shows 8 daily schedules (after FluxCD sync from Plans 01+02)
5. `test -f .planning/phases/11-velero-full-backup/RESTORE-PROCEDURE.md` — runbook exists
6. `velero backup-location get` — default BackupStorageLocation shows Available
</verification>

<success_criteria>
- Test restore of xm-spotify-sync completed with STATUS=Completed (not PartiallyFailed)
- xm-spotify-sync pod Running after namespace was deleted and restored
- RESTORE-PROCEDURE.md committed to git with complete runbook
- `velero schedule get` shows 8 daily backup schedules
- Human checkpoint approved confirming visual verification
</success_criteria>

<output>
After completion, create `.planning/phases/11-velero-full-backup/11-03-SUMMARY.md` following the standard summary template.
</output>
