---
plan: 11-02
phase: 11
wave: 2
depends_on:
  - 11-01
autonomous: true
files_modified:
  - infrastructure/controllers/base/velero/schedules.yaml
  - infrastructure/controllers/base/velero/kustomization.yaml
requirements:
  - BACK-04

must_haves:
  truths:
    - "A Velero Schedule exists for every active app namespace (linkding, n8n, mealie, audiobookshelf, pgadmin, homepage, xm-spotify-sync, filebrowser)"
    - "Schedules run daily and retain backups for 14 days (ttl: 336h)"
    - "defaultVolumesToFsBackup: true on each schedule so Longhorn PVCs are included"
    - "velero schedule get shows 8 schedules in the cluster after FluxCD sync"
  artifacts:
    - path: "infrastructure/controllers/base/velero/schedules.yaml"
      provides: "8 Velero Schedule CRs — one per app namespace"
      contains: "kind: Schedule"
    - path: "infrastructure/controllers/base/velero/kustomization.yaml"
      provides: "Updated base kustomization including schedules.yaml"
      contains: "schedules.yaml"
  key_links:
    - from: "infrastructure/controllers/base/velero/schedules.yaml"
      to: "velero BackupStorageLocation/default"
      via: "Schedule.spec.template.storageLocation: default"
      pattern: "storageLocation: default"
    - from: "infrastructure/controllers/base/velero/kustomization.yaml"
      to: "infrastructure/controllers/base/velero/schedules.yaml"
      via: "resources: - schedules.yaml"
      pattern: "- schedules.yaml"
---

<objective>
Add Velero Schedule CRs for all 8 active app namespaces, stored in `infrastructure/controllers/base/velero/schedules.yaml`. Each schedule runs nightly at 2am, includes filesystem-based PVC backup (kopia via node-agent), and retains backups for 14 days.

Purpose: Satisfy BACK-04 — automated daily backups for all namespaces. These schedules deploy alongside Velero via FluxCD, so no manual `velero schedule create` commands are needed.
Output: `schedules.yaml` with 8 Schedule objects; updated kustomization.yaml includes it.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/ROADMAP.md
@.planning/phases/11-velero-full-backup/11-01-SUMMARY.md
</context>

<interfaces>
<!-- Velero Schedule CRD structure (velero.io/v1) -->

Velero Schedule object pattern:
```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-<namespace>
  namespace: velero
spec:
  schedule: "0 2 * * *"     # daily at 2am UTC
  template:
    includedNamespaces:
      - <namespace>
    storageLocation: default
    ttl: 336h0m0s             # 14 days = 14 * 24 = 336 hours
    defaultVolumesToFsBackup: true   # include Longhorn PVCs via kopia node-agent
    snapshotVolumes: false
```

Active app namespaces (from apps/staging/kustomization.yaml):
- linkding
- n8n
- mealie
- audiobookshelf
- pgadmin
- homepage
- xm-spotify-sync
- filebrowser

NOTE: homarr is intentionally commented out in staging/kustomization.yaml — do NOT include a schedule for homarr.

Current infrastructure/controllers/base/velero/kustomization.yaml (from Plan 01):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - repository.yaml
  - release.yaml
  - network-policy.yaml
```
</interfaces>

<tasks>

<task type="auto">
  <name>Task 1: Create schedules.yaml with 8 daily Schedule CRs and update base kustomization</name>
  <read_first>
    - infrastructure/controllers/base/velero/kustomization.yaml (to append schedules.yaml)
    - apps/staging/kustomization.yaml (to confirm active namespaces list — homarr is excluded)
    - infrastructure/controllers/base/velero/release.yaml (verify defaultVolumesToFsBackup is set at HelmRelease level, confirm schedule-level override is correct)
  </read_first>
  <files>
    infrastructure/controllers/base/velero/schedules.yaml,
    infrastructure/controllers/base/velero/kustomization.yaml
  </files>
  <action>
Create `infrastructure/controllers/base/velero/schedules.yaml` with 8 Velero Schedule objects separated by `---`. All schedules use:
- `namespace: velero` (Velero CRDs live in the velero control-plane namespace)
- `schedule: "0 2 * * *"` (daily at 02:00 UTC)
- `ttl: 336h0m0s` (14 days)
- `defaultVolumesToFsBackup: true` (filesystem backup via node-agent/kopia for Longhorn PVCs)
- `snapshotVolumes: false`
- `storageLocation: default`

Stagger schedules by 10 minutes across namespaces to avoid simultaneous backup I/O spikes on R2 and the nodes:
- linkding: `"0 2 * * *"` (02:00)
- n8n: `"10 2 * * *"` (02:10)
- mealie: `"20 2 * * *"` (02:20)
- audiobookshelf: `"30 2 * * *"` (02:30) — has most PVC data
- pgadmin: `"40 2 * * *"` (02:40)
- homepage: `"50 2 * * *"` (02:50)
- xm-spotify-sync: `"0 3 * * *"` (03:00)
- filebrowser: `"10 3 * * *"` (03:10)

Full file structure:
```yaml
# Velero daily backup schedules — one per active app namespace
# All schedules: daily, 14-day retention, filesystem-based PVC backup (kopia via node-agent)
# Schedules staggered by 10 minutes to avoid simultaneous R2 write spikes
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-linkding
  namespace: velero
spec:
  schedule: "0 2 * * *"
  template:
    includedNamespaces:
      - linkding
    storageLocation: default
    ttl: 336h0m0s
    defaultVolumesToFsBackup: true
    snapshotVolumes: false
---
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-n8n
  namespace: velero
spec:
  schedule: "10 2 * * *"
  template:
    includedNamespaces:
      - n8n
    storageLocation: default
    ttl: 336h0m0s
    defaultVolumesToFsBackup: true
    snapshotVolumes: false
---
# ... (repeat pattern for mealie, audiobookshelf, pgadmin, homepage, xm-spotify-sync, filebrowser)
```

Write all 8 Schedule objects in full (do not abbreviate with comments like "repeat pattern" — write every object completely).

Then update `infrastructure/controllers/base/velero/kustomization.yaml` to add `- schedules.yaml` to resources:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - repository.yaml
  - release.yaml
  - network-policy.yaml
  - schedules.yaml
```
  </action>
  <verify>
    <automated>grep -c "kind: Schedule" infrastructure/controllers/base/velero/schedules.yaml && kustomize build infrastructure/controllers/base/velero/ 2>&1 | grep -c "kind:"</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c "kind: Schedule" infrastructure/controllers/base/velero/schedules.yaml` returns exactly `8`
    - `kustomize build infrastructure/controllers/base/velero/` succeeds with no errors
    - Each Schedule has `ttl: 336h0m0s`, `defaultVolumesToFsBackup: true`, `snapshotVolumes: false`
    - No schedule exists for `homarr`
    - `infrastructure/controllers/base/velero/kustomization.yaml` contains `- schedules.yaml`
  </acceptance_criteria>
  <done>schedules.yaml has 8 complete Schedule objects, kustomize build passes, kustomization.yaml includes schedules.yaml</done>
</task>

</tasks>

<verification>
1. `grep -c "kind: Schedule" infrastructure/controllers/base/velero/schedules.yaml` → must return `8`
2. `kustomize build infrastructure/controllers/base/velero/ 2>&1 | grep "kind:"` → must show Namespace, HelmRepository, HelmRelease, 3x NetworkPolicy, 8x Schedule = 13 resources
3. `grep "homarr" infrastructure/controllers/base/velero/schedules.yaml` → must return nothing (no homarr schedule)
4. `grep "336h0m0s" infrastructure/controllers/base/velero/schedules.yaml | wc -l` → must return `8`
</verification>

<success_criteria>
- 8 Schedule objects in schedules.yaml, one per active app namespace
- All schedules: daily, 14-day TTL, filesystem backup enabled
- kustomize build of base/velero succeeds without errors
- No schedule for homarr (intentionally disabled app)
</success_criteria>

<output>
After completion, create `.planning/phases/11-velero-full-backup/11-02-SUMMARY.md` following the standard summary template.
</output>
