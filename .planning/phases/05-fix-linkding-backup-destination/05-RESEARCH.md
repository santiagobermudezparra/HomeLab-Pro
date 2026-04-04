# Phase 5: Fix linkding Backup Destination - Research

**Researched:** 2026-04-05
**Domain:** CloudNativePG barmanObjectStore — S3-compatible object storage backup destination
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BACK-02 | linkding `ScheduledBackup` has a `destinationPath` pointing to object storage | barmanObjectStore goes on the Cluster resource (not ScheduledBackup); S3 credentials need SOPS-encrypted Secret in `linkding` namespace |
</phase_requirements>

---

## Summary

Phase 5 adds the missing `spec.backup.barmanObjectStore` stanza to the `linkding-postgres` CloudNativePG Cluster resource so that the existing `linkding-backup` ScheduledBackup can write data to an S3-compatible object store. The ScheduledBackup itself requires no changes — only the Cluster resource needs updating.

The cluster does not currently have MinIO installed and no object store credentials exist in any namespace. The user must therefore choose an external S3-compatible provider (Cloudflare R2, Backblaze B2, or AWS S3). Cloudflare R2 is the recommended choice: free egress, no storage class complexity, compatible with barman-cloud-backup, and consistent with the project's existing Cloudflare infrastructure. Backblaze B2 has a documented issue in CNPG 1.24 (HeadBucket failures in barman 3.x) that has not been fully resolved as of April 2026.

The plan has two artifacts: (1) a new SOPS-encrypted secret file in `databases/staging/linkding/` holding the S3 access key and secret key, and (2) a patch to `databases/staging/linkding/postgresql-cluster.yaml` adding the `spec.backup.barmanObjectStore` block.

**Primary recommendation:** Add `spec.backup.barmanObjectStore` to `linkding-postgres` Cluster pointing at a Cloudflare R2 bucket, with S3 credentials in a SOPS-encrypted `linkding-backup-s3-secret` Secret in the `linkding` namespace.

---

## Project Constraints (from CLAUDE.md)

- Never commit unencrypted secrets to Git — always SOPS-encrypt before committing
- Encrypted regex: `^(data|stringData)$` — only those fields are encrypted
- Age recipient: `age1spwc8lctzldd0ghkkls8jfvzzra7cx95r2zqq6eya84etq65wfgqy2h99p` (from `clusters/staging/.sops.yaml`)
- Base/overlay pattern: base configs reusable, environment-specific in overlays
- Branch from main, never commit directly to main
- Test with `kubectl apply -k ... --dry-run=client` before committing
- Let FluxCD manage reconciliation after PR merge

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| CloudNativePG (CNPG) | 1.24.1 (running) | PostgreSQL cluster + backup orchestration | Already installed; manages `linkding-postgres` cluster |
| barman-cli-cloud | bundled with `ghcr.io/cloudnative-pg/postgresql:17.0` | Executes barman-cloud-backup and barman-cloud-wal-archive | Included in CNPG default PostgreSQL image; no install needed |
| Cloudflare R2 | N/A (SaaS) | S3-compatible object store for backup destination | Free egress; consistent with project's Cloudflare ecosystem; works with barman-cloud S3 API |
| SOPS | 3.10.2 (installed) | Encrypt S3 credentials before committing | Already used across project for all secrets |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Backblaze B2 | N/A (SaaS) | Alternative S3-compatible object store | If R2 is unavailable; note HeadBucket issue in CNPG #7105/#8415 |
| AWS S3 | N/A (SaaS) | Canonical S3 | If cost is not a concern and R2/B2 are ruled out |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Cloudflare R2 | MinIO in-cluster | MinIO requires new HelmRelease, PVC, operator — out of scope for Phase 5; Phase 11 Velero will evaluate |
| Cloudflare R2 | Backblaze B2 | B2 has documented barman compatibility issues (HeadBucket failures); R2 is lower-risk |
| SOPS-encrypted Secret in git | External Secrets Operator | ESO not installed; SOPS is the established project pattern |

---

## Architecture Patterns

### Where barmanObjectStore Lives

**Critical:** `spec.backup.barmanObjectStore` belongs on the **Cluster** resource, NOT on the ScheduledBackup resource. The ScheduledBackup's `spec.method: barmanObjectStore` (default) simply instructs it to use whatever barmanObjectStore is configured on the referenced Cluster.

```
databases/staging/linkding/
├── kustomization.yaml          ← must uncomment backup-config.yaml + add new secret
├── postgresql-cluster.yaml     ← ADD spec.backup.barmanObjectStore HERE
├── backup-config.yaml          ← NO CHANGES NEEDED (already correct)
├── secrets.yaml                ← NO CHANGES NEEDED
└── linkding-backup-s3-secret.yaml  ← NEW: SOPS-encrypted S3 credentials
```

### Pattern 1: barmanObjectStore on Cluster (Cloudflare R2)

```yaml
# Source: https://cloudnative-pg.io/documentation/1.24/appendixes/object_stores/
# In databases/staging/linkding/postgresql-cluster.yaml — ADD to spec:
spec:
  backup:
    barmanObjectStore:
      destinationPath: "s3://BUCKET_NAME/linkding/"
      endpointURL: "https://ACCOUNT_ID.r2.cloudflarestorage.com"
      s3Credentials:
        accessKeyId:
          name: linkding-backup-s3-secret
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: linkding-backup-s3-secret
          key: ACCESS_SECRET_KEY
    retentionPolicy: "30d"
```

**R2 endpointURL format:** `https://<account-id>.r2.cloudflarestorage.com`
The account ID is found in the Cloudflare dashboard under R2 > Overview.

**Region:** R2 does not require a region field. Do NOT add a `region:` key — it will cause an error.

### Pattern 2: S3 Credentials Secret (pre-encryption)

```yaml
# Source: project SOPS pattern from databases/staging/linkding/secrets.yaml
# Create this file BEFORE encrypting:
apiVersion: v1
kind: Secret
metadata:
  name: linkding-backup-s3-secret
  namespace: linkding
type: Opaque
stringData:
  ACCESS_KEY_ID: <r2-access-key-id>
  ACCESS_SECRET_KEY: <r2-secret-access-key>
```

**Encrypt command:**
```bash
sops --age=age1spwc8lctzldd0ghkkls8jfvzzra7cx95r2zqq6eya84etq65wfgqy2h99p \
  --encrypt \
  --encrypted-regex '^(data|stringData)$' \
  --in-place databases/staging/linkding/linkding-backup-s3-secret.yaml
```

### Pattern 3: Kustomization Update (linkding namespace already set at top-level)

The linkding kustomization has `namespace: linkding` at the top level. The new secret does NOT need an inline namespace if the kustomization already sets it — but to be explicit and match the project's pattern (all linkding secrets do have inline namespace in their metadata), set `namespace: linkding` in the secret metadata anyway.

Current kustomization state:
```yaml
# databases/staging/linkding/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: linkding
resources:
  - secrets.yaml
  - postgresql-cluster.yaml
  # - backup-config.yaml    ← UNCOMMENT this
                             # + ADD: - linkding-backup-s3-secret.yaml
```

### Anti-Patterns to Avoid
- **Adding barmanObjectStore to ScheduledBackup:** The ScheduledBackup only has `spec.method`, `spec.cluster.name`, `spec.schedule`, `spec.immediate`, and `spec.backupOwnerReference`. Object store config lives exclusively on the Cluster.
- **Region field for R2/MinIO:** Do not add `region:` for providers that don't require it (R2, MinIO). Adding it incorrectly causes barman-cloud-backup to fail.
- **Committing unencrypted secret:** Create the secret file first, verify it looks correct, THEN run sops encrypt in-place. Never commit without running sops.
- **Using `kubectl create secret --dry-run` output for SOPS:** The `creationTimestamp: null` line in the generated YAML is fine — SOPS encrypts only `data`/`stringData`, not metadata.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| WAL archiving to S3 | Custom pg_basebackup + WAL shipper | barman-cli-cloud (bundled in CNPG image) | barman handles WAL archiving, continuous archiving, restore catalog, retention — thousands of edge cases |
| Credential rotation | Custom secret watcher | SOPS re-encrypt + FluxCD sync | FluxCD decrypts and re-applies on sync; SOPS handles the encryption lifecycle |
| Backup retention | Cron job that deletes old objects | `retentionPolicy: "30d"` on barmanObjectStore | CNPG enforces retention at the barman layer; deletes according to WAL dependency graph (not just age) |

---

## Runtime State Inventory

> Phase 5 is NOT a rename/refactor — this section covers object storage state only.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | No existing backups in linkding namespace — `kubectl get backup -n linkding` returns empty | None — first backup run after fix will populate |
| Live service config | Cloudflare R2: bucket must be manually created via Cloudflare Dashboard before applying manifests | Human creates bucket; no automation available |
| OS-registered state | None | None |
| Secrets/env vars | No S3 credentials exist anywhere in cluster for linkding | Create new SOPS-encrypted secret file |
| Build artifacts | linkding-postgres Cluster image: `ghcr.io/cloudnative-pg/postgresql:17.0` — includes barman-cli-cloud; no install needed | None |

---

## Common Pitfalls

### Pitfall 1: backup-config.yaml Is Still Commented Out
**What goes wrong:** After adding barmanObjectStore to the Cluster, no ScheduledBackup fires because `backup-config.yaml` is still commented out in `databases/staging/linkding/kustomization.yaml`.
**Why it happens:** The kustomization has `# - backup-config.yaml` — this was intentional during Phase 4 while waiting for object storage.
**How to avoid:** The plan must uncomment `- backup-config.yaml` AND add `- linkding-backup-s3-secret.yaml` to the kustomization resources in the same PR.
**Warning signs:** `kubectl get scheduledbackup -n linkding` returns no resources after FluxCD sync.

### Pitfall 2: barmanObjectStore on ScheduledBackup Instead of Cluster
**What goes wrong:** Backup still fails with "no barmanObjectStore section defined on the target cluster".
**Why it happens:** ScheduledBackup does not accept a barmanObjectStore spec — it is set on the Cluster.
**How to avoid:** Only edit `postgresql-cluster.yaml`, not `backup-config.yaml`.
**Warning signs:** `kubectl describe backup -n linkding <name>` shows same error as n8n backups show today.

### Pitfall 3: Cloudflare R2 Bucket Not Created Before Apply
**What goes wrong:** barman-cloud-wal-archive fails with 404/NoSuchBucket on the first WAL file attempt immediately after cluster is updated.
**Why it happens:** The bucket must exist in R2 before CNPG tries to write to it. CNPG does not create the bucket.
**How to avoid:** Human creates the bucket in Cloudflare Dashboard before merging the PR.
**Warning signs:** `kubectl logs -n linkding linkding-postgres-1 -c postgres` shows barman-cloud-wal-archive exit status 1 with "NoSuchBucket".

### Pitfall 4: SOPS Encryption Before Verification
**What goes wrong:** Wrong values encrypted; can't easily diff the plaintext before committing.
**Why it happens:** Encrypting early makes it hard to verify the values are correct.
**How to avoid:** Create the plaintext secret, verify it with `cat`, THEN run sops encrypt in-place. Verify the file has `ENC[AES256_GCM` in stringData fields before committing.
**Warning signs:** `sops -d` on the committed file shows unexpected values.

### Pitfall 5: Continuous Archiving State Change After barmanObjectStore Added
**What goes wrong:** CNPG restarts the PostgreSQL pod when `spec.backup.barmanObjectStore` is added to the Cluster. This is expected but may surprise if monitoring is watched.
**Why it happens:** Adding barmanObjectStore requires PostgreSQL to set `archive_mode=on` (already `on` per live cluster inspection) and configure `archive_command`. CNPG reconciles the running pod.
**How to avoid:** Know this is expected. The live cluster already shows `ContinuousArchivingSuccess` — it will transition to failure briefly then succeed once credentials are correct and bucket exists.
**Warning signs:** Pod restart during reconciliation is normal; not a pitfall to avoid but to expect.

---

## Code Examples

### Complete postgresql-cluster.yaml patch (spec.backup addition)

```yaml
# Source: https://cloudnative-pg.io/documentation/1.24/appendixes/object_stores/
# ADD these lines to databases/staging/linkding/postgresql-cluster.yaml
# under spec: (after the existing storage/bootstrap/postgresql blocks)

  backup:
    barmanObjectStore:
      destinationPath: "s3://BUCKET_NAME/linkding/"
      endpointURL: "https://ACCOUNT_ID.r2.cloudflarestorage.com"
      s3Credentials:
        accessKeyId:
          name: linkding-backup-s3-secret
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: linkding-backup-s3-secret
          key: ACCESS_SECRET_KEY
    retentionPolicy: "30d"
```

### Plaintext secret before SOPS encryption

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: linkding-backup-s3-secret
  namespace: linkding
type: Opaque
stringData:
  ACCESS_KEY_ID: <r2-token-access-key-id>
  ACCESS_SECRET_KEY: <r2-token-secret-access-key>
```

### SOPS encryption (using project age key)

```bash
sops --age=age1spwc8lctzldd0ghkkls8jfvzzra7cx95r2zqq6eya84etq65wfgqy2h99p \
  --encrypt \
  --encrypted-regex '^(data|stringData)$' \
  --in-place databases/staging/linkding/linkding-backup-s3-secret.yaml
```

### Updated kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: linkding
resources:
  - secrets.yaml
  - postgresql-cluster.yaml
  - backup-config.yaml
  - linkding-backup-s3-secret.yaml
```

### Validation commands

```bash
# After FluxCD sync — verify ScheduledBackup is active
kubectl get scheduledbackup -n linkding

# Watch for a successful backup (may take up to 3 AM UTC, or immediate: true fires instantly)
kubectl get backup -n linkding

# Describe the backup to see error details if still failing
kubectl describe backup -n linkding <name>

# Verify WAL archiving is working
kubectl get cluster -n linkding linkding-postgres -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}'
# Expected: True

# Check pod logs for barman activity
kubectl logs -n linkding linkding-postgres-1 -c postgres | grep barman | tail -20
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Separate barman server (standalone) | barman-cloud tools embedded in CNPG PostgreSQL image | CNPG 1.x | No separate barman pod needed; backup runs inside the postgres pod itself |
| ScheduledBackup carries storage config | Cluster carries `spec.backup.barmanObjectStore`; ScheduledBackup only references cluster | CNPG v1 design | Single source of truth for backup destination |
| 6-field Quartz cron schedule | 5-field standard cron (CNPG 1.23+) | CNPG 1.23 | `"0 3 * * *"` is correct; do NOT use 6-field format |

**Note on CNPG barman plugin (v2 architecture):** There is a newer `plugin-barman-cloud` CNPG-I plugin that moves barmanObjectStore configuration to a separate `ObjectStore` CRD. This is NOT installed in this cluster (CNPG 1.24.1 uses the legacy built-in barmanObjectStore on the Cluster spec). Do not use the plugin API — use `spec.backup.barmanObjectStore` directly on the Cluster.

---

## Open Questions

1. **Which S3-compatible provider does the user want to use?**
   - What we know: No provider configured yet; Cloudflare R2 is recommended
   - What's unclear: User preference — R2 requires a Cloudflare account; B2/S3 are alternatives
   - Recommendation: Planner should include a human decision gate or ask the user before the plan executes. If skipping the gate, default to R2 and parameterize (bucket name, account ID, credentials) as human-fill-in placeholders.

2. **Should n8n get the same fix simultaneously?**
   - What we know: n8n backups are also failing with "no barmanObjectStore" — same root cause
   - What's unclear: Phase 5 scope says linkding only (BACK-02)
   - Recommendation: Keep Phase 5 scope to linkding per BACK-02. n8n gets the same fix as a follow-up or can be added to the same PR as a bonus task if user requests.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| kubectl | Apply/verify manifests | Yes | v1.33.0 | — |
| sops | Encrypt S3 credentials secret | Yes | 3.10.2 | — |
| CNPG operator | Reconcile Cluster with barmanObjectStore | Yes | 1.24.1 | — |
| Cloudflare R2 bucket | Backup destination | Must be created manually | — | Use B2 or AWS S3 instead |
| age key for SOPS | Encrypt secret | Yes | in clusters/staging/.sops.yaml | — |
| `kustomize` (standalone) | Build validation | NOT found as standalone binary | — | Use `kubectl kustomize` instead |

**Missing dependencies with no fallback:**
- Cloudflare R2 bucket (or chosen S3 bucket): must exist before manifests are applied. This is a human prerequisite step before the automation tasks run.

**Missing dependencies with fallback:**
- `kustomize` standalone: use `kubectl kustomize databases/staging/linkding/` instead of `kustomize build databases/staging/linkding/`

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | kubectl (live cluster verification) + kustomize build (static) |
| Config file | none — infrastructure validation, not unit tests |
| Quick run command | `kubectl kustomize databases/staging/linkding/ \| grep -c "kind:"` |
| Full suite command | see Phase Requirements mapping below |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | Notes |
|--------|----------|-----------|-------------------|-------|
| BACK-02 | linkding ScheduledBackup has a destinationPath pointing to object storage | smoke | `kubectl get backup -n linkding -o jsonpath='{.items[0].spec.backupOwnerReference}'` | Requires cluster to have synced |
| BACK-02 | Cluster has barmanObjectStore with destinationPath set | static | `kubectl kustomize databases/staging/linkding/ \| grep -A5 "barmanObjectStore"` | Automated — no cluster needed |
| BACK-02 | ScheduledBackup is active (not commented out) | static | `kubectl kustomize databases/staging/linkding/ \| grep -c "ScheduledBackup"` | Should return 1 |
| BACK-02 | S3 secret exists and is SOPS-encrypted | static | `grep 'ENC\[AES256_GCM' databases/staging/linkding/linkding-backup-s3-secret.yaml` | Automated pre-commit check |
| BACK-02 | Backup completes successfully with object storage destination | live/manual | `kubectl get backup -n linkding` showing phase: completed | Requires 1 backup cycle after FluxCD sync |
| BACK-02 | WAL archiving is working | live/automated | `kubectl get cluster -n linkding linkding-postgres -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}'` returns True | Run after FluxCD sync |

### Sampling Rate
- **Per task commit:** `kubectl kustomize databases/staging/linkding/ | grep "barmanObjectStore"` (static check)
- **Per wave merge:** `kubectl apply -k databases/staging/linkding/ --dry-run=client`
- **Phase gate (human-verify checkpoint):** `kubectl get backup -n linkding` shows at least one backup with phase: completed and no "no barmanObjectStore" error

### Wave 0 Gaps
- None — no test framework install needed; all validation is kubectl/kustomize commands against the running cluster

---

## Sources

### Primary (HIGH confidence)
- `https://cloudnative-pg.io/documentation/1.24/backup_barmanobjectstore/` — barmanObjectStore spec, retention policy, compression
- `https://cloudnative-pg.io/documentation/1.24/appendixes/object_stores/` — S3, MinIO, DigitalOcean Spaces examples; endpointURL patterns
- `https://cloudnative-pg.io/documentation/1.24/backup/` — ScheduledBackup vs Cluster relationship; `spec.method` field
- Live cluster inspection via `kubectl` — CNPG version 1.24.1 confirmed; linkding cluster status; no MinIO installed; backup failure error message

### Secondary (MEDIUM confidence)
- WebSearch result: Cloudflare R2 endpointURL format `https://<account-id>.r2.cloudflarestorage.com` — cross-referenced against Cloudflare R2 docs pattern
- `https://ezyinfra.dev/blog/cloudnativepg-ha-setup` — MinIO barmanObjectStore YAML example

### Tertiary (LOW confidence — for reference only)
- GitHub issue `cloudnative-pg/cloudnative-pg#7105` and `#8415` — Backblaze B2 HeadBucket failures in barman 3.x; flags B2 as higher-risk option

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — CNPG 1.24.1 verified live; barmanObjectStore spec from official docs
- Architecture: HIGH — Cluster vs ScheduledBackup placement confirmed from official docs + live error message
- Pitfalls: HIGH — Pitfall 1 (commented backup-config.yaml) confirmed by live kustomization inspection; Pitfall 2 confirmed by live backup error message
- Provider recommendation: MEDIUM — R2 compatibility confirmed by community examples; no official CNPG 1.24 R2 documentation exists

**Research date:** 2026-04-05
**Valid until:** 2026-05-05 (stable tech; CNPG API changes slowly)
