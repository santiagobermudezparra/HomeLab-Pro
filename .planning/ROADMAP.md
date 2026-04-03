# HomeLab-Pro Improvement — Roadmap

**Milestone:** v1 — Cluster Hardening & Resilience
**Granularity:** Fine (one concern per phase)
**Created:** 2026-04-04

---

## Phase 1: Fix FluxCD Bootstrap Race Condition

**Goal:** `apps` Kustomization waits for `databases` before deploying, eliminating the bootstrap race condition where apps try to connect to databases that don't exist yet.

**Requirements:** CRIT-01

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

## Phase 3: Pin All Image Tags

**Goal:** No deployment in the cluster uses `:latest` or untagged images. All images are pinned to specific versions for reproducible, GitOps-safe deployments.

**Requirements:** CRIT-03

**Scope:**
- `apps/base/n8n/deployment.yaml`: `n8nio/n8n:latest` → pin to current stable (e.g. `1.x.y`)
- All `apps/staging/*/cloudflare.yaml`: `cloudflare/cloudflared:latest` → pin to specific version
- `infrastructure/controllers/base/renovate/cronjob.yaml`: `renovate/renovate:latest` → pin
- Verify Renovate will track pinned versions going forward

**Done when:** `grep -r ":latest" apps/ infrastructure/` returns zero matches.

---

## Phase 4: Grafana Admin Password as SOPS Secret

**Goal:** Grafana admin password is stored in a SOPS-encrypted Kubernetes Secret and referenced by the HelmRelease, not hardcoded in plaintext in git.

**Requirements:** CRIT-04

**Scope:**
- Create `monitoring/configs/staging/kube-prometheus-stack/grafana-admin-secret.yaml` (SOPS-encrypted)
- Update `monitoring/controllers/base/kube-prometheus-stack/release.yaml` to reference the secret via `admin.existingSecret`
- Remove hardcoded `adminPassword: watary` from HelmRelease values
- Add secret to monitoring kustomization

**Done when:** `grep -r "adminPassword" monitoring/` returns zero matches and Grafana login still works.

---

## Phase 5: Fix Renovate external-host-error

**Goal:** Renovate runs without errors and successfully scans the repository for outdated images and Helm chart versions.

**Requirements:** CRIT-05

**Scope:**
- Inspect Renovate logs from erroring pods (2d ago) vs successful pods (recent)
- Identify whether the error is a GitHub API rate limit, token permissions, or network issue
- Fix Renovate config or secret accordingly
- Verify successful run produces correct PRs (e.g., for pinned tags from Phase 3)

**Done when:** `kubectl get pods -n renovate` shows only `Completed` exits, no `Error` pods in the last 24h.

---

## Phase 6: n8n Database Backup

**Goal:** n8n's PostgreSQL cluster has a scheduled backup so automation data is not lost on database pod failure.

**Requirements:** BACK-01

**Scope:**
- Create `databases/staging/n8n/backup-config.yaml` (ScheduledBackup, daily 3am, mirrors linkding pattern)
- Configure backup destination (object storage — MinIO or S3 bucket)
- Add to `databases/staging/n8n/kustomization.yaml`

**Done when:** `kubectl get scheduledbackup -n n8n` shows the backup scheduled and `kubectl get backup -n n8n` shows at least one completed backup.

---

## Phase 7: Fix linkding Backup Destination

**Goal:** linkding's existing ScheduledBackup actually persists data to object storage (currently has no `destinationPath` configured).

**Requirements:** BACK-02

**Scope:**
- Configure S3/MinIO object storage credentials as SOPS-encrypted secret in linkding namespace
- Update `databases/staging/linkding/backup-config.yaml` with `destinationPath` pointing to object store
- Verify backup completes and data appears in object storage

**Done when:** `kubectl get backup -n linkding` shows a successful backup with an object storage destination.

---

## Phase 8: Install Longhorn Distributed Storage

**Goal:** Longhorn is installed, configured as the default StorageClass with replication factor 2, and its UI dashboard is accessible internally via Traefik.

**Requirements:** STOR-01, STOR-02, STOR-03, STOR-06, OBS-02

**Scope:**
- Add `infrastructure/controllers/base/longhorn/` — HelmRelease, namespace, repository
- Add `infrastructure/controllers/staging/longhorn/` — staging overlay with values (defaultClass: true, replication: 2)
- Configure Longhorn UI via Traefik Ingress at `longhorn.internal.watarystack.org` (or similar)
- Update `infrastructure/controllers/staging/kustomization.yaml` to include longhorn
- Verify Prometheus scrapes Longhorn metrics
- Do NOT migrate existing PVCs yet (Phase 9)

**Done when:** `kubectl get storageclass` shows `longhorn` as default, `local-path` is no longer default, Longhorn UI is accessible, and no existing PVCs have been touched.

---

## Phase 9: Migrate PVCs to Longhorn

**Goal:** All stateful app PVCs and database PVCs are migrated from local-path to Longhorn, enabling data resilience across node failures.

**Requirements:** STOR-04, STOR-05

**Scope (per app, sequential to avoid data loss):**
- Scale down app → backup PVC data → delete local-path PVC → recreate with Longhorn storageClass → restore data → scale up
- Order: pgadmin → filebrowser → mealie → audiobookshelf (3 PVCs) → linkding-data → n8n-data → CNPG PVCs (linkding-postgres-1, n8n-postgresql-cluster-1)
- CNPG PVCs: handled via CNPG backup/restore workflow (not manual copy)
- Update PVC definitions in base configs to specify `storageClassName: longhorn`

**Done when:** `kubectl get pvc --all-namespaces` shows zero `local-path` PVCs, all apps healthy and verified after migration.

---

## Phase 10: Balance Workloads to Worker Nodes

**Goal:** Worker-02 (18h old, nearly idle) and Worker-01 receive proportional workloads. Control-plane is no longer hosting the majority of app pods.

**Requirements:** SCHED-01, SCHED-02, SCHED-03

**Scope:**
- Add `podAntiAffinity` or `topologySpreadConstraints` to cloudflared deployments (currently all pods land on control-plane)
- Add `topologySpreadConstraints` to high-memory apps (mealie, prometheus) to spread across workers
- Consider `nodeAffinity` to prefer workers over control-plane for app pods
- Verify control-plane `kubectl taint` is not needed (k3s doesn't taint control-plane by default)

**Done when:** `kubectl get pods --all-namespaces -o wide` shows workloads distributed across all 3 nodes, worker-02 running at least 5 non-system pods.

---

## Phase 11: Cilium CNI Migration

**Goal:** Cilium replaces Flannel as the CNI, with Hubble observability enabled. All existing network communication works correctly after migration.

**Requirements:** SEC-01, SEC-02

**Scope:**
- Plan migration: disable k3s flannel, install Cilium via Helm in kube-system
- Update k3s agent config on all 3 nodes to use `--flannel-backend=none --disable-network-policy`
- Install Cilium HelmRelease via FluxCD with Hubble enabled
- Verify all pods reach Ready after CNI swap
- Verify flux-system NetworkPolicies still function
- Enable Hubble UI (accessible via Traefik Ingress)

**Done when:** `cilium status` shows all nodes healthy, `hubble status` shows flows, existing apps all Running and reachable via Cloudflare Tunnels.

**⚠ High-risk phase** — requires node-level config changes and a maintenance window. All pods will restart.

---

## Phase 12: NetworkPolicies — Per-Namespace Isolation

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

## Phase 13: Velero Full Backup

**Goal:** Velero is installed with S3-compatible backend and all app namespaces have daily backup schedules with verified restore capability.

**Requirements:** BACK-03, BACK-04, BACK-05

**Scope:**
- Install Velero HelmRelease with MinIO (or external S3) as backend
- Configure backup schedules for all app namespaces (daily, 14-day retention)
- Perform test restore of a non-critical namespace (xm-spotify-sync or pgadmin)
- Document restore procedure

**Done when:** `velero backup get` shows successful scheduled backups for all namespaces, test restore verified.

---

## Phase 14: Headlamp Web Dashboard

**Goal:** Headlamp is deployed and accessible via Traefik Ingress for cluster visibility without requiring kubectl.

**Requirements:** OBS-01

**Scope:**
- Deploy Headlamp via FluxCD (base + staging overlay)
- Traefik Ingress at `headlamp.internal.watarystack.org` (or Cloudflare Tunnel if external access wanted)
- Configure RBAC for read-only cluster access
- Add to homepage dashboard links

**Done when:** Headlamp UI loads at configured URL and shows all namespaces and pod states.

---

## Summary

| Phase | Name | Category | Risk | Est. Effort |
|-------|------|----------|------|-------------|
| 1 | Fix FluxCD Bootstrap Race | Critical Fix | Low | Tiny |
| 2 | Resource Limits — audiobookshelf | Critical Fix | Low | Small |
| 3 | Pin All Image Tags | Critical Fix | Low | Small |
| 4 | Grafana Password to Secret | Security | Low | Small |
| 5 | Fix Renovate Errors | Critical Fix | Low | Medium |
| 6 | n8n Database Backup | Backup | Low | Small |
| 7 | Fix linkding Backup Destination | Backup | Low | Small |
| 8 | Install Longhorn Storage | Storage | Medium | Medium |
| 9 | Migrate PVCs to Longhorn | Storage | Medium | Large |
| 10 | Balance Workloads to Workers | Scheduling | Low | Small |
| 11 | Cilium CNI Migration | Security | **High** | Large |
| 12 | NetworkPolicies per Namespace | Security | Medium | Medium |
| 13 | Velero Full Backup | Backup | Low | Medium |
| 14 | Headlamp Dashboard | Observability | Low | Small |

---
*Roadmap created: 2026-04-04*
*Based on live cluster diagnosis: 3 nodes, 11 PVCs all local-path, FluxCD v2.5.1, K3s v1.30.0*
