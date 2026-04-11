# Requirements: HomeLab-Pro Improvement

**Defined:** 2026-04-04
**Core Value:** Every stateful app survives any single node failure without data loss

## v1 Requirements

### Critical Fixes (CRIT)

- [x] **CRIT-01**: `apps` Kustomization has `dependsOn: [databases]` so apps never race databases on bootstrap
- [ ] **CRIT-02**: audiobookshelf Deployment has resource `requests` and `limits` defined
- [ ] **CRIT-03**: All deployments using `:latest` image tags are pinned to specific versions (n8n, cloudflared)
- [x] **CRIT-04**: Grafana admin password is stored in a SOPS-encrypted Secret, not hardcoded in HelmRelease values
- [ ] **CRIT-05**: Renovate external-host-error is diagnosed and resolved

### Backup (BACK)

- [ ] **BACK-01**: n8n CloudNativePG cluster has a `ScheduledBackup` resource configured
- [x] **BACK-02**: linkding `ScheduledBackup` has a `destinationPath` pointing to object storage
- [ ] **BACK-03**: Velero is installed and configured with an S3-compatible backup target
- [ ] **BACK-04**: All app namespaces have Velero backup schedules (daily, configurable retention)
- [ ] **BACK-05**: A Velero test restore has been performed and documented

### Storage (STOR)

- [x] **STOR-01**: Longhorn is installed via FluxCD HelmRelease
- [x] **STOR-02**: Longhorn is configured as the default StorageClass (local-path demoted)
- [x] **STOR-03**: Longhorn replication factor set to 2 (data on 2 nodes minimum)
- [x] **STOR-04**: All stateful app PVCs (audiobookshelf, mealie, linkding-data, filebrowser, n8n-data, pgadmin) migrated from local-path to Longhorn
- [x] **STOR-05**: CloudNativePG PVCs (linkding-postgres-1, n8n-postgresql-cluster-1) migrated from local-path to Longhorn
- [x] **STOR-06**: Longhorn UI dashboard is accessible (via Traefik Ingress, internal access)

### Scheduling (SCHED)

- [x] **SCHED-01**: Worker-02 is receiving app workloads proportional to its capacity (4 CPU, 15.7GB RAM)
- [x] **SCHED-02**: PodTopologySpreadConstraints are defined on multi-replica deployments (cloudflared) to spread across nodes
- [x] **SCHED-03**: Control-plane node is not overloaded with stateful workloads after storage migration

### Security (SEC)

- [ ] **SEC-01**: Cilium is installed as the CNI, replacing Flannel
- [ ] **SEC-02**: Hubble observability is enabled in Cilium
- [x] **SEC-03**: A default-deny NetworkPolicy is applied in each app namespace
- [x] **SEC-04**: Allow-rules are configured per namespace so each app can reach only its own database and required services
- [x] **SEC-05**: flux-system existing NetworkPolicies are preserved and verified after Cilium migration

### Observability (OBS)

- [x] **OBS-01**: Headlamp dashboard is deployed and accessible via Traefik Ingress (internal)
- [x] **OBS-02**: Longhorn metrics are scraped by Prometheus

### Networking (NET)

- [ ] **NET-DNS-01**: PiHole is deployed in K3s with persistent storage, accessible via internal Traefik Ingress
- [ ] **NET-DNS-02**: Network gateway is configured to use PiHole as primary DNS resolver
- [ ] **NET-DNS-03**: All network devices (phones, laptops, IoT) are resolving through PiHole
- [ ] **NET-DNS-04**: Ad-blocking is verified working on client devices

### Security — DNS (SEC)

- [ ] **SEC-DNS-01**: PiHole Grafana dashboard is configured and wired into Homepage with query statistics

## v2 Requirements

### Media Stack

- **MEDIA-01**: Radarr deployed with Cloudflare Tunnel access
- **MEDIA-02**: Sonarr deployed with Cloudflare Tunnel access
- **MEDIA-03**: Prowlarr deployed as indexer manager
- **MEDIA-04**: qBittorrent with VPN sidecar deployed
- **MEDIA-05**: Bazarr (subtitle management) deployed

### Advanced Networking

- **NET-01**: External Secrets Operator installed (replace SOPS-in-git with Vault or similar)
- **NET-02**: Cilium BGP/L2 announcements for internal LoadBalancer IPs

### HA Database

- **DB-01**: linkding CNPG cluster scaled to 2 instances (primary + standby)
- **DB-02**: n8n CNPG cluster scaled to 2 instances

## Out of Scope

| Feature | Reason |
|---------|--------|
| Rook-Ceph | No raw block devices; Longhorn is correct choice for this hardware |
| Kubernetes upgrade | v1.30.0+k3s1 is stable and not blocking; out of scope for this milestone |
| Production environment | Single staging cluster; multi-env out of scope |
| Homarr | Replaced by Homepage; intentionally disabled |
| Authelia/Authentik | SSO layer adds complexity not justified by current use case |
| Flux Operator | Already running FluxCD well via bootstrap; minimal benefit |
| CoreDNS changes | Already running correctly from k3s defaults |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CRIT-01 | Phase 1 | Complete |
| CRIT-02 | Phase 2 | Pending |
| CRIT-03 | Unassigned | Pending |
| CRIT-04 | Phase 3 | Complete |
| CRIT-05 | Phase 4 | Pending |
| BACK-01 | Phase 5 | Pending |
| BACK-02 | Phase 6 | Complete |
| STOR-01 | Phase 7 | Complete |
| STOR-02 | Phase 7 | Complete |
| STOR-03 | Phase 7 | Complete |
| STOR-06 | Phase 7 | Complete |
| OBS-02 | Phase 7 | Complete |
| STOR-04 | Phase 8 | Complete |
| STOR-05 | Phase 8 | Complete |
| SCHED-01 | Phase 9 | Complete |
| SCHED-02 | Phase 9 | Complete |
| SCHED-03 | Phase 9 | Complete |
| SEC-01 | Phase 10 | Pending |
| SEC-02 | Phase 10 | Pending |
| SEC-03 | Phase 11 | Complete |
| SEC-04 | Phase 11 | Complete |
| SEC-05 | Phase 11 | Complete |
| BACK-03 | Phase 12 | Pending |
| BACK-04 | Phase 12 | Pending |
| BACK-05 | Phase 12 | Pending |
| OBS-01 | Phase 12 | Complete |
| NET-DNS-01 | Phase 14 | Pending |
| NET-DNS-02 | Phase 14 | Pending |
| NET-DNS-03 | Phase 14 | Pending |
| NET-DNS-04 | Phase 14 | Pending |
| SEC-DNS-01 | Phase 14 | Pending |

**Coverage:**
- v1 requirements: 28 total
- Mapped to phases: 28
- Unmapped: 0 ✓

---
*Requirements defined: 2026-04-04*
*Last updated: 2026-04-04 after initial cluster diagnosis*
