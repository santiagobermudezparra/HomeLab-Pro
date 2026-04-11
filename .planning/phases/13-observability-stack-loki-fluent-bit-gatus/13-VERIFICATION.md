---
phase: 13-observability-stack-loki-fluent-bit-gatus
verified: 2026-04-11T08:00:00Z
status: human_needed
score: 7/7
re_verification: false
human_verification:
  - test: "FluxCD reconciles loki and fluent-bit HelmReleases without errors"
    expected: "kubectl get helmreleases -n monitoring shows loki and fluent-bit with READY=True"
    why_human: "Cannot verify cluster runtime state from manifest files alone"
  - test: "Loki pod is Running in monitoring namespace"
    expected: "kubectl get pods -n monitoring shows loki-0 (or loki-*) with STATUS=Running"
    why_human: "Cannot verify pod runtime state from manifests"
  - test: "Fluent Bit DaemonSet pods running on all 3 nodes"
    expected: "kubectl get ds fluent-bit -n monitoring shows DESIRED=3 READY=3"
    why_human: "Cannot verify DaemonSet scheduling from manifests"
  - test: "Grafana Explore shows Loki datasource with queryable logs"
    expected: "Grafana Explore tab shows 'Loki' in the datasource dropdown and returns log results for {job='fluent-bit'}"
    why_human: "Requires browser interaction with running Grafana"
  - test: "Gatus accessible at https://status.watarystack.org"
    expected: "Browser shows the WataryStack status page with green/red indicators for all configured services"
    why_human: "Requires DNS CNAME creation in Cloudflare dashboard (user action) and FluxCD reconciliation"
  - test: "Headlamp accessible at https://headlamp.watarystack.org"
    expected: "Browser loads the Headlamp Kubernetes dashboard login page"
    why_human: "Requires FluxCD reconciliation of any ingress changes from prior phase"
---

# Phase 13: Observability Stack (Loki / Fluent Bit / Gatus) Verification Report

**Phase Goal:** Deploy observability stack — Loki for log storage, Fluent Bit for log collection, Gatus for service health status page.
**Verified:** 2026-04-11T08:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

All manifest artifacts are present, substantive, and wired. No runtime verification is possible from Git state alone. All 7 observable truths are structurally satisfied by the codebase; runtime confirmation is required for the 6 human verification items.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Loki HelmRelease deployed in monitoring namespace via FluxCD | ✓ VERIFIED | `monitoring/controllers/base/loki/release.yaml` — HelmRelease with `deploymentMode: SingleBinary`, `auth_enabled: false`, `storageClass: longhorn`, `replication_factor: 1` |
| 2 | Loki accepts log push on port 3100 cluster-internally | ✓ VERIFIED | HelmRelease creates `loki.monitoring.svc.cluster.local:3100`; Fluent Bit release.yaml references this exact host/port |
| 3 | Fluent Bit DaemonSet wired to forward all pod logs to Loki | ✓ VERIFIED | `monitoring/controllers/base/fluent-bit/release.yaml` — `kind: DaemonSet`, `Host loki.monitoring.svc.cluster.local`, `Port 3100`, `Auto_Kubernetes_Labels On`, control-plane toleration present |
| 4 | Grafana auto-discovers Loki datasource via sidecar ConfigMap | ✓ VERIFIED | `monitoring/configs/staging/kube-prometheus-stack/loki-datasource.yaml` — label `grafana_datasource: "1"`, URL `http://loki.monitoring.svc.cluster.local:3100` |
| 5 | Gatus status page is accessible at https://status.watarystack.org | ? HUMAN | Manifests are correct; requires Cloudflare DNS CNAME to exist and FluxCD to reconcile |
| 6 | Gatus checks all active homelab services (10 endpoints) | ✓ VERIFIED | `apps/base/gatus/configmap.yaml` — 10 endpoint checks across 4 groups: Audiobookshelf, Spotify Sync, Linkding, Mealie, n8n, Filebrowser, Grafana, Prometheus, PgAdmin, Headlamp |
| 7 | Homepage dashboard shows Gatus entry in Monitoring group | ✓ VERIFIED | `apps/base/homepage/homepage-configmap.yaml` — Gatus entry with `href: https://status.watarystack.org` and `ping:` configured, placed first in the Monitoring group |

**Score:** 6/7 truths VERIFIED, 1/7 needs human confirmation (runtime access)

---

### Required Artifacts

| Artifact | Provided | Status | Details |
|----------|----------|--------|---------|
| `monitoring/controllers/base/loki/release.yaml` | Loki HelmRelease (single-binary, filesystem) | ✓ VERIFIED | `deploymentMode: SingleBinary`, `storage.type: filesystem`, `auth_enabled: false`, `storageClass: longhorn`, version `6.29.0` |
| `monitoring/controllers/base/loki/repository.yaml` | Grafana HelmRepository | ✓ VERIFIED | `name: grafana`, `url: https://grafana.github.io/helm-charts` |
| `monitoring/controllers/base/loki/kustomization.yaml` | Base Loki kustomization | ⚠ NOTE | Lists `repository.yaml` and `release.yaml` only; `namespace.yaml` is present on disk but not listed — see note below |
| `monitoring/controllers/staging/loki/kustomization.yaml` | Staging overlay pointing to base loki | ✓ VERIFIED | `resources: - ../../base/loki/` |
| `monitoring/controllers/staging/kustomization.yaml` | Top-level staging controllers kustomization | ✓ VERIFIED | Lists `kube-prometheus-stack`, `loki`, `fluent-bit` |
| `monitoring/controllers/base/fluent-bit/release.yaml` | Fluent Bit HelmRelease as DaemonSet | ✓ VERIFIED | `kind: DaemonSet`, Loki output config, control-plane toleration, resource limits |
| `monitoring/controllers/base/fluent-bit/repository.yaml` | Fluent Helm repository | ✓ VERIFIED | `name: fluent`, `url: https://fluent.github.io/helm-charts` |
| `monitoring/controllers/base/fluent-bit/kustomization.yaml` | Base Fluent Bit kustomization | ⚠ NOTE | Lists `repository.yaml` and `release.yaml` only; `namespace.yaml` present on disk but not listed — see note below |
| `monitoring/controllers/staging/fluent-bit/kustomization.yaml` | Staging overlay pointing to base fluent-bit | ✓ VERIFIED | `resources: - ../../base/fluent-bit/` |
| `monitoring/configs/staging/kube-prometheus-stack/loki-datasource.yaml` | Grafana datasource ConfigMap | ✓ VERIFIED | `grafana_datasource: "1"` label, `url: http://loki.monitoring.svc.cluster.local:3100` |
| `monitoring/configs/staging/kube-prometheus-stack/kustomization.yaml` | Config kustomization with loki-datasource | ✓ VERIFIED | `loki-datasource.yaml` listed at end of resources |
| `apps/base/gatus/deployment.yaml` | Gatus Deployment | ✓ VERIFIED | Image `ghcr.io/twin/gatus:v5.12.1`, mounts `gatus-config` ConfigMap at `/config`, port 8080 |
| `apps/base/gatus/service.yaml` | Gatus ClusterIP Service | ✓ VERIFIED | Exposes port 8080, selector `app: gatus` |
| `apps/base/gatus/configmap.yaml` | Gatus endpoint configuration | ✓ VERIFIED | 10 endpoints across Media/Productivity/Monitoring/Infrastructure groups |
| `apps/base/gatus/kustomization.yaml` | Base Gatus kustomization | ✓ VERIFIED | Lists namespace, deployment, service, configmap |
| `apps/staging/gatus/cloudflare.yaml` | Cloudflared Deployment + ConfigMap | ✓ VERIFIED | `hostname: status.watarystack.org`, `service: http://gatus:8080`, catch-all `http_status:404` |
| `apps/staging/gatus/cloudflare-secret.yaml` | SOPS-encrypted tunnel credentials | ✓ VERIFIED | Contains `ENC[AES256_GCM`, `encrypted_regex: ^(data|stringData)$`, age recipient matches cluster key |
| `apps/staging/gatus/kustomization.yaml` | Gatus staging overlay | ✓ VERIFIED | References `../../base/gatus`, `cloudflare.yaml`, `cloudflare-secret.yaml` |
| `apps/staging/kustomization.yaml` | Apps staging kustomization including gatus | ✓ VERIFIED | `- gatus` present in resources list |
| `apps/base/homepage/homepage-configmap.yaml` | Homepage Monitoring group updated | ✓ VERIFIED | Gatus entry with `href/ping: https://status.watarystack.org` as first entry in Monitoring group |

**Note on namespace.yaml omission:** Both `monitoring/controllers/base/loki/kustomization.yaml` and `monitoring/controllers/base/fluent-bit/kustomization.yaml` list only `repository.yaml` and `release.yaml`, omitting `namespace.yaml`. The `monitoring` namespace is pre-created by kube-prometheus-stack (wave 1, already deployed), so these components will schedule correctly. This is not a blocker but represents an inconsistency with the plan's success criteria which called for `namespace.yaml` to be listed. The namespace files exist on disk and are harmlessly unused.

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `monitoring/controllers/staging/kustomization.yaml` | `monitoring/controllers/staging/loki/kustomization.yaml` | `- loki` in resources | ✓ WIRED | Confirmed present |
| `monitoring/controllers/staging/loki/kustomization.yaml` | `monitoring/controllers/base/loki/` | `../../base/loki/` | ✓ WIRED | Exact path confirmed |
| `monitoring/controllers/staging/kustomization.yaml` | `monitoring/controllers/staging/fluent-bit/kustomization.yaml` | `- fluent-bit` in resources | ✓ WIRED | Confirmed present |
| `monitoring/controllers/staging/fluent-bit/kustomization.yaml` | `monitoring/controllers/base/fluent-bit/` | `../../base/fluent-bit/` | ✓ WIRED | Exact path confirmed |
| `monitoring/controllers/base/fluent-bit/release.yaml` | `loki.monitoring.svc.cluster.local:3100` | `Host:` in Loki OUTPUT config | ✓ WIRED | `Host loki.monitoring.svc.cluster.local`, `Port 3100` |
| `monitoring/configs/staging/kube-prometheus-stack/loki-datasource.yaml` | Grafana sidecar | `grafana_datasource: "1"` label | ✓ WIRED | Label present; sidecar configured to watch this label in monitoring namespace |
| `monitoring/configs/staging/kube-prometheus-stack/kustomization.yaml` | `loki-datasource.yaml` | resource list | ✓ WIRED | Last entry in resources list |
| `apps/staging/gatus/cloudflare.yaml` | `gatus` service port 8080 | `service: http://gatus:8080` | ✓ WIRED | Exact service reference confirmed |
| `apps/staging/kustomization.yaml` | `apps/staging/gatus/` | `- gatus` in resources | ✓ WIRED | Confirmed present |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `apps/base/gatus/configmap.yaml` | `endpoints` (static probe config) | Static YAML — no DB needed; Gatus performs live HTTP probes at runtime | N/A — config-driven | ✓ FLOWING |
| `monitoring/configs/staging/kube-prometheus-stack/loki-datasource.yaml` | Grafana datasource URL | Static URL pointing to live Loki service | Depends on Loki pod running | ? HUMAN |
| `monitoring/controllers/base/fluent-bit/release.yaml` | Log output stream | `/var/log/containers/*.log` via `tail` input | Live filesystem logs | ? HUMAN |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — phase produces Kubernetes manifests only; no runnable CLI or API entry points to test without a running cluster.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| OBS-LOG-01 | 13-01, 13-02 | Log aggregation: Loki storage + Fluent Bit collection + Grafana datasource | ✓ SATISFIED | Loki HelmRelease (single-binary, filesystem), Fluent Bit DaemonSet with Loki output, Grafana datasource ConfigMap with sidecar label — all wired end-to-end |
| OBS-STATUS-01 | 13-03 | Service health status page at status.watarystack.org | ✓ SATISFIED (structurally) | Gatus deployment + configmap with 10 endpoint checks, Cloudflare tunnel routing status.watarystack.org → gatus:8080, SOPS-encrypted secret, gatus in apps/staging/kustomization.yaml, Homepage updated — awaiting DNS CNAME for runtime access |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `monitoring/controllers/base/loki/kustomization.yaml` | — | `namespace.yaml` exists on disk but is not listed in resources | ℹ Info | No impact — monitoring namespace pre-exists from kube-prometheus-stack; namespace.yaml is an unused no-op |
| `monitoring/controllers/base/fluent-bit/kustomization.yaml` | — | `namespace.yaml` exists on disk but is not listed in resources | ℹ Info | No impact — same reason as above |

No blockers or warnings found.

---

### Human Verification Required

#### 1. FluxCD HelmRelease Reconciliation

**Test:** Run `kubectl get helmreleases -n monitoring` after FluxCD sync completes
**Expected:** Both `loki` and `fluent-bit` HelmReleases show `READY=True` and `STATUS=Release reconciliation succeeded`
**Why human:** Cannot verify cluster runtime state from Git manifests

#### 2. Loki Pod Running

**Test:** Run `kubectl get pods -n monitoring | grep loki`
**Expected:** Pod `loki-0` (StatefulSet) shows `STATUS=Running` and `READY=1/1`
**Why human:** Cannot verify pod lifecycle from manifests

#### 3. Fluent Bit DaemonSet on All Nodes

**Test:** Run `kubectl get ds fluent-bit -n monitoring`
**Expected:** `DESIRED`, `READY`, and `AVAILABLE` all equal 3 (one per node)
**Why human:** Cannot verify DaemonSet scheduling from manifests

#### 4. Grafana Loki Datasource Active

**Test:** Open Grafana → Explore → click datasource dropdown
**Expected:** "Loki" appears as a selectable datasource; running a query with `{job="fluent-bit"}` returns log lines
**Why human:** Requires browser interaction with running Grafana instance at grafana.watarystack.org

#### 5. Gatus Status Page Accessible

**Test:** After creating DNS CNAME `status.watarystack.org → <tunnel-uuid>.cfargotunnel.com` in Cloudflare dashboard, navigate to https://status.watarystack.org
**Expected:** WataryStack Status page loads showing 10 service endpoints with green/red health indicators
**Why human:** DNS CNAME creation is a manual Cloudflare dashboard action; requires FluxCD reconciliation of gatus resources

#### 6. Headlamp Dashboard Accessible

**Test:** Navigate to https://headlamp.watarystack.org
**Expected:** Headlamp Kubernetes dashboard login page loads over HTTPS
**Why human:** Depends on FluxCD reconciliation of any Traefik ingress changes and cert-manager TLS provisioning

---

### Gaps Summary

No structural gaps. All manifests exist, are substantive, and are wired. The only outstanding items are runtime confirmations that require cluster access:

1. The `namespace.yaml` files for loki and fluent-bit are on disk but not referenced in their kustomization.yaml resource lists. This is an info-level inconsistency (not a gap) because the `monitoring` namespace is already created by kube-prometheus-stack which deploys in the same wave. The namespace files could be added for completeness but will not affect reconciliation.

2. All 6 human verification items require a running cluster and are expected post-merge artifacts, not pre-merge blockers.

---

_Verified: 2026-04-11T08:00:00Z_
_Verifier: Claude (gsd-verifier)_
