# Phase 4: n8n Database Backup — Research

**Researched:** 2026-04-05
**Domain:** CloudNativePG ScheduledBackup CRD
**Confidence:** HIGH

---

## Summary

Phase 4 adds a `ScheduledBackup` resource for the n8n PostgreSQL cluster. The deliverable is one
new file (`databases/staging/n8n/backup-config.yaml`) and one line added to
`databases/staging/n8n/kustomization.yaml`. Everything needed to implement this phase already
exists in the repository as a direct template: `databases/staging/linkding/backup-config.yaml`.

The linkding ScheduledBackup has no `destinationPath` and no object-storage credentials — it is a
pure CRD scheduling resource that records `Backup` objects in Kubernetes but does not persist data
off-node. BACK-01 only requires "a `ScheduledBackup` resource configured" — it does not require a
functioning remote destination. Phase 5 (BACK-02) is the phase that adds `destinationPath` to
linkding; that work is deliberately deferred. Mirroring linkding's current (no-destination) pattern
for n8n is intentional and consistent with the roadmap.

Important caveat: a ScheduledBackup without `barmanObjectStore` configured in the cluster spec
will fail at runtime with an error such as "cannot proceed with the backup as the cluster has no
backup section." The Backup objects will be created on schedule but will immediately fail. This is
the same state linkding is in today. BACK-01 is satisfied by the presence of the resource; actual
successful backup completion is tracked under BACK-02 (linkding fix) and will be extended to n8n
afterwards.

**Primary recommendation:** Copy the linkding `backup-config.yaml` verbatim, change `name`,
`namespace`, and `cluster.name` to the n8n equivalents, then add `backup-config.yaml` to the n8n
kustomization. No other files need changing.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BACK-01 | n8n CloudNativePG cluster has a `ScheduledBackup` resource configured | ScheduledBackup CRD is already in-cluster via cloudnative-pg HelmRelease v0.22.x. Cluster name `n8n-postgresql-cluster` in namespace `n8n` is confirmed. Pattern from linkding is a direct template. |
</phase_requirements>

---

## Key Facts Discovered

### n8n Cluster Identity
| Property | Value |
|----------|-------|
| Cluster kind | `postgresql.cnpg.io/v1 Cluster` |
| Cluster name | `n8n-postgresql-cluster` |
| Namespace | `n8n` |
| Source file | `databases/staging/n8n/postgresql-cluster.yaml` |

### Linkding Backup Template (exact content to mirror)
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: linkding-backup
  namespace: linkding
spec:
  schedule: "0 3 * * *"
  immediate: true
  cluster:
    name: linkding-postgres
  backupOwnerReference: cluster
```

The linkding kustomization has `# - backup-config.yaml` commented out — the file exists but is
not yet active in the kustomization. The n8n kustomization has no such entry at all.

### CloudNativePG Operator Version
- HelmRelease: `cloudnative-pg` chart version `0.22.x` in namespace `cnpg-system`
- CNPG operator v0.22.x corresponds to CloudNativePG operator release series; CRD
  `ScheduledBackup` is stable in this version.

### Cron Format
CloudNativePG's `schedule` field uses a **5-field standard cron** expression (not 6-field Go cron).
The linkding template uses `"0 3 * * *"` — daily at 03:00 UTC. This is correct.
Source: confirmed from the existing linkding `backup-config.yaml` that is already in-cluster and
accepted by the operator.

### backupOwnerReference Field
- `cluster` — the PostgreSQL Cluster object owns the created Backup objects (Backup resources are
  GC'd if the cluster is deleted).
- `self` — the ScheduledBackup resource owns the Backups.
- `none` — no ownership.
The linkding template uses `cluster`; mirror this for n8n.

### Object Storage Situation
There is **no MinIO or S3 configuration anywhere in this cluster**. No `barmanObjectStore`,
`destinationPath`, `endpointURL`, or S3 credentials exist in any current manifest. This confirms
that Phase 4 does not configure object storage — that is Phase 5's scope (and it will need new
infrastructure decisions before implementation).

### Runtime Behavior Without destinationPath
A ScheduledBackup without a `barmanObjectStore` configured in the Cluster spec will create Backup
CRD objects on schedule, but each Backup will fail immediately with a "cluster has no backup
section" error. The resource is still useful: it records intent, tests the scheduling mechanism,
and ensures the CRD is present. This matches the linkding current state, which the roadmap
explicitly notes as "no destinationPath (backups go nowhere)."

---

## Standard Stack

### Core
| Resource | Version | Purpose | Notes |
|----------|---------|---------|-------|
| `ScheduledBackup` CRD | `postgresql.cnpg.io/v1` | Schedule periodic CNPG backups | Installed via cloudnative-pg HelmRelease v0.22.x |
| Kustomize | native (FluxCD) | Include new file in resources list | No new tooling needed |

### No New Dependencies
This phase requires zero new controllers, operators, secrets, or external services.

---

## Architecture Patterns

### Recommended File Structure (after phase)
```
databases/staging/n8n/
├── backup-config.yaml      # NEW — ScheduledBackup resource
├── kustomization.yaml      # MODIFIED — add backup-config.yaml to resources
├── postgresql-cluster.yaml # unchanged
└── secrets.yaml            # unchanged
```

### Pattern: Mirror Linkding ScheduledBackup
**What:** Create a `ScheduledBackup` that points to the n8n cluster. No backup destination needed.
**When to use:** CNPG operator is already installed; object storage is not yet configured.
**Example:**
```yaml
# Source: mirrors databases/staging/linkding/backup-config.yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: n8n-backup
  namespace: n8n
spec:
  schedule: "0 3 * * *"
  immediate: true
  cluster:
    name: n8n-postgresql-cluster
  backupOwnerReference: cluster
```

### Pattern: Kustomization Update
Add `backup-config.yaml` as the last entry in the resources list (after `postgresql-cluster.yaml`):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - secrets.yaml
  - postgresql-cluster.yaml
  - backup-config.yaml
```

Note: The kustomization has no `namespace:` field set at the top level (unlike linkding which
has `namespace: linkding`). The namespace is declared in the ScheduledBackup manifest itself, so
this is fine.

### Anti-Patterns to Avoid
- **Do not add `namespace: n8n` at the kustomization level** — the existing kustomization does
  not have it, and the namespace is already in the resource manifests. Adding it would be a
  diff inconsistency.
- **Do not configure `barmanObjectStore` in this phase** — object storage is Phase 5+ scope.
- **Do not use a 6-field cron expression** — CloudNativePG uses standard 5-field cron, not Go's
  6-field format. `"0 3 * * *"` is correct.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Backup scheduling | Custom CronJob + pg_dump script | CloudNativePG `ScheduledBackup` | CNPG handles WAL archiving, point-in-time recovery, consistent snapshots, and cluster lifecycle |
| Backup retention | Manual cleanup jobs | `backupOwnerReference: cluster` | CNPG garbage-collects Backup objects when cluster is deleted |

---

## Common Pitfalls

### Pitfall 1: Backup Fails Immediately (Expected)
**What goes wrong:** `kubectl get backup -n n8n` shows Backup objects with `Failed` status
**Why it happens:** The Cluster has no `backup.barmanObjectStore` configured, so CNPG cannot
write backup data anywhere.
**How to avoid:** This is expected for Phase 4. Do not treat Failed Backups as a bug — it is the
same state as linkding today. The Done criterion says "shows at least one completed backup" which
requires Phase 5 (object storage) to be completed first.
**Warning signs:** If no Backup objects appear at all, the ScheduledBackup was not created or
the `immediate: true` did not trigger.

**CRITICAL NOTE on Done Criterion:** The ROADMAP says "Done when: `kubectl get backup -n n8n`
shows at least one completed backup." This cannot be achieved without a backup destination.
Phase 4 can only satisfy the first half: "`kubectl get scheduledbackup -n n8n` shows the backup
scheduled." The "completed backup" part requires Phase 5 work (object storage). The planner
should scope the verification accordingly.

### Pitfall 2: Wrong Cluster Name
**What goes wrong:** ScheduledBackup references wrong cluster name, CNPG rejects or ignores it.
**Why it happens:** Typo or using linkding name without updating.
**How to avoid:** Cluster name is `n8n-postgresql-cluster` (verified in
`databases/staging/n8n/postgresql-cluster.yaml` line 4).

### Pitfall 3: Kustomization Namespace Mismatch
**What goes wrong:** Adding `namespace: n8n` to the kustomization file when it was not there before
changes the effective namespace for all resources.
**Why it happens:** Cargo-culting from the linkding kustomization which has `namespace: linkding`.
**How to avoid:** The n8n kustomization currently has no top-level `namespace:` field. Each
resource already declares its own namespace. Do not add it.

---

## Code Examples

### Complete backup-config.yaml for n8n
```yaml
# Source: mirrors databases/staging/linkding/backup-config.yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: n8n-backup
  namespace: n8n
spec:
  # Schedule: Daily at 3 AM
  schedule: "0 3 * * *"

  # Backup immediately on creation
  immediate: true

  # Reference to the cluster
  cluster:
    name: n8n-postgresql-cluster

  # Retention policy
  backupOwnerReference: cluster
```

### Updated kustomization.yaml for n8n
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - secrets.yaml
  - postgresql-cluster.yaml
  - backup-config.yaml
```

### Verification Commands
```bash
# Verify ScheduledBackup exists (satisfies first half of Done criterion)
kubectl get scheduledbackup -n n8n

# Verify Backup objects are being created (will be Failed status until Phase 5)
kubectl get backup -n n8n

# Check what error Backup objects report (expected: no backup section)
kubectl describe backup -n n8n | grep -A5 "Status:"

# Validate kustomization builds cleanly before applying
kustomize build databases/staging/n8n/
```

---

## Environment Availability

Step 2.6: SKIPPED — this phase is purely a Kubernetes manifest addition. No new external tools,
services, CLIs, or runtimes are required beyond the already-running CloudNativePG operator.

---

## Runtime State Inventory

Step 2.5: SKIPPED — this is a greenfield addition (new file creation), not a rename or refactor.
No existing runtime state is affected.

---

## Validation Architecture

**nyquist_validation is enabled** (from `.planning/config.json`).

### Test Framework
| Property | Value |
|----------|-------|
| Framework | kubectl / kustomize (infrastructure validation, no unit test framework) |
| Config file | none — validation is live cluster inspection |
| Quick run command | `kustomize build databases/staging/n8n/` |
| Full suite command | `kubectl get scheduledbackup -n n8n && kubectl get backup -n n8n` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BACK-01 | ScheduledBackup resource exists in n8n namespace | smoke | `kubectl get scheduledbackup -n n8n` | ❌ Wave 0 (create backup-config.yaml) |
| BACK-01 | kustomize build succeeds with new file | smoke | `kustomize build databases/staging/n8n/` | ❌ Wave 0 |
| BACK-01 | Backup objects appear after `immediate: true` trigger | smoke | `kubectl get backup -n n8n` | ❌ Wave 0 |

**Note:** Backup objects will show `Failed` status — this is expected until Phase 5. The test
verifies existence of objects, not successful completion.

### Sampling Rate
- **Per task commit:** `kustomize build databases/staging/n8n/`
- **Per wave merge:** `kubectl get scheduledbackup -n n8n`
- **Phase gate:** ScheduledBackup resource exists in cluster (Failed backup status is acceptable)

### Wave 0 Gaps
- [ ] `databases/staging/n8n/backup-config.yaml` — the entire deliverable of this phase
- [ ] Line added to `databases/staging/n8n/kustomization.yaml`

*(No test framework or fixture files needed — validation is kubectl/kustomize commands only)*

---

## Open Questions

1. **Done Criterion Scoping**
   - What we know: The ROADMAP Done criterion says "kubectl get backup -n n8n shows at least one
     completed backup" — completed backups require object storage, which is Phase 5+ scope.
   - What's unclear: Was the Done criterion written assuming Phase 5 would be done first, or is
     it aspirational for Phase 4?
   - Recommendation: The planner should split the Done criterion — Phase 4 verifies only
     "ScheduledBackup exists and is scheduled." The "completed backup" gate belongs to a future
     phase when object storage is configured.

2. **Linkding kustomization inconsistency**
   - What we know: `databases/staging/linkding/kustomization.yaml` has `# - backup-config.yaml`
     commented out, even though the file exists and is presumably ready to use.
   - What's unclear: Is this intentional (waiting for Phase 5 to uncomment it), or was it
     accidentally left commented?
   - Recommendation: Leave linkding kustomization untouched in Phase 4. Phase 5 will address it.

---

## Sources

### Primary (HIGH confidence)
- `databases/staging/linkding/backup-config.yaml` — direct template, already in-cluster and
  accepted by the CNPG operator
- `databases/staging/n8n/postgresql-cluster.yaml` — cluster name and namespace confirmed
- `databases/staging/n8n/kustomization.yaml` — current state of n8n kustomization confirmed
- `infrastructure/controllers/base/cloudnative-pg/release.yaml` — CNPG operator version 0.22.x
- CloudNativePG documentation (backup page, v1.24) — ScheduledBackup spec fields confirmed

### Secondary (MEDIUM confidence)
- WebSearch results confirming ScheduledBackup behavior without barmanObjectStore (error message
  "cannot proceed with the backup as the cluster has no backup section")
- CloudNativePG GitHub issues confirming Backup objects fail without destination configured

---

## Project Constraints (from CLAUDE.md)

| Directive | Impact on Phase |
|-----------|----------------|
| Never commit unencrypted secrets to Git | Not applicable — no new secrets in this phase |
| Always use SOPS to encrypt before committing | Not applicable — no secrets |
| Follow base/overlay pattern | Not applicable — databases/ does not follow app base/overlay; all content is in `databases/staging/` |
| Branch from main, never commit directly | All changes on feature branch via PR |
| Test with `--dry-run=client` first | Use `kustomize build` for manifest validation |
| All secrets SOPS-encrypted | No secrets needed for this phase |

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — CNPG CRD is already in-cluster, linkding template is proven
- Architecture: HIGH — two files, exact content known, no ambiguity
- Pitfalls: HIGH — verified from existing linkding state and CNPG documentation
- Done criterion: MEDIUM — the "completed backup" criterion cannot be met without Phase 5

**Research date:** 2026-04-05
**Valid until:** 2026-05-05 (stable CNPG CRD, no fast-moving dependencies)
