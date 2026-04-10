---
gsd_state_version: 1.0
milestone: v2.5.1
milestone_name: milestone
status: verifying
stopped_at: "Completed 10-02-PLAN.md (SKILL.md update + PR #58 opened)"
last_updated: "2026-04-10T23:09:35.716Z"
progress:
  total_phases: 12
  completed_phases: 9
  total_plans: 22
  completed_plans: 22
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-04)

**Core value:** Every stateful app survives any single node failure without data loss
**Current focus:** Phase 10 — NetworkPolicies — Per-Namespace Isolation
**Milestone:** v1 — Cluster Hardening & Resilience

## Current Phase

**Phase 4: n8n Database Backup**
Status: Complete — Verification checkpoint approved
Stopped at: Completed 10-02-PLAN.md (SKILL.md update + PR #58 opened)
Next action: `/gsd:plan-phase 5`

## Key Decisions (Phase 01)

- FluxCD apps Kustomization now depends on `databases`, completing bootstrap chain: `infrastructure-controllers -> databases -> apps`
- No `wait: true` or healthChecks added to apps.yaml — minimal change sufficient, out of scope for this phase

## Key Decisions (Phase 06, Plan 01)

- Longhorn v1.7.3 iscsi-installer DaemonSet deployed as permanent fixture (not Job) so new nodes automatically get open-iscsi
- Staging overlay has no secrets — iscsi-installer requires no credentials, simpler than cert-manager overlay
- Manifests follow base/overlay pattern matching cert-manager and cloudnative-pg exactly

## Key Decisions (Phase 06, Plan 02)

- Longhorn 1.7.3 version pinned (research date 2026-04-05); re-verify if >30 days before deploying
- Both replica count fields required: `persistence.defaultClassReplicaCount: 2` (K8s StorageClass parameters) AND `defaultSettings.defaultReplicaCount: "2"` (must be string, Longhorn UI default)
- Ingress section omitted from release.yaml — handled in Plan 03 overlay (consistent with linkding pattern)
- ServiceMonitor label `release: kube-prometheus-stack` matches live cluster's serviceMonitorSelector confirmed via kubectl
- FluxCD reconciliation and smoke tests are post-merge concerns (GitOps constraint: FluxCD tracks main branch only)

## Key Decisions (Phase 06, Plan 03)

- No TLS on Longhorn UI ingress — internal-only operator dashboard, cert-manager annotation intentionally omitted
- Matched linkding ingress pattern exactly (same spec structure: ingressClassName: traefik, pathType: Prefix, path: /)
- Standalone ingress.yaml placed in staging overlay (not base) — routing config is environment-specific per established convention
- Traefik LAN IP is 192.168.1.115; browser access requires /etc/hosts entry on each workstation

## Key Decisions (Phase 07, Plan 01)

- Proactively chown restored files to app UID (5050:5050 for pgadmin) in debug pod before scale-up — prevents permission denied errors; `kubectl cp` preserves local user ownership not container UID
- Debug pod restore + chown pattern validated: copy data in via busybox debug pod, fix ownership to app UID, delete pod, then scale up app — pgadmin started cleanly on first attempt
- PVC migration procedure confirmed end-to-end: scale-to-0 → debug pod + kubectl cp out → delete PVC → apply updated storage.yaml → wait Bound → debug pod + kubectl cp in + chown → delete pod → scale-to-1

## Key Decisions (Phase 07, Plan 03)

- mealie linuxserver image uses UID 911 (abc user) — chown -R 911:911 applied after kubectl cp restore; kubectl cp does not preserve container UID ownership
- Chown pattern confirmed again across apps: pgadmin=5050, mealie=911; always identify app UID before PVC migration

## Key Decisions (Phase 07, Plan 04)

- All 7 audiobookshelf PVCs migrated atomically in one scale-to-0 window — app mounts all 7 simultaneously, partial migration would cause mount failures
- Only config (SQLite DB, 320KB) and metadata (logs/cache/backups, 80KB) needed backup; 5 empty media PVCs (audiobooks, podcasts, ebooks, comics, videos) deleted and recreated fresh
- chown -R 99:100 required for lscr.io/linuxserver/audiobookshelf — runs as UID 99 (nobody), GID 100 (users)
- storage.yaml has no namespace metadata — always apply PVC manifests with explicit `-n <namespace>` flag to avoid routing to wrong context namespace

## Key Decisions (Phase 07, Plan 05)

- linkding runs as UID 1000 (sethcottle/linkding image default) — chown -R 1000:1000 applied after kubectl cp restore
- storage.yaml has no namespace metadata — used explicit -n linkding flag on all kubectl apply/delete commands

## Key Decisions (Phase 10, Plan 01)

- Traefik allow rule uses combined namespaceSelector+podSelector (single from-entry, AND semantics) to restrict to Traefik pods in kube-system only — not all kube-system pods
- CNPG allow-cnpg-controller targets `cnpg.io/podRole: instance` pods specifically, not all pods in the namespace
- xm-spotify-sync allow-same-namespace covers cloudflared (same ns), allow-traefik-ingress covers Traefik — no separate cloudflared policy needed
- flux-system NetworkPolicies left untouched — they exist imperatively in cluster (not in git); SEC-05 is preservation, not creation

## Key Decisions (Phase 07, Plan 07)

- CNPG WAL archive check bypass: when new cluster has same name and same backup destinationPath as old cluster, `barman-cloud-check-wal-archive` fails ("Expected empty archive"); workaround: omit backup section during recovery cluster creation (no WAL check without backup section), re-add backup section via `kubectl apply` after cluster reaches healthy state
- CNPG pvcTemplate is a flat PVC spec — `storageClassName` goes directly under `pvcTemplate`, NOT under `pvcTemplate.spec` (rejected as "unknown field")
- Use `bootstrap.recovery.source` with `externalClusters` (not `bootstrap.recovery.backup.name`) for CNPG migrations where cluster name and backup path are the same — external cluster name must match original server name in R2
- CNPG `kubectl get backup` is ambiguous with Longhorn — use `kubectl get backups.postgresql.cnpg.io` to query CNPG backup objects specifically

## Phase Progress

| Phase | Name | Status |
|-------|------|--------|
| 1 | Fix FluxCD Bootstrap Race | ✓ Complete |
| 2 | Resource Limits — audiobookshelf | ○ Pending |
| 3 | Grafana Password to SOPS Secret | ○ Pending |
| 4 | n8n Database Backup | ✓ Complete |
| 5 | Fix linkding Backup Destination | ○ Pending |
| 6 | Install Longhorn Storage | ○ Pending |
| 7 | Migrate PVCs to Longhorn | ✓ Complete (Plans 01-07 complete, PR #39 open) |
| 8 | Balance Workloads to Workers | ○ Pending |
| 9 | Cilium CNI Migration | ○ Pending |
| 10 | NetworkPolicies per Namespace | ◑ In Progress (Plan 01 complete) |
| 11 | Velero Full Backup | ○ Pending |
| 12 | Headlamp Dashboard | ○ Pending |

## Cluster Snapshot (2026-04-04)

- **FluxCD**: v2.5.1, all 7 kustomizations synced at main@sha1:616ba732
- **K3s**: v1.30.0+k3s1 on all 3 nodes (Ubuntu 24.04)
- **Control-plane**: 11% CPU, 28% RAM (7836Mi/28GB), 21% disk (33GB/167GB)
- **Worker-01**: 0% CPU, 10% RAM — underutilized
- **Worker-02**: 0% CPU, 6% RAM — joined 18h ago, nearly empty
- **Storage**: 1 StorageClass (local-path), 11 PVCs total, all node-pinned
- **Monitoring**: kube-prometheus-stack v66.2.2, all healthy
- **HelmReleases**: 3 total, all True/healthy

## Key Context for Resuming

- Branch convention: `feat/phase-N-<slug>` off `feat/homelab-improvement`
- All secrets must be SOPS-encrypted before commit
- `apps/staging/kustomization.yaml` — homarr is commented out intentionally
- cert-manager-cainjector has 17100 restarts — monitor but not blocking
- Phase 9 (Cilium) is the highest-risk phase — requires maintenance window, node config changes

---
*State initialized: 2026-04-04*
