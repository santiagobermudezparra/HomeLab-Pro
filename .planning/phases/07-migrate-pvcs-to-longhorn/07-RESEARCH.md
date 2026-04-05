# Phase 7: Migrate PVCs to Longhorn - Research

**Researched:** 2026-04-06
**Domain:** Kubernetes PVC migration from local-path to Longhorn; CNPG cluster storage migration
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| STOR-04 | All stateful app PVCs migrated from local-path to Longhorn | Manual migration procedure (scale-down, rsync/kubectl-cp, recreate PVC with storageClassName: longhorn, restore) documented per app |
| STOR-05 | CNPG PVCs (linkding-postgres-1, n8n-postgresql-cluster-1) migrated from local-path to Longhorn | CNPG backup-and-restore workflow using existing barmanObjectStore backups documented; pvcTemplate.storageClassName field confirmed |
</phase_requirements>

---

## Project Constraints (from CLAUDE.md)

- Do NOT hardcode node names, `nodeSelector`, `nodeName`, or `nodeAffinity` that pins workloads to specific nodes. K3s handles workload scheduling organically — this must be preserved across all manifests and migration procedures.
- Always use the base/overlay pattern: base configs in `apps/base/`, environment-specific overlays in `apps/staging/`
- Encrypt all secrets with SOPS before committing
- Branch from `feat/homelab-improvement` (per STATE.md convention), never commit directly to main
- All secrets must use age key from `clusters/staging/.sops.yaml`
- FluxCD tracks `main` branch only — reconciliation and smoke tests are post-merge concerns

---

## Summary

Phase 7 migrates 15 local-path PVCs across 7 app namespaces to Longhorn distributed storage. There are two distinct migration workflows: (1) manual copy for regular app PVCs, and (2) CNPG backup-and-restore for PostgreSQL PVCs. Both are procedural/operational plans — the only Git artifact per app is updating `storage.yaml` to add `storageClassName: longhorn`.

**Key live cluster facts (verified 2026-04-06):**
- Longhorn is fully healthy: all 3 nodes schedulable, 30 pods Running, default StorageClass confirmed
- All 15 PVCs are local-path, sizes range from 1Gi to 5Gi (total ~38Gi allocated, actual data is tiny: <10MB for most apps)
- Both CNPG clusters have active barmanObjectStore backups to Cloudflare R2 (last backup <1hr ago), making CNPG migration safe
- app pods are split: control-plane hosts linkding, mealie, audiobookshelf; worker-01 hosts pgadmin, filebrowser, n8n, n8n-postgres, linkding-postgres is also on control-plane
- Worker-01 has 76GB free (Longhorn schedulable); Control-plane has 141GB free (Longhorn schedulable); Worker-02 has 229GB free

**Migration order per roadmap (sequential, safest first):**
pgadmin → filebrowser → mealie → audiobookshelf (7 PVCs) → linkding-data → n8n-data → CNPG PVCs (linkding-postgres-1, n8n-postgresql-cluster-1)

**Primary recommendation:** Use `kubectl cp` (not rsync) for data copy since actual data is <10MB per app. Each migration is: scale-down → kubectl cp data out → delete old PVC → apply updated storage.yaml (with `storageClassName: longhorn`) → wait for Longhorn PVC to bind → kubectl cp data in → scale-up. CNPG PVCs use the CNPG bootstrap.recovery workflow with the existing R2 barmanObjectStore.

---

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| kubectl cp | v1.33.0 (client) | Copy files to/from running pods | Built-in, no extra tooling; data is tiny (<10MB actual) |
| Longhorn StorageClass | 1.7.3 (installed) | Target storage provider | Already deployed, default SC, 3-node replication |
| CNPG operator | 1.24.1 (installed) | Manages PostgreSQL clusters and recovery | Already deployed; bootstrap.recovery is the official CNPG storage migration path |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| kubectl scale | v1.33.0 | Scale deployments down/up during migration | Required to quiesce writes before data copy |
| kubectl wait | v1.33.0 | Wait for pod to reach desired state | Used between scale-down and data copy to ensure clean shutdown |
| barman-cloud backup (Cloudflare R2) | existing | Source for CNPG restore | Both linkding and n8n have active backups |
| kustomize build --dry-run=client | v5.6.0 | Validate manifest changes | Run before committing storage.yaml updates |

### No New Installations Required

All required tools are already present in the cluster. Phase 7 is a pure operational procedure + Git manifest change. No HelmReleases, HelmRepositories, or new infrastructure components are added.

---

## Architecture Patterns

### PVC Migration Pattern (App PVCs)

The standard migration sequence for each app PVC:

```
1. kubectl scale deployment/{app} -n {app} --replicas=0
2. kubectl wait --for=delete pod -n {app} -l app={app} --timeout=60s
3. mkdir /tmp/{app}-backup
4. kubectl cp {namespace}/{pod}:{mount-path}/. /tmp/{app}-backup/
5. # Update storage.yaml: add storageClassName: longhorn
6. kubectl delete pvc {pvc-name} -n {namespace}
7. kubectl apply -f apps/base/{app}/storage.yaml  (or flux reconcile)
8. kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/{pvc-name} -n {namespace} --timeout=120s
9. NEW_POD=$(kubectl get pod -n {namespace} -l app={app} -o name)  # after scale-up
10. kubectl scale deployment/{app} -n {app} --replicas=1
11. kubectl wait --for=condition=Ready pod -n {namespace} -l app={app} --timeout=120s
12. kubectl cp /tmp/{app}-backup/. {namespace}/{pod}:{mount-path}/
13. kubectl rollout restart deployment/{app} -n {namespace}  # if needed to re-read files
14. rm -rf /tmp/{app}-backup
```

**Important:** Step 5 (storageClassName update in Git) and step 6 (delete old PVC) must be coordinated. The Git change alone does not delete the old PVC — the old PVC must be manually deleted first. Once deleted and the new storage.yaml is applied (locally via `kubectl apply` or via FluxCD reconcile), Longhorn provisions a new PVC immediately.

**CRITICAL — No nodeSelector/nodeName:** The new Longhorn PVC has no node affinity. When the app pod restarts, it can schedule on any node. This is the desired behavior per the project constraint. Do NOT add any node pinning.

### CNPG PVC Migration Pattern

CNPG manages its own PVCs via `volumeClaimTemplates`. You cannot manually recreate these PVCs — you must use the CNPG backup-and-restore bootstrap workflow.

```
Workflow:
1. Trigger an on-demand Backup (or use most recent ScheduledBackup) to ensure R2 has fresh data
2. kubectl delete cluster {name} -n {namespace}   # deletes cluster AND its PVCs
3. Edit databases/staging/{app}/postgresql-cluster.yaml:
   - Change spec.bootstrap from initdb → recovery (with barmanObjectStore source)
   - Add spec.storage.pvcTemplate.spec.storageClassName: longhorn
4. git commit → PR → merge → FluxCD applies new Cluster
5. CNPG operator provisions new PVC on Longhorn, restores from R2 backup
6. Wait for cluster to reach "healthy state"
7. Verify app can connect and data is intact
8. Post-restore: restore spec.bootstrap back to initdb (prevent re-initialization on pod restart)
```

**Key detail:** `spec.storage.pvcTemplate` is a standard PVC template spec. Setting `spec.storage.pvcTemplate.spec.storageClassName: longhorn` tells CNPG to provision the PostgreSQL data PVC on Longhorn instead of the default StorageClass. The `spec.storage.size: 2Gi` remains unchanged.

**Backup availability confirmed:** Both CNPG clusters have `backup.barmanObjectStore.destinationPath` configured and ScheduledBackups running (last backup <1hr ago as of 2026-04-06).

### storage.yaml Update Pattern (Git change per app)

For every non-CNPG app, the only Git change is adding `storageClassName: longhorn` to each PVC in `apps/base/{app}/storage.yaml`:

```yaml
# Before (existing):
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pgadmin-data-pvc
  namespace: pgadmin
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi

# After (add storageClassName):
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pgadmin-data-pvc
  namespace: pgadmin
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

**Note:** PVC `storageClassName` is immutable after creation. The Git change only affects **new** PVCs created after the old one is deleted. The manual deletion step is always required.

### CNPG storage.yaml Update Pattern

For CNPG, the change is in `databases/staging/{app}/postgresql-cluster.yaml`:

```yaml
spec:
  storage:
    size: 2Gi
    pvcTemplate:
      spec:
        storageClassName: longhorn
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 2Gi
  bootstrap:
    recovery:
      backup:
        name: {most-recent-backup-object-name}
```

After successful restore, update bootstrap back to `initdb` form (or leave recovery; CNPG only runs bootstrap once on cluster creation — it does not re-run on pod restart).

### Anti-Patterns to Avoid

- **Don't add nodeSelector/nodeAffinity to PVCs or deployments** to pin them to specific nodes after migration — Longhorn handles data placement via its replica scheduling. Adding node affinity defeats the purpose of distributed storage.
- **Don't use `kubectl cp` while the app is still running** — always scale to 0 replicas before copying to ensure filesystem consistency (no partial writes).
- **Don't delete a PVC without first copying data out** — local-path PVCs have `reclaimPolicy: Delete`, meaning data is gone immediately on PVC deletion.
- **Don't migrate all apps in one plan** — sequential per-app plans prevent cascading failures. One app at a time.
- **Don't apply the storage.yaml Git change before manually deleting the old PVC** — FluxCD will see the PVC already exists and not recreate it (Kubernetes resource ownership). The old PVC must be deleted first so the new one (with `storageClassName: longhorn`) gets created.
- **Don't use `kubectl apply` to change storageClassName on an existing PVC** — storageClassName is immutable; Kubernetes will reject the patch. Delete and recreate.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CNPG PVC data copy | Manual rsync of PostgreSQL data directory | CNPG bootstrap.recovery from barmanObjectStore | PostgreSQL data directory is not portable as raw files; CNPG handles WAL replay, checksums, and cluster state. Raw copy will corrupt data. |
| Wait for pod deletion | `sleep N` | `kubectl wait --for=delete pod` | Race condition: pod may not have flushed data to disk; wait is deterministic |
| Data integrity check | Manual file listing | App smoke tests (verify login works, data appears) | End-to-end validation catches storage mount issues that file count checks miss |

---

## Runtime State Inventory

This phase is a data migration, not a rename. No string replacement is involved. The runtime state that matters is the PVC data itself.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | 15 local-path PVCs with data; CNPG clusters have R2 object store backups (verified active) | Manual copy via kubectl cp (app PVCs); CNPG backup-and-restore (postgres PVCs) |
| Live service config | Both CNPG clusters have barmanObjectStore configured pointing to Cloudflare R2 bucket `homelab-postgres-backups` | No config change; these are used as the restore source |
| OS-registered state | None — no OS-level references to PVC names | None |
| Secrets/env vars | R2 credentials in `linkding-backup-s3-secret` and `n8n-backup-s3-secret` SOPS secrets (already deployed) | None — reuse for restore |
| Build artifacts | None | None |

**Nothing found in category:** OS-registered state — none verified by `kubectl get nodes` and `kubectl describe pv` showing only Kubernetes-native node affinity (set by local-path provisioner, will be absent in new Longhorn PVCs).

---

## Live Cluster State (Verified 2026-04-06)

### PVC Inventory with Node Pinning

All 15 PVCs are currently on `local-path`, each pinned to one node via PV node affinity:

| Namespace | PVC Name | Size | Pinned Node | Actual Data |
|-----------|----------|------|-------------|-------------|
| pgadmin | pgadmin-data-pvc | 1Gi | homelab-worker-01 | 192KB |
| filebrowser | filebrowser-db | 1Gi | homelab-worker-01 | 44KB |
| filebrowser | filebrowser-files | 5Gi | homelab-worker-01 | ~4KB (empty) |
| mealie | mealie-data | 1Gi | control-plane | 1.4MB |
| audiobookshelf | audiobookshelf-config | 1Gi | control-plane | 320KB |
| audiobookshelf | audiobookshelf-metadata | 1Gi | control-plane | 80KB |
| audiobookshelf | audiobookshelf-audiobooks | 1Gi | control-plane | ~4KB (empty) |
| audiobookshelf | audiobookshelf-podcasts | 5Gi | control-plane | ~4KB (empty) |
| audiobookshelf | audiobookshelf-ebooks | 5Gi | control-plane | ~4KB (empty) |
| audiobookshelf | audiobookshelf-comics | 5Gi | control-plane | ~4KB (empty) |
| audiobookshelf | audiobookshelf-videos | 5Gi | control-plane | ~4KB (empty) |
| linkding | linkding-data-pvc | 1Gi | control-plane | 48KB |
| n8n | n8n-data | 2Gi | homelab-worker-01 | 1.1MB |
| linkding | linkding-postgres-1 | 2Gi | control-plane | CNPG managed |
| n8n | n8n-postgresql-cluster-1 | 2Gi | homelab-worker-01 | CNPG managed |

### Longhorn Node Schedulability

| Node | Schedulable | Available | Reserved | Maximum |
|------|------------|-----------|----------|---------|
| control-plane (santi-standard-pc-i440fx-piix-1996) | True | 141GB | 50GB | 179GB |
| homelab-worker-01 | True | 76GB | 70GB | 250GB |
| homelab-worker-02 | True | 229GB | 70GB | 250GB |

All 3 nodes schedulable — replication factor 2 will use any 2 of the 3 nodes per volume.

### CNPG Backup Status

| Cluster | Namespace | Last Backup | Destination | Status |
|---------|-----------|-------------|-------------|--------|
| linkding-postgres | linkding | <1hr ago (2026-04-06) | s3://homelab-postgres-backup/linkding (R2) | Active |
| n8n-postgresql-cluster | n8n | <1hr ago (2026-04-06) | s3://homelab-postgres-backup/n8n (R2) | Active |

---

## Common Pitfalls

### Pitfall 1: Forgetting the app pod uses the same PVC name but on a new volume

**What goes wrong:** After deleting the old PVC and creating a new Longhorn one with the same name, the deployment mounts it and the app starts — but data appears empty. The volume was provisioned correctly but data was never restored.
**Why it happens:** The data copy step (step 12 in the procedure) must happen AFTER the new PVC is bound and the pod is running (for `kubectl cp` destination), but BEFORE the app reads/initializes data.
**How to avoid:** Scale to 0, copy data out, recreate PVC, then do `kubectl cp` data IN while pod is at 0 replicas (using a temporary debug pod that mounts the new PVC), OR scale to 1, copy data in immediately, and restart.
**Warning signs:** App starts without error but shows empty state (no bookmarks, no config).

### Pitfall 2: FluxCD reconciles storage.yaml before old PVC is deleted

**What goes wrong:** You update storage.yaml with `storageClassName: longhorn`, commit, and merge. FluxCD sees the updated PVC manifest but the existing PVC (on local-path) already exists — Kubernetes does not update the storageClassName on existing PVCs. FluxCD reports success but the PVC stays on local-path.
**Why it happens:** Kubernetes PVC `storageClassName` is immutable. FluxCD applies a strategic merge patch that does not delete+recreate resources.
**How to avoid:** Always delete the old PVC first (imperatively via `kubectl delete pvc`), THEN let FluxCD (or a manual `kubectl apply`) create the new one from the updated manifest.
**Warning signs:** `kubectl get pvc` still shows `storageClass: local-path` after a FluxCD reconcile.

### Pitfall 3: Copying data while app is still writing (data corruption)

**What goes wrong:** rsync or `kubectl cp` runs while the app is serving requests, capturing a partial/inconsistent state.
**Why it happens:** Skipping the scale-down step to save time.
**How to avoid:** Always confirm 0 replicas before any data copy step: `kubectl get pods -n {namespace} | grep {app}` should return nothing before proceeding.
**Warning signs:** App starts with corrupted database, config parse errors, or missing data.

### Pitfall 4: CNPG cluster deletion removes the app's database

**What goes wrong:** `kubectl delete cluster` removes the CNPG cluster object AND its PVC (ReclaimPolicy: Delete), leaving the app (linkding, n8n) unable to connect.
**Why it happens:** This is the correct and intended sequence for CNPG storage migration. The app will be down until the new cluster is bootstrapped from backup.
**How to avoid:** Pre-plan the downtime window. Ensure the most recent backup is confirmed complete before deleting the cluster. Keep the app deployment scaled to 0 during CNPG recreation to prevent connection errors in logs.
**Warning signs:** App pods crash-looping with "connection refused" on port 5432 (expected during migration window, not a failure).

### Pitfall 5: CNPG recovery bootstrap fails because backup name is wrong

**What goes wrong:** The `spec.bootstrap.recovery.backup.name` references a Backup object that was garbage-collected or does not exist in the namespace.
**Why it happens:** CNPG's `retentionPolicy: 30d` keeps Backup objects, but if the cluster was deleted and recreated, Backup objects in the namespace may be gone.
**How to avoid:** Before deleting the CNPG cluster, create an on-demand Backup and wait for `phase: completed`. Use that exact Backup object name in the recovery spec.
**Warning signs:** New CNPG cluster stays in `Creating` state, operator logs show "backup not found".

### Pitfall 6: audiobookshelf has 7 PVCs — must migrate all atomically

**What goes wrong:** Migrating audiobookshelf PVCs one-at-a-time with app running between migrations causes the app to lose some mounts mid-operation.
**Why it happens:** audiobookshelf mounts 7 PVCs simultaneously (/config, /metadata, /audiobooks, /podcasts, /ebooks, /comics, /videos). Each must be deleted and recreated as Longhorn.
**How to avoid:** Scale audiobookshelf to 0, then migrate all 7 PVCs in sequence before scaling back up.
**Warning signs:** audiobookshelf pod fails to start with volume mount errors.

---

## Code Examples

### Example: Adding storageClassName to a PVC manifest

```yaml
# Source: Kubernetes PVC spec (apps/base/pgadmin/storage.yaml)
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pgadmin-data-pvc
  namespace: pgadmin
spec:
  storageClassName: longhorn    # Add this line
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

### Example: CNPG storage migration — updated postgresql-cluster.yaml

```yaml
# Source: CNPG v1 Cluster spec (kubectl explain cluster.spec.storage.pvcTemplate)
# databases/staging/linkding/postgresql-cluster.yaml — during migration
spec:
  storage:
    size: 2Gi
    pvcTemplate:
      spec:
        storageClassName: longhorn
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 2Gi
  bootstrap:
    recovery:
      backup:
        name: linkding-backup-YYYYMMDD   # exact name of completed Backup object
```

```yaml
# Post-restore: revert to initdb bootstrap (Cluster won't re-initialize on restart;
# CNPG only runs bootstrap once on new cluster creation)
spec:
  storage:
    size: 2Gi
    pvcTemplate:
      spec:
        storageClassName: longhorn
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 2Gi
  bootstrap:
    initdb:
      database: linkding
      owner: linkding
      secret:
        name: linkding-db-credentials
```

### Example: Triggering an on-demand CNPG backup before migration

```bash
# Trigger immediate backup before cluster deletion
kubectl apply -n linkding -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: pre-migration-backup
spec:
  method: barmanObjectStore
  cluster:
    name: linkding-postgres
EOF

# Wait for completion
kubectl wait backup/pre-migration-backup -n linkding \
  --for=jsonpath='{.status.phase}'=completed \
  --timeout=300s
```

### Example: Scale-down, copy, scale-up sequence

```bash
# Scale down app
kubectl scale deployment/pgadmin -n pgadmin --replicas=0
kubectl wait --for=delete pod -n pgadmin -l app=pgadmin --timeout=60s

# Copy data out (actual data is ~192KB)
mkdir -p /tmp/pgadmin-backup
POD=$(kubectl get pod -n pgadmin -l app=pgadmin -o name 2>/dev/null | head -1)
# Note: if replicas=0, no pod exists — data is on the PV, need a debug pod
# Alternative: mount via debug pod
kubectl run debug-pgadmin --image=busybox --restart=Never \
  --overrides='{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"pgadmin-data-pvc"}}],"containers":[{"name":"debug","image":"busybox","command":["sleep","600"],"volumeMounts":[{"name":"data","mountPath":"/pgadmin-data"}]}]}}' \
  -n pgadmin
kubectl wait --for=condition=Ready pod/debug-pgadmin -n pgadmin --timeout=60s
kubectl cp pgadmin/debug-pgadmin:/pgadmin-data/. /tmp/pgadmin-backup/
kubectl delete pod/debug-pgadmin -n pgadmin

# Delete old PVC and apply updated storage.yaml
kubectl delete pvc pgadmin-data-pvc -n pgadmin
kubectl apply -f apps/base/pgadmin/storage.yaml

# Wait for new Longhorn PVC to bind
kubectl wait pvc/pgadmin-data-pvc -n pgadmin \
  --for=jsonpath='{.status.phase}'=Bound --timeout=120s

# Restore data using another debug pod
kubectl run debug-pgadmin --image=busybox --restart=Never \
  --overrides='{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"pgadmin-data-pvc"}}],"containers":[{"name":"debug","image":"busybox","command":["sleep","600"],"volumeMounts":[{"name":"data","mountPath":"/pgadmin-data"}]}]}}' \
  -n pgadmin
kubectl wait --for=condition=Ready pod/debug-pgadmin -n pgadmin --timeout=60s
kubectl cp /tmp/pgadmin-backup/. pgadmin/debug-pgadmin:/pgadmin-data/
kubectl delete pod/debug-pgadmin -n pgadmin

# Scale back up
kubectl scale deployment/pgadmin -n pgadmin --replicas=1
kubectl wait --for=condition=Ready pod -n pgadmin -l app=pgadmin --timeout=120s

# Verify
kubectl exec -n pgadmin deployment/pgadmin -- ls /var/lib/pgadmin
```

---

## Migration Plan Structure

Based on the roadmap's ordered sequence and the per-app nature of the work, the 15 PVCs across 7 apps map naturally to the following plan groupings:

| Plan | Apps | PVCs | Notes |
|------|------|------|-------|
| Plan 01 | pgadmin | pgadmin-data-pvc (1Gi) | Simplest app, single PVC, good test of procedure |
| Plan 02 | filebrowser | filebrowser-db (1Gi), filebrowser-files (5Gi) | 2 PVCs, both on worker-01 |
| Plan 03 | mealie | mealie-data (1Gi) | Single PVC, control-plane |
| Plan 04 | audiobookshelf | 7 PVCs (1+1+1+5+5+5+5=23Gi allocated) | Must migrate all 7 atomically — scale to 0, migrate all, scale up |
| Plan 05 | linkding | linkding-data-pvc (1Gi) | Single PVC |
| Plan 06 | n8n | n8n-data (2Gi) | Single PVC |
| Plan 07 | CNPG | linkding-postgres-1 (2Gi), n8n-postgresql-cluster-1 (2Gi) | Backup-restore workflow; higher risk, needs confirmed backups first |

Each plan follows the same structure: Git change (storage.yaml) + operational procedure + verification.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Longhorn StorageClass | All new PVCs | Yes | 1.7.3 (default SC) | — |
| kubectl | All migration steps | Yes | v1.33.0 | — |
| CNPG operator | CNPG PVC migration | Yes | 1.24.1 | — |
| Cloudflare R2 backups | CNPG restore | Yes | Backups active <1hr ago | — |
| SSH to worker-01 | Optional debug | Yes | via `ssh homelab-worker1@192.168.1.89` | kubectl exec on debug pod |
| rsync | Data copy (optional alternative) | Yes | 3.2.7 | kubectl cp (preferred) |

**No missing dependencies.** All required infrastructure is in place.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | kubectl (no unit test framework — operational validation only) |
| Config file | none |
| Quick run command | `kubectl get pvc -n {namespace}` (per-app) |
| Full suite command | `kubectl get pvc --all-namespaces \| grep local-path` (phase gate: zero output) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | Notes |
|--------|----------|-----------|-------------------|-------|
| STOR-04 | All app PVCs use Longhorn storageClass | smoke | `kubectl get pvc --all-namespaces -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,SC:.spec.storageClassName' \| grep -v longhorn` | Zero output = pass |
| STOR-04 | Each migrated app is healthy post-migration | smoke | `kubectl get pods -n {namespace} \| grep -v Running` | Zero non-Running pods |
| STOR-05 | CNPG clusters healthy on Longhorn | smoke | `kubectl get cluster --all-namespaces` | Both show "Cluster in healthy state" |
| STOR-05 | CNPG PVCs use Longhorn | smoke | `kubectl get pvc -n linkding linkding-postgres-1 -o jsonpath='{.spec.storageClassName}'` | Output: `longhorn` |

### Sampling Rate

- **Per plan (per app):** `kubectl get pvc -n {namespace}` shows storageClass = longhorn + `kubectl get pods -n {namespace}` shows Running
- **Per wave merge:** Not applicable — each plan is its own wave
- **Phase gate:** `kubectl get pvc --all-namespaces | grep local-path` returns zero lines before `/gsd:verify-work`

### Wave 0 Gaps

None — no test files to create. Validation is entirely via `kubectl` commands against the live cluster.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual `cp` PV directories on host | `kubectl cp` via debug pod | K8s 1.10+ | No SSH access to host needed; works with any provisioner |
| CNPG storage migration via WAL archive stream | CNPG bootstrap.recovery from completed Backup | CNPG 1.x | Simpler and more reliable than streaming; tolerates brief downtime |
| `pv-migrate` tool | kubectl cp + debug pod (for tiny data) | — | pv-migrate adds complexity; for <10MB data, debug pod + kubectl cp is simpler |

---

## Open Questions

1. **pgadmin fsGroup/runAsUser after migration**
   - What we know: pgadmin pod uses no explicit `securityContext.fsGroup` in deployment.yaml (not set explicitly)
   - What's unclear: Whether Longhorn volumes will present with different permissions than local-path volumes, causing pgadmin to fail on startup
   - Recommendation: After scale-up post-migration, check pod logs immediately. If permission denied errors appear, add `initContainer` with `chown` or add `securityContext.fsGroup` to deployment.

2. **Audiobookshelf media content mounts**
   - What we know: `/audiobooks`, `/podcasts`, `/ebooks`, `/comics`, `/videos` PVCs contain only ~4KB (essentially empty). The app may store content here in future.
   - What's unclear: Whether the user has media files stored elsewhere (NFS, external disk) that will be added later
   - Recommendation: Migrate the empty PVCs now. This phase does not need to address NFS/external mounts.

3. **CNPG bootstrap revert after recovery**
   - What we know: CNPG only runs bootstrap once (on cluster creation). After a recovery bootstrap completes, the cluster is in normal operation.
   - What's unclear: Whether leaving `bootstrap.recovery` in the spec (instead of reverting to `initdb`) causes any issues with GitOps reconciliation.
   - Recommendation: Revert to `initdb` form post-restore to keep spec consistent with initial deployment. CNPG ignores bootstrap spec after cluster is initialized.

---

## Sources

### Primary (HIGH confidence)

- `kubectl explain cluster.spec.storage.pvcTemplate` — confirmed `storageClassName` field in CNPG pvcTemplate spec
- `kubectl get pvc --all-namespaces` — live cluster state, all 15 PVCs confirmed local-path
- `kubectl get nodes.longhorn.io -n longhorn-system` — all 3 nodes schedulable, disk availability confirmed
- `kubectl get backup -n linkding`, `kubectl get backup -n n8n` — CNPG backup objects confirmed active
- `kubectl get storageclass` — longhorn is sole default SC, local-path absent
- `.planning/phases/06-install-longhorn-distributed-storage/06-VERIFICATION.md` — Phase 6 verification confirmed all Longhorn prerequisites
- `.planning/STATE.md`, `.planning/ROADMAP.md` — migration order and scope
- `kubectl exec ... du -sh` — actual data sizes in all app PVCs
- `kubectl get pv -o json` — node pinning of all local-path PVs confirmed

### Secondary (MEDIUM confidence)

- CNPG 1.24.1 documentation patterns (bootstrap.recovery) — verified against `kubectl explain` output
- Longhorn PVC migration pattern (scale-down, delete, recreate) — standard Kubernetes storage migration practice, consistent with Longhorn docs

### Tertiary (LOW confidence)

- None

---

## Metadata

**Confidence breakdown:**
- PVC inventory and live state: HIGH — directly queried from live cluster
- Migration procedure (app PVCs): HIGH — standard Kubernetes pattern, data is tiny
- CNPG migration procedure: HIGH — `kubectl explain` confirmed pvcTemplate.storageClassName field; active backups confirmed
- Pitfalls: HIGH — derived from live cluster state and known Kubernetes immutability constraints

**Research date:** 2026-04-06
**Valid until:** 2026-05-06 (Longhorn version; CNPG operator; cluster node state stable)
