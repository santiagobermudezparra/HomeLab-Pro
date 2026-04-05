---
phase: 05-fix-linkding-backup-destination
plan: "01"
subsystem: databases
tags: [cnpg, backup, s3, cloudflare-r2, sops, barman]
dependency_graph:
  requires: []
  provides: [linkding-barman-backup, n8n-barman-backup]
  affects: [databases/staging/linkding, databases/staging/n8n]
tech_stack:
  added: [barman-cloud-backup via CNPG barmanObjectStore]
  patterns: [SOPS-encrypted S3 credentials, Cloudflare R2 as barman destination]
key_files:
  created:
    - databases/staging/linkding/linkding-backup-s3-secret.yaml
    - databases/staging/n8n/n8n-backup-s3-secret.yaml
  modified:
    - databases/staging/linkding/postgresql-cluster.yaml
    - databases/staging/linkding/kustomization.yaml
    - databases/staging/n8n/postgresql-cluster.yaml
    - databases/staging/n8n/kustomization.yaml
decisions:
  - "Cloudflare R2 as backup target — free egress, S3-compatible, barman-cloud-backup compatible"
  - "Shared R2 bucket homelab-postgres-backups with path prefixes /linkding and /n8n"
  - "No region field in barmanObjectStore — R2 rejects requests with region set"
  - "ACCESS_KEY_SECRET as the key name in the secret (not ACCESS_SECRET_KEY)"
metrics:
  duration: "3 minutes"
  completed_date: "2026-04-05"
  tasks_completed: 4
  files_changed: 6
---

# Phase 05 Plan 01: Fix linkding Backup Destination Summary

**One-liner:** CNPG barmanObjectStore S3 backup configured for both linkding and n8n clusters via Cloudflare R2 with SOPS-encrypted credentials.

## What Was Built

Both `linkding-postgres` and `n8n-postgresql-cluster` CNPG Clusters now have a complete `spec.backup.barmanObjectStore` stanza pointing at the Cloudflare R2 bucket `homelab-postgres-backups`, with separate path prefixes (`/linkding` and `/n8n`). SOPS-encrypted S3 credential secrets were created for each namespace. The linkding kustomization was also updated to uncomment `backup-config.yaml` (which was previously disabled). A PR has been opened targeting `main`.

## Tasks

| Task | Name | Status | Commit |
|------|------|--------|--------|
| 1 | Provide S3/R2 credentials | Satisfied (credentials in .env) | — |
| 2 | Create linkding-backup-s3-secret (SOPS-encrypted) | Done | 2282999 |
| 3 | Patch linkding postgresql-cluster.yaml + kustomization | Done | 2282999 |
| 4 | Create n8n-backup-s3-secret (SOPS-encrypted) | Done | 2282999 |
| 5 | Patch n8n postgresql-cluster.yaml + kustomization, commit, open PR | Done | 2282999 |
| 6 | Checkpoint: Verify backups complete after PR merge | Pending human verification | — |

## Validation Results

- `kubectl kustomize databases/staging/linkding/` — exits 0, output contains `kind: Cluster`, `barmanObjectStore`, `kind: ScheduledBackup`, `kind: Secret` (x3)
- `kubectl apply -k databases/staging/linkding/ --dry-run=client` — exits 0
- `kubectl kustomize databases/staging/n8n/` — exits 0, output contains `barmanObjectStore`, `kind: ScheduledBackup`
- `kubectl apply -k databases/staging/n8n/ --dry-run=client` — exits 0
- Both secrets verified with `grep -c 'ENC\[AES256_GCM'` returning 3 (2 stringData fields + 1 MAC)

## Decisions Made

1. **Cloudflare R2 as backup target** — Free egress, no storage class complexity, S3-compatible with barman-cloud-backup. Endpoint format: `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`.
2. **Shared bucket with path prefixes** — Both clusters use `homelab-postgres-backups` with `/linkding` and `/n8n` prefixes. Simpler management than separate buckets.
3. **No `region:` field** — Cloudflare R2 rejects requests that include a region. This is a known pitfall documented in the research file.
4. **Key name `ACCESS_KEY_SECRET`** — Matches the CNPG secret key name pattern used in the plan spec. Do not confuse with `ACCESS_SECRET_KEY`.

## Deviations from Plan

None — plan executed exactly as written. Task 1 (credentials) was pre-satisfied by `.env` file as noted in execution context.

## PR

PR #32: https://github.com/santiagobermudezparra/HomeLab-Pro/pull/32

## Known Stubs

None — all data is wired. The barmanObjectStore destinationPath contains real bucket/account values (no placeholders).

## Pending

Task 6 checkpoint is awaiting human verification:
1. Merge PR #32 to main
2. Wait for FluxCD to sync (~1 min)
3. Verify: `kubectl get backup -n linkding` and `kubectl get backup -n n8n` show `phase: completed`
4. Verify WAL archiving: `kubectl get cluster linkding-postgres -n linkding -o yaml | grep -A5 continuousArchiving`

## Self-Check: PASSED

- databases/staging/linkding/linkding-backup-s3-secret.yaml — FOUND
- databases/staging/n8n/n8n-backup-s3-secret.yaml — FOUND
- databases/staging/linkding/postgresql-cluster.yaml — FOUND (contains barmanObjectStore)
- databases/staging/n8n/postgresql-cluster.yaml — FOUND (contains barmanObjectStore)
- databases/staging/linkding/kustomization.yaml — FOUND (backup-config.yaml uncommented, secret added)
- databases/staging/n8n/kustomization.yaml — FOUND (n8n-backup-s3-secret.yaml added)
- Commit 2282999 — verified
