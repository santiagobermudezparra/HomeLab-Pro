# HomeLab-Pro Improvement — Roadmap

**Milestone:** v1 — Cluster Hardening & Resilience
**Granularity:** Fine (one concern per phase)
**Created:** 2003-04-04

---

## Phase 1: Fix FluxCD Bootstrap Race Condition

**Goal:** `apps` Kustomization waits for `databases` before deploying, eliminating the bootstrap race condition where apps try to connect to databases that don't exist yet.

**Requirements:** CRIT-01

**Plans:** 1/1 plans complete

Plans:
- [x] 01-01-PLAN.md — Add dependsOn: databases to apps Kustomization and open PR

**Scope:**
- Add `dependsOn: [{ name: databases }]` to `clusters/staging/apps.yaml`
- Verify the dependency chain: `infrastructure-controllers` → `databases` → `apps`
- Test via `flux reconcile` dry-run

**Done when:** `flux get kustomizations` shows `apps` depends on `databases` in the dependency graph and the change is merged to main.

---

## Phase 2: Add Resource Limits — audiobookshelf

**Goal:** audiobookshelf deployment has defined resource requests and limits so it cannot OOM-kill the control-plane node.

**Requirements:** CRIT-02

**Scope:**
- Add `resources.requests` and `resources.limits` to `apps/base/audiobookshelf/deployment.yaml`
- Review all other app deployments for missing or undersized limits
- Audit existing limits against actual pod memory usage from `kubectl top pods`

**Done when:** `kubectl describe pod -n audiobookshelf` shows resource limits set, and all deployments have non-zero requests.

---

## Phase 3: Grafana Admin Password as SOPS Secret

**Goal:** Grafana admin password is stored in a SOPS-encrypted Kubernetes Secret and referenced by the HelmRelease, not hardcoded in plaintext in git.

**Requirements:** CRIT-04

**Scope:**
- Create `monitoring/configs/staging/kube-prometheus-stack/grafana-admin-secret.yaml` (SOPS-encrypted)
- Update `monitoring/controllers/base/kube-prometheus-stack/release.yaml` to reference the secret via `admin.existingSecret`
- Remove hardcoded `adminPassword: watary` from HelmRelease values
- Add secret to monitoring kustomization

**Done when:** `grep -r "adminPassword" monitoring/` returns zero matches and Grafana login still works.

**Plans:** 1 plan

Plans:
- [x] 03-01-PLAN.md — Create SOPS-encrypted grafana-admin-secret and update HelmRelease to use existingSecret

---

## Phase 4: n8n Database Backup

**Goal:** n8n's PostgreSQL cluster has a scheduled backup so automation data is not lost on database pod failure.

**Requirements:** BACK-01

**Plans:** 1/1 plans complete

Plans:
- [x] 04-01-PLAN.md — Create ScheduledBackup for n8n-postgresql-cluster and add to kustomization

**Scope:**
- Create `databases/staging/n8n/backup-config.yaml` (ScheduledBackup, daily 3am, mirrors linkding pattern)
- Configure backup destination (object storage — MinIO or S3 bucket)
- Add to `databases/staging/n8n/kustomization.yaml`

**Done when:** `kubectl get scheduledbackup -n n8n` shows the backup scheduled and `kubectl get backup -n n8n` shows at least one completed backup.

---

## Phase 5: Fix linkding Backup Destination

**Goal:** linkding's existing ScheduledBackup actually persists data to object storage (currently has no `destinationPath` configured).

**Requirements:** BACK-02

**Scope:**
- Configure S3/MinIO object storage credentials as SOPS-encrypted secret in linkding namespace
- Update `databases/staging/linkding/backup-config.yaml` with `destinationPath` pointing to object store
- Verify backup completes and data appears in object storage

**Done when:** `kubectl get backup -n linkding` shows a successful backup with an object storage destination.

**Plans:** 1/1 plans complete

Plans:
- [x] 05-01-PLAN.md — Create SOPS-encrypted S3 secret, patch postgresql-cluster.yaml with barmanObjectStore, activate backup-config.yaml, open PR

---

## Phase 6: Install Longhorn Distributed Storage

**Goal:** Longhorn is installed, configured as the default StorageClass with replication factor 2, and its UI dashboard is accessible internally via Traefik.

**Requirements:** STOR-01, STOR-02, STOR-03, STOR-06, OBS-02

**Plans:** 2/4 plans executed

Plans:
- [ ] 06-01-PLAN.md — iscsi-installer DaemonSet prereq: namespace, DaemonSet, staging overlay wired into controller hierarchy
- [x] 06-02-PLAN.md — Longhorn HelmRelease: HelmRepository + HelmRelease with replica=2, default StorageClass, ServiceMonitor
- [x] 06-03-PLAN.md — Longhorn UI ingress: Traefik Ingress at longhorn.watarystack.org pointing to longhorn-frontend:80
- [ ] 06-04-PLAN.md — local-path demotion: K3s config disable local-storage on all nodes, K3s restart, StorageClass verification

**Scope:**
- Add `infrastructure/controllers/base/longhorn/` — HelmRelease, namespace, repository
- Add `infrastructure/controllers/staging/longhorn/` — staging overlay with values (defaultClass: true, replication: 2)
- Configure Longhorn UI via Traefik Ingress at `longhorn.watarystack.org` (internal)
- Update `infrastructure/controllers/staging/kustomization.yaml` to include longhorn
- Verify Prometheus scrapes Longhorn metrics
- Do NOT migrate existing PVCs yet (Phase 8)

**Done when:** `kubectl get storageclass` shows `longhorn` as default, `local-path` is no longer default, Longhorn UI is accessible, and no existing PVCs have been touched.

---

## Phase 7: Migrate PVCs to Longhorn

**Goal:** All stateful app PVCs and database PVCs are migrated from local-path to Longhorn, enabling data resilience across node failures.

**Requirements:** STOR-04, STOR-05

**Plans:** 7/7 plans complete

Plans:
- [x] 07-01-PLAN.md — pgadmin: update storage.yaml + live migration of pgadmin-data-pvc (1Gi) to Longhorn
- [x] 07-02-PLAN.md — filebrowser: update storage.yaml + live migration of filebrowser-db and filebrowser-files (2 PVCs) to Longhorn
- [x] 07-03-PLAN.md — mealie: update storage.yaml + live migration of mealie-data (1Gi) to Longhorn
- [x] 07-04-PLAN.md — audiobookshelf: update storage.yaml + live migration of all 7 PVCs atomically to Longhorn
- [x] 07-05-PLAN.md — linkding: update storage.yaml + live migration of linkding-data-pvc (1Gi) to Longhorn
- [x] 07-06-PLAN.md — n8n: update storage.yaml + live migration of n8n-data (2Gi) to Longhorn
- [x] 07-07-PLAN.md — CNPG: pre-migration backups, bootstrap.recovery migration for linkding-postgres-1 and n8n-postgresql-cluster-1, PR

**Scope (per app, sequential to avoid data loss):**
- Scale down app → backup PVC data → delete local-path PVC → recreate with Longhorn storageClass → restore data → scale up
- Order: pgadmin → filebrowser → mealie → audiobookshelf (7 PVCs) → linkding-data → n8n-data → CNPG PVCs (linkding-postgres-1, n8n-postgresql-cluster-1)
- CNPG PVCs: handled via CNPG backup/restore workflow (not manual copy)
- Update PVC definitions in base configs to specify `storageClassName: longhorn`

**Done when:** `kubectl get pvc --all-namespaces` shows zero `local-path` PVCs, all apps healthy and verified after migration.

---

## Phase 8: Balance Workloads to Worker Nodes

**Goal:** Worker-02 (18h old, nearly idle) and Worker-01 receive proportional workloads. Control-plane is no longer hosting the majority of app pods.

**Requirements:** SCHED-01, SCHED-02, SCHED-03

**Plans:** 2/2 plans complete

Plans:
- [x] 08-01-PLAN.md — topologySpreadConstraints on all 7 active cloudflared Deployments (spread 2 replicas across nodes)
- [x] 08-02-PLAN.md — nodeAffinity (prefer non-control-plane) on all 8 app Deployments and Prometheus HelmRelease

**Scope:**
- Add `topologySpreadConstraints` to cloudflared deployments (currently all pods land on control-plane)
- Add `nodeAffinity` (preferredDuringSchedulingIgnoredDuringExecution, DoesNotExist on node-role.kubernetes.io/control-plane) to all app deployments
- Add same affinity to Prometheus via HelmRelease values
- No hardcoded node names — role-based scheduling only

**Done when:** `kubectl get pods --all-namespaces -o wide` shows workloads distributed across all 3 nodes, worker-02 running at least 5 non-system pods.

---

## Phase 9: Cilium CNI Migration

**Goal:** Cilium replaces Flannel as the CNI, with Hubble observability enabled. All existing network communication works correctly after migration.

**Requirements:** SEC-01, SEC-02

**Plans:** 3 plans

Plans:
- [ ] 09-01-PLAN.md — Maintenance window: disable Flannel in K3s config, restart all nodes, delete flannel.1 interface
- [ ] 09-02-PLAN.md — Bootstrap Cilium 1.16.19 via helm, install cilium CLI, restart all pods to use Cilium networking
- [ ] 09-03-PLAN.md — GitOps adoption: commit HelmRelease + Hubble UI Traefik Ingress + homepage entry, open PR

**Scope:**
- Plan migration: disable k3s flannel, install Cilium via Helm in kube-system
- Update k3s agent config on all 3 nodes to use `--flannel-backend=none --disable-network-policy`
- Install Cilium HelmRelease via FluxCD with Hubble enabled
- Verify all pods reach Ready after CNI swap
- Verify flux-system NetworkPolicies still function
- Enable Hubble UI (accessible via Traefik Ingress)

**Done when:** `cilium status` shows all nodes healthy, `hubble status` shows flows, existing apps all Running and reachable via Cloudflare Tunnels.

**High-risk phase** — requires node-level config changes and a maintenance window. All pods will restart.

---

## Phase 10: NetworkPolicies — Per-Namespace Isolation

**Goal:** Each app namespace has a default-deny NetworkPolicy plus explicit allow-rules for its required connections, so no app can reach another app's database.

**Requirements:** SEC-03, SEC-04, SEC-05

**Scope (per namespace):**
- `default-deny-ingress` NetworkPolicy in each app namespace
- Explicit allow rules:
  - linkding → linkding-postgres-rw (port 5432)
  - n8n → n8n-postgresql-cluster-rw (port 5432)
  - monitoring namespace scrape rules (allow Prometheus to reach all namespaces)
  - cloudflared → app service (within same namespace)
  - flux-system existing policies preserved
- Test isolation: verify mealie cannot reach linkding's postgres

**Done when:** `kubectl get networkpolicies --all-namespaces` shows policies in all app namespaces, and cross-namespace DB access is blocked (verified by test pod).

---

## Phase 11: Velero Full Backup

**Status: Pending — deferred, run when ready (`/gsd:execute-phase 11`)**

**Goal:** Velero is installed with S3-compatible backend and all app namespaces have daily backup schedules with verified restore capability.

**Requirements:** BACK-03, BACK-04, BACK-05

**Plans:** 3 plans (not started)

Plans:
- [ ] 11-01-velero-install-PLAN.md — Velero HelmRelease + R2 credentials (SOPS) + NetworkPolicy + staging overlay wired into controller hierarchy
- [ ] 11-02-backup-schedules-PLAN.md — 8 daily Velero Schedules (one per active app namespace, 14-day retention)
- [ ] 11-03-restore-test-PLAN.md — Ad-hoc backup + test restore of xm-spotify-sync + RESTORE-PROCEDURE.md runbook

**Scope:**
- Install Velero HelmRelease with Cloudflare R2 as S3-compatible backend (no MinIO needed — R2 already in use for CNPG)
- Configure backup schedules for all app namespaces (daily, 14-day retention)
- Perform test restore of a non-critical namespace (xm-spotify-sync)
- Document restore procedure

**Done when:** `velero backup get` shows successful scheduled backups for all namespaces, test restore verified.

---

## Phase 12: Headlamp Web Dashboard

**Goal:** Headlamp is deployed and accessible via Traefik Ingress for cluster visibility without requiring kubectl.

**Requirements:** OBS-01

**Scope:**
- Deploy Headlamp via FluxCD (base + staging overlay)
- Traefik Ingress at `headlamp.internal.watarystack.org` (or Cloudflare Tunnel if external access wanted)
- Configure RBAC for read-only cluster access
- Add to homepage dashboard links

**Plans:** 2/2 plans complete

Plans:
- [x] 12-01-PLAN.md — Headlamp base manifests, staging overlay, RBAC, Traefik Ingress at headlamp.internal.watarystack.org
- [x] 12-02-PLAN.md — Add Headlamp entry to Homepage dashboard services.yaml (Infrastructure group)

**Done when:** Headlamp UI loads at configured URL and shows all namespaces and pod states.

---

## Summary

| Phase | Name | Category | Risk | Est. Effort |
|-------|------|----------|------|-------------|
| 1 | Fix FluxCD Bootstrap Race | Critical Fix | Low | Small |
| 2 | Resource Limits — audiobookshelf | Critical Fix | Low | Small |
| 3 | Grafana Password to SOPS Secret | Security | Low | Small |
| 4 | n8n Database Backup | Backup | Low | Small |
| 5 | Fix linkding Backup Destination | 1/1 | Complete   | 2026-04-05 |
| 6 | Install Longhorn Storage | 2/4 | In Progress|  |
| 7 | Migrate PVCs to Longhorn | 7/7 | Complete   | 2026-04-06 |
| 8 | Balance Workloads to Workers | 2/2 | Complete   | 2026-04-06 |
| 9 | Cilium CNI Migration | Security | **High** | Large |
| 10 | NetworkPolicies per Namespace | 2/2 | Complete    | 2026-04-10 |
| 11 | Velero Full Backup | Backup | Low | Medium |
| 12 | Headlamp Dashboard | 2/2 | Complete   | 2026-04-11 |
| 13 | Observability Stack — Loki, Fluent Bit, Gatus | 1/3 | In Progress|  |

---

## Phase 13: Observability Stack — Loki, Fluent Bit, and Gatus

**Goal:** Cluster-wide logs are queryable in Grafana (via Loki + Fluent Bit) and all homelab services are continuously probed with results on a public status page (via Gatus).

**Requirements:** OBS-LOG-01, OBS-STATUS-01

**Depends on:** Phase 12

**Plans:** 1/3 plans executed

Plans:
- [x] 13-01-PLAN.md — Loki HelmRelease (single-binary, filesystem backend) in monitoring controllers hierarchy
- [ ] 13-02-PLAN.md — Fluent Bit DaemonSet + Grafana Loki datasource ConfigMap
- [ ] 13-03-PLAN.md — Gatus base manifests, Cloudflare Tunnel, staging overlay, Homepage entry

**Scope:**
- Deploy Loki (single-binary mode, Cloudflare R2 or local filesystem backend) via FluxCD HelmRelease
- Deploy Fluent Bit DaemonSet to collect logs from all nodes and forward to Loki
- Wire Loki as a Grafana data source so logs appear alongside Prometheus metrics
- Deploy Gatus via FluxCD (base + staging overlay)
- Configure Gatus endpoint checks for all active services (audiobookshelf, homarr, linkding, mealie, n8n, etc.)
- Expose Gatus via Cloudflare Tunnel at `status.watarystack.org`
- Add both to homepage dashboard

**Done when:** Grafana "Explore" tab shows logs from all app namespaces via Loki, and Gatus status page shows green/red indicators for all monitored services.

---
*Roadmap created: 2003-04-04*
*Based on live cluster diagnosis: 3 nodes, 11 PVCs all local-path, FluxCD v2.5.1, K3s v1.30.0*
