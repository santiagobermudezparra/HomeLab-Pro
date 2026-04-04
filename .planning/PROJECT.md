# HomeLab-Pro Improvement

## What This Is

A production-grade K3s homelab running on 3 nodes (1 control-plane + 2 workers) managed via
FluxCD GitOps. It hosts personal services (audiobookshelf, n8n, mealie, linkding, filebrowser,
homepage, pgadmin, xm-spotify-sync) with Cloudflare Tunnels for external access and
kube-prometheus-stack for monitoring. This project drives a structured improvement roadmap to
harden, balance, and scale the cluster from its current working-but-fragile state into a
genuinely resilient homelab.

## Core Value

Every stateful app survives any single node failure without data loss.

## Requirements

### Validated

- ✓ FluxCD GitOps managing all cluster state — existing, working
- ✓ Cloudflare Tunnels for external access — existing, working
- ✓ SOPS + age secret encryption — existing, working
- ✓ kube-prometheus-stack monitoring — existing, working
- ✓ CloudNativePG for linkding and n8n databases — existing, working
- ✓ cert-manager with DNS-01 and HTTP-01 issuers — existing, working
- ✓ Renovate bot for dependency updates — existing, working (intermittent errors)

### Active

- [ ] FluxCD dependsOn ordering fixed (apps race with infra on bootstrap)
- [ ] All app deployments have resource requests and limits
- [ ] All image tags pinned (no :latest in production)
- ✓ Grafana admin password stored as SOPS-encrypted secret — Validated in Phase 3
- [ ] n8n database has scheduled backup config
- [ ] Linkding backup has configured object-storage destination
- [ ] Longhorn distributed storage installed and set as default StorageClass
- [ ] All stateful PVCs migrated from local-path to Longhorn
- [ ] Worker-02 (new node, 18h old) receives workload proportional to its capacity
- [ ] Renovate external-host-error resolved
- [ ] Cilium replaces Flannel as CNI
- [ ] NetworkPolicies isolate each app namespace
- [ ] Velero backs up all namespaces + PVCs to object storage
- [ ] Web dashboard (Headlamp) deployed for cluster visibility

### Out of Scope

- Radarr/*arr media stack — lifestyle feature, not infrastructure hardening (add separately anytime)
- Multi-cluster / production environment — single staging cluster only for now
- Kubernetes upgrade (v1.30.0+k3s1) — stable, not blocking anything
- Homarr — intentionally disabled (homepage is active replacement)
- External auth (Authentik/Authelia) — not in this milestone

## Context

### Cluster State (diagnosed 2026-04-04)

| Node | Role | CPU | RAM | Disk | Current Load |
|------|------|-----|-----|------|-------------|
| santi-standard-pc-i440fx-piix-1996 | control-plane | 8c | 28GB | 167GB (21% used) | 11% CPU, 28% RAM — OVERLOADED with pods |
| homelab-worker-01 | worker | 6c | 16GB | 244GB | 0% CPU, 10% RAM |
| homelab-worker-02 | worker | 4c | 15.7GB | 244GB | 0% CPU, 6% RAM — 18h old, barely used |

### Storage (critical issue)

Only one StorageClass exists: `local-path` (default). All 11 PVCs are local-path:

- **Control-plane node**: linkding-data-pvc, audiobookshelf (3 PVCs), mealie-data, linkding-postgres-1
- **Worker-01**: n8n-data, n8n-postgresql-cluster-1, pgadmin-data-pvc, filebrowser-db, filebrowser-files

PVCs are pinned to one node via nodeAffinity. Pod scheduling distributes across nodes, but data
does NOT follow — a node failure means that app's data is inaccessible until the node recovers.

### Known Issues

- `dependsOn` commented out in `clusters/staging/apps.yaml` — race condition on fresh bootstrap
- audiobookshelf deployment has no resource requests or limits
- n8n uses `n8nio/n8n:latest` (should be pinned)
- cloudflared uses `cloudflare/cloudflared:latest` (should be pinned)
- Grafana admin password `watary` hardcoded in HelmRelease values (not a Secret)
- n8n CNPG cluster has no ScheduledBackup configured
- linkding backup config has no `destinationPath` (backups go nowhere)
- Renovate: `external-host-error` on runs from 2d ago (recent hourly runs completing OK)
- NetworkPolicies: zero isolation between app namespaces (only flux-system has them)
- Worker-02 joined 18h ago — no workloads migrated to it yet

### What's Working Well

- All pods Running/Completed, zero Warning events in the cluster
- FluxCD synced on all 7 kustomizations at main@sha1:616ba732
- All 3 HelmReleases (cert-manager, cloudnative-pg, kube-prometheus-stack) healthy
- Cloudflare Tunnels all healthy (2 replicas each app)
- cert-manager-cainjector has 17100 restarts — worth monitoring but not crashing

## Constraints

- **No breaking changes**: Every phase must leave the cluster in a working state — no big-bang migrations
- **FluxCD GitOps**: All changes go through Git → PR → FluxCD sync, never direct kubectl apply to main
- **SOPS encryption**: All secrets encrypted before commit, no plaintext secrets in git
- **K3s compatibility**: Changes must be compatible with k3s v1.30.0 and its built-in components
- **Single disk per node**: No raw block devices available for Ceph OSDs — Longhorn (directory-based) is the right storage choice
- **Branch workflow**: All changes on feature branches, PRs to main — never commit directly to main

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Longhorn over Rook-Ceph | No raw block devices; Longhorn works with directories; lighter RAM footprint (~500MB vs ~2GB); designed for k3s | — Pending |
| Cilium over Calico | Better eBPF performance; Hubble observability built-in; active development; k3s integration guides | — Pending |
| Headlamp over k8s Dashboard | Modern, k3s-friendly, no special RBAC gymnastics; actively maintained | — Pending |
| Velero over manual PVC snapshots | Full namespace backup including secrets + PVCs; S3 target allows off-node storage | — Pending |
| Fine granularity roadmap | User prefers one concern per phase for visibility and rollback safety | ✓ |

---
*Last updated: 2026-04-04 — Phase 3 complete (Grafana admin password as SOPS secret)*
