---
plan: 05-01
phase: 05-fix-linkding-backup-destination
status: completed
completed: 2026-04-05
---

## What Was Built

Wired `barmanObjectStore` S3 backup destinations to both `linkding-postgres` and `n8n-postgresql-cluster` CloudNativePG Clusters, routing daily backups to Cloudflare R2.

## Key Files

### Created
- `databases/staging/linkding/linkding-backup-s3-secret.yaml` — SOPS-encrypted R2 credentials for linkding barman-cloud-backup
- `databases/staging/n8n/n8n-backup-s3-secret.yaml` — SOPS-encrypted R2 credentials for n8n barman-cloud-backup

### Modified
- `databases/staging/linkding/postgresql-cluster.yaml` — added `spec.backup.barmanObjectStore` → `s3://homelab-postgres-backup/linkding`
- `databases/staging/linkding/kustomization.yaml` — uncommented `backup-config.yaml`, added `linkding-backup-s3-secret.yaml`
- `databases/staging/n8n/postgresql-cluster.yaml` — added `spec.backup.barmanObjectStore` → `s3://homelab-postgres-backup/n8n`
- `databases/staging/n8n/kustomization.yaml` — added `n8n-backup-s3-secret.yaml`

## Decisions

- **Shared bucket, separate prefixes**: Both clusters use `homelab-postgres-backup` R2 bucket with `/linkding` and `/n8n` prefixes
- **Bucket name fix**: Initial config used `homelab-postgres-backups` (with trailing s); corrected to `homelab-postgres-backup` to match the actual R2 bucket name
- **No region field**: Cloudflare R2 does not require a region field in barmanObjectStore
- **gzip compression**: WAL and data compression both set to gzip

## Verification

- `kubectl get backup linkding-manual-backup-01 -n linkding` → `phase: completed`
- `kubectl get backup n8n-manual-backup-01 -n n8n` → `phase: completed`
- `ContinuousArchiving: True` on both clusters
- `kubectl kustomize databases/staging/linkding/` exits 0
- `kubectl kustomize databases/staging/n8n/` exits 0

## Issues Encountered

- Bucket name typo in `.env` (`homelab-postgres-backups` vs actual `homelab-postgres-backup`) caused first backup attempt to fail with `Bucket does not exist`. Fixed in PR #33.
