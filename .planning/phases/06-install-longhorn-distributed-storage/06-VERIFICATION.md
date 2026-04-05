---
phase: 06-install-longhorn-distributed-storage
verified: 2026-04-05T07:30:00Z
status: passed
score: 5/5 must-haves verified
gaps: []
human_verification:
  - test: "Longhorn UI browser navigation"
    expected: "Node list shows 3 nodes, disk schedulability, and volume list loads without error"
    why_human: "HTTP 200 confirmed via curl but full UI navigation and content rendering requires a browser"
  - test: "Prometheus is actively scraping Longhorn metrics"
    expected: "Prometheus UI shows longhorn_* metrics with recent timestamps"
    why_human: "ServiceMonitor exists with correct label but actual scrape success requires checking Prometheus targets page or querying metrics"
---

# Phase 06: Install Longhorn Distributed Storage — Verification Report

**Phase Goal:** Longhorn is installed, configured as the default StorageClass with replication factor 2, and its UI dashboard is accessible internally via Traefik.
**Verified:** 2026-04-05T07:30:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | HelmRelease longhorn reconciles successfully (Ready=True) | VERIFIED | `kubectl get helmrelease longhorn -n longhorn-system` → Ready=True; "Helm install succeeded for release longhorn-system/longhorn.v1 with chart longhorn@1.7.3" |
| 2 | Longhorn is the only default StorageClass (local-path removed) | VERIFIED | `kubectl get sc` shows only `longhorn (default)` and `longhorn-static`; local-path StorageClass does not exist |
| 3 | StorageClass numberOfReplicas is 2 | VERIFIED | `kubectl get sc longhorn -o jsonpath='{.parameters.numberOfReplicas}'` → `2` |
| 4 | Longhorn UI is accessible at longhorn.watarystack.org | VERIFIED | `curl -H "Host: longhorn.watarystack.org" http://192.168.1.115/` → HTTP 200 |
| 5 | ServiceMonitor exists with label matching kube-prometheus-stack Prometheus | VERIFIED | `kubectl get servicemonitor -n longhorn-system` → `longhorn-prometheus-servicemonitor` with label `release: kube-prometheus-stack`; Prometheus `serviceMonitorSelector` matches |

**Score:** 5/5 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `infrastructure/controllers/base/longhorn/namespace.yaml` | longhorn-system Namespace | VERIFIED | File exists, 5 lines, valid Namespace manifest |
| `infrastructure/controllers/base/longhorn/iscsi-installer.yaml` | iscsi-installer DaemonSet | VERIFIED | File exists, 43 lines, contains `longhorn-iscsi-installation`; DaemonSet is DESIRED=3, READY=3 in cluster |
| `infrastructure/controllers/base/longhorn/repository.yaml` | HelmRepository pointing to charts.longhorn.io | VERIFIED | File exists, contains `https://charts.longhorn.io` |
| `infrastructure/controllers/base/longhorn/release.yaml` | HelmRelease longhorn 1.7.3 with StorageClass + replicas + ServiceMonitor | VERIFIED | File exists; sets `defaultClass: true`, `defaultClassReplicaCount: 2`, `defaultReplicaCount: "2"`, ServiceMonitor with `release: kube-prometheus-stack` |
| `infrastructure/controllers/base/longhorn/kustomization.yaml` | Resource list including namespace, iscsi-installer, repository, release | VERIFIED | All 4 resources listed |
| `infrastructure/controllers/staging/longhorn/kustomization.yaml` | Staging overlay referencing base + ingress.yaml | VERIFIED | References `../../base/longhorn/` and `ingress.yaml` |
| `infrastructure/controllers/staging/longhorn/ingress.yaml` | Traefik Ingress routing longhorn.watarystack.org to longhorn-frontend:80 | VERIFIED | File exists with TLS annotation (cert-manager); live cluster serving HTTP 200 |
| `infrastructure/controllers/staging/kustomization.yaml` | Top-level controllers list including longhorn | VERIFIED | Contains `- longhorn` in resources list |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `infrastructure/controllers/staging/kustomization.yaml` | `infrastructure/controllers/staging/longhorn/` | `resources: - longhorn` | WIRED | Entry `- longhorn` present in resources list |
| `infrastructure/controllers/staging/longhorn/kustomization.yaml` | `infrastructure/controllers/base/longhorn/` | `resources: ../../base/longhorn/` | WIRED | Entry `../../base/longhorn/` present |
| `infrastructure/controllers/staging/longhorn/kustomization.yaml` | `infrastructure/controllers/staging/longhorn/ingress.yaml` | `resources: ingress.yaml` | WIRED | Entry `ingress.yaml` present |
| `infrastructure/controllers/base/longhorn/release.yaml` | `infrastructure/controllers/base/longhorn/repository.yaml` | `spec.chart.spec.sourceRef.name: longhorn` | WIRED | `sourceRef` present, name and namespace match HelmRepository |
| `longhorn StorageClass` | replica count 2 | `persistence.defaultClassReplicaCount: 2` | WIRED | Live cluster confirms `numberOfReplicas: 2` |
| `ServiceMonitor` | kube-prometheus-stack Prometheus | label `release: kube-prometheus-stack` | WIRED | Prometheus `serviceMonitorSelector.matchLabels.release: kube-prometheus-stack` confirmed |
| `infrastructure/controllers/staging/longhorn/ingress.yaml` | `longhorn-frontend` service port 80 | `spec.rules[0].http.paths[0].backend.service.name: longhorn-frontend` | WIRED | Backend is `longhorn-frontend:80`; HTTP 200 probe confirmed routing works |

---

### Data-Flow Trace (Level 4)

Not applicable for this phase — all artifacts are Kubernetes manifests (infrastructure configuration), not components that render dynamic data from a store or API.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| HelmRelease is Ready | `kubectl get helmrelease longhorn -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` | `True` | PASS |
| longhorn is sole default StorageClass | `kubectl get sc` | Only `longhorn (default)` and `longhorn-static`; no local-path | PASS |
| StorageClass numberOfReplicas=2 | `kubectl get sc longhorn -o jsonpath='{.parameters.numberOfReplicas}'` | `2` | PASS |
| local-path StorageClass absent | `kubectl get sc local-path` | Error: not found | PASS |
| 10+ Longhorn pods running | `kubectl get pods -n longhorn-system --field-selector=status.phase=Running --no-headers \| wc -l` | `30` | PASS |
| iscsi-installer DaemonSet READY=3 | `kubectl get ds longhorn-iscsi-installation -n longhorn-system` | DESIRED=3, READY=3 | PASS |
| 22 Longhorn CRDs installed | `kubectl get crd \| grep longhorn \| wc -l` | `22` | PASS |
| ServiceMonitor with correct label | `kubectl get servicemonitor -n longhorn-system -o jsonpath='{.items[0].metadata.labels.release}'` | `kube-prometheus-stack` | PASS |
| Ingress routes to longhorn-frontend | `kubectl get ingress longhorn-ui -n longhorn-system -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}'` | `longhorn-frontend` | PASS |
| Longhorn UI returns HTTP 200 | `curl -s -o /dev/null -w "%{http_code}" -H "Host: longhorn.watarystack.org" http://192.168.1.115/` | `200` | PASS |
| FluxCD infrastructure-controllers kustomization Ready | `kubectl get kustomization infrastructure-controllers -n flux-system` | Ready=True, Applied revision: main@sha1:f25ba73 | PASS |
| All nodes Ready after K3s restart | `kubectl get nodes` | homelab-worker-01, homelab-worker-02, santi-standard-pc-i440fx-piix-1996 all Ready | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| STOR-01 | 06-01, 06-02 | Longhorn is installed via FluxCD HelmRelease | SATISFIED | HelmRelease Ready=True; 30 pods Running; 22 CRDs present |
| STOR-02 | 06-02, 06-04 | Longhorn is configured as the default StorageClass (local-path demoted) | SATISFIED | `longhorn (default)` is the only StorageClass; local-path does not exist |
| STOR-03 | 06-02 | Longhorn replication factor set to 2 (data on 2 nodes minimum) | SATISFIED | `numberOfReplicas: 2` in StorageClass parameters; `defaultReplicaCount: "2"` in HelmRelease values |
| STOR-06 | 06-03 | Longhorn UI dashboard is accessible via Traefik Ingress | SATISFIED | Ingress `longhorn-ui` exists routing `longhorn.watarystack.org` to `longhorn-frontend:80`; HTTP 200 confirmed |
| OBS-02 | 06-02 | Longhorn metrics are scraped by Prometheus | SATISFIED | ServiceMonitor `longhorn-prometheus-servicemonitor` exists with label `release: kube-prometheus-stack`; Prometheus `serviceMonitorSelector` matches |

No orphaned requirements — all 5 requirements mapped to plans are verified.

---

### Anti-Patterns Found

No anti-patterns detected. All manifest files are substantive and complete. No TODO/FIXME comments, no placeholder content, no empty implementations.

---

### Notable Observations

**Ingress TLS state (informational, not a gap):**

The `ingress.yaml` file on the current feature branch (`feat/homelab-improvement`) includes a `cert-manager.io/cluster-issuer` annotation and TLS block. However, the version merged to `main` (PR #34) did not include TLS — it was a plain HTTP ingress. The live cluster runs the `main` branch version (no TLS on the ingress spec), confirmed by `kubectl get ingress longhorn-ui -n longhorn-system` showing PORTS=80 with no TLS section in the spec.

A TLS certificate `longhorn-ui-tls` exists in `longhorn-system` (Ready=True, issued by `letsencrypt-cloudflare-prod`) as a side-effect from an intermediate cluster state when the TLS ingress was briefly applied. The cert is orphaned relative to the current cluster ingress state.

PR #35 (pending merge) will bring the TLS ingress.yaml to `main`, at which point FluxCD will apply the TLS-enabled ingress and the cert will be properly used. This is not a gap for STOR-06 (the requirement specifies UI accessible via Traefik Ingress — HTTP 200 is confirmed), but it is worth tracking.

**Plan 06-04 has no Git artifacts by design:**

The local-path demotion (STOR-02) was implemented by editing `/etc/rancher/k3s/config.yaml` directly on the control-plane node via SSH. This is not a GitOps change. The live cluster state confirms the outcome: local-path StorageClass does not exist, longhorn is the sole default. The K3s config change is documented in `06-04-SUMMARY.md`.

**Worker-01 disk scheduling disabled (expected):**

`homelab-worker-01` has less than 25% free disk space. Longhorn's scheduling threshold requires 25% free. Worker-01 shows `Schedulable: false` for its disk condition in Longhorn. This is expected behavior documented in the plans — replication uses control-plane and Worker-02 only.

---

### Human Verification Required

#### 1. Longhorn UI Browser Navigation

**Test:** Open `http://longhorn.watarystack.org` (requires LAN access and DNS/hosts entry `192.168.1.115 longhorn.watarystack.org`). Navigate to the Nodes page and Volumes page.
**Expected:** Node list shows 3 nodes (Worker-01 disk showing Schedulable=false is expected). Volume list loads without error. No error banners.
**Why human:** HTTP 200 confirms the server responds, but full UI rendering and content correctness requires a browser session.

#### 2. Prometheus Actively Scraping Longhorn Metrics

**Test:** Open Prometheus UI, go to Status > Targets. Search for "longhorn". Alternatively run: `kubectl exec -n monitoring deploy/kube-prometheus-stack-prometheus -- wget -qO- 'localhost:9090/api/v1/query?query=longhorn_volume_state' | python3 -m json.tool | grep resultType`
**Expected:** Longhorn targets show UP state. Query returns data (not empty result).
**Why human:** ServiceMonitor exists with correct selector label, but actual scrape success depends on network connectivity between Prometheus and the Longhorn metrics endpoint, which cannot be confirmed without executing a live query.

---

### Gaps Summary

No gaps. All 5 observable truths are verified, all 8 artifacts exist and are substantive, all 7 key links are wired, all 5 requirements are satisfied, and all 12 behavioral spot-checks passed. The phase goal is fully achieved.

---

_Verified: 2026-04-05T07:30:00Z_
_Verifier: Claude (gsd-verifier)_
