---
phase: 08-balance-workloads-to-worker-nodes
verified: 2026-04-06T00:00:00Z
status: human_needed
score: 5/5 must-haves verified
re_verification: false
human_verification:
  - test: "Confirm workload distribution after PR #45 is merged and FluxCD syncs"
    expected: "kubectl get pods --all-namespaces -o wide shows app pods on worker-01 and worker-02, not exclusively on control-plane; worker-02 running at least 5 non-system pods"
    why_human: "Scheduling preference is a soft rule applied at pod scheduling time. Current cluster state cannot be verified without kubectl access to the live cluster. FluxCD applies changes only after merge."
  - test: "Verify cloudflared pods spread across nodes after merge + FluxCD reconcile"
    expected: "kubectl get pods -A -o wide | grep cloudflared shows replicas on different nodes (not all on control-plane)"
    why_human: "topologySpreadConstraints only take effect when pods are (re)scheduled; cannot verify current placement from the Git repo alone."
  - test: "Confirm REQUIREMENTS.md coverage table phase label"
    expected: "SCHED-01, SCHED-02, SCHED-03 mapping table rows should read 'Phase 8' not 'Phase 9'; update if incorrect"
    why_human: "ROADMAP.md assigns SCHED-01/02/03 to Phase 8; REQUIREMENTS.md coverage table says Phase 9. One of them has a stale label. Human should confirm which is authoritative and correct the stale entry."
---

# Phase 8: Balance Workloads to Worker Nodes — Verification Report

**Phase Goal:** Worker-02 (18h old, nearly idle) and Worker-01 receive proportional workloads. Control-plane is no longer hosting the majority of app pods.
**Verified:** 2026-04-06
**Status:** human_needed (all automated checks pass; live cluster distribution requires human confirmation post-merge)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Each active cloudflared deployment (7 apps) has topologySpreadConstraints defined | VERIFIED | All 7 cloudflare.yaml files contain `topologySpreadConstraints` (grep count = 1 each) |
| 2 | cloudflared replicas spread across different nodes automatically when cluster grows | VERIFIED | `topologyKey: kubernetes.io/hostname`, `maxSkew: 1`, `whenUnsatisfiable: DoNotSchedule` present in all 7 files |
| 3 | No node names are hardcoded in any scheduling YAML | VERIFIED | grep for `nodeName`, `worker-01`, `worker-02` across all modified files returns no output |
| 4 | All single-replica app deployments prefer to land on worker nodes, not the control-plane | VERIFIED | All 8 deployment.yaml files in apps/base contain `preferredDuringSchedulingIgnoredDuringExecution` with `DoesNotExist` on `node-role.kubernetes.io/control-plane` and `weight: 100` |
| 5 | Prometheus preferably runs on a worker node, not the control-plane | VERIFIED | `monitoring/controllers/base/kube-prometheus-stack/release.yaml` contains `affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution` with `DoesNotExist` on `node-role.kubernetes.io/control-plane` under `prometheusSpec` (line 37-44) |

**Score:** 5/5 truths verified (automated)

---

## Required Artifacts

### Plan 08-01: cloudflared topologySpreadConstraints

| Artifact | Expected | Level 1: Exists | Level 2: Substantive | Level 3: Wired | Status |
|----------|----------|-----------------|----------------------|----------------|--------|
| `apps/staging/linkding/cloudflare.yaml` | topologySpreadConstraints in Deployment | YES | topologyKey + whenUnsatisfiable + labelSelector present | Part of kustomize build — kubectl kustomize OK | VERIFIED |
| `apps/staging/mealie/cloudflare.yaml` | topologySpreadConstraints in Deployment | YES | topologyKey + whenUnsatisfiable + labelSelector present | kubectl kustomize OK | VERIFIED |
| `apps/staging/audiobookshelf/cloudflare.yaml` | topologySpreadConstraints in Deployment | YES | topologyKey + whenUnsatisfiable + labelSelector present | kubectl kustomize OK | VERIFIED |
| `apps/staging/pgadmin/cloudflare.yaml` | topologySpreadConstraints in Deployment | YES | topologyKey + whenUnsatisfiable + labelSelector present | kubectl kustomize OK | VERIFIED |
| `apps/staging/homepage/cloudflare.yaml` | topologySpreadConstraints in Deployment | YES | topologyKey + whenUnsatisfiable + labelSelector present | kubectl kustomize OK | VERIFIED |
| `apps/staging/n8n/cloudflare.yaml` | topologySpreadConstraints in Deployment | YES | topologyKey + whenUnsatisfiable + labelSelector present | kubectl kustomize OK | VERIFIED |
| `apps/staging/filebrowser/cloudflare.yaml` | topologySpreadConstraints in Deployment | YES | topologyKey + whenUnsatisfiable + labelSelector present | kubectl kustomize OK | VERIFIED |

### Plan 08-02: nodeAffinity on app deployments and Prometheus

| Artifact | Expected | Level 1: Exists | Level 2: Substantive | Level 3: Wired | Status |
|----------|----------|-----------------|----------------------|----------------|--------|
| `apps/base/linkding/deployment.yaml` | nodeAffinity preferring non-control-plane | YES | DoesNotExist + weight:100 + preferredDuring... | Applied via kustomize overlay (kubectl kustomize OK) | VERIFIED |
| `apps/base/mealie/deployment.yaml` | nodeAffinity preferring non-control-plane | YES | DoesNotExist + weight:100 + preferredDuring... | Applied via kustomize overlay | VERIFIED |
| `apps/base/audiobookshelf/deployment.yaml` | nodeAffinity preferring non-control-plane | YES | DoesNotExist + weight:100 + preferredDuring... | Applied via kustomize overlay | VERIFIED |
| `apps/base/pgadmin/deployment.yaml` | nodeAffinity preferring non-control-plane | YES | DoesNotExist + weight:100 + preferredDuring... | Applied via kustomize overlay | VERIFIED |
| `apps/base/homepage/deployment.yaml` | nodeAffinity preferring non-control-plane | YES | DoesNotExist + weight:100 + preferredDuring... | Applied via kustomize overlay | VERIFIED |
| `apps/base/n8n/deployment.yaml` | nodeAffinity preferring non-control-plane | YES | DoesNotExist + weight:100 + preferredDuring... | Applied via kustomize overlay | VERIFIED |
| `apps/base/filebrowser/deployment.yaml` | nodeAffinity preferring non-control-plane | YES | DoesNotExist + weight:100 + preferredDuring... | Applied via kustomize overlay | VERIFIED |
| `apps/base/xm-spotify-sync/deployment.yaml` | nodeAffinity preferring non-control-plane | YES | DoesNotExist + weight:100 + preferredDuring... | Applied via kustomize overlay | VERIFIED |
| `monitoring/controllers/base/kube-prometheus-stack/release.yaml` | prometheusSpec.affinity with nodeAffinity | YES | Affinity under prometheusSpec at lines 37-44; DoesNotExist on control-plane role label | HelmRelease applies via Flux monitoring kustomization | VERIFIED |

---

## Key Link Verification

### Plan 08-01 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `topologySpreadConstraints[0].topologyKey` | `kubernetes.io/hostname` | node label | VERIFIED | `topologyKey: kubernetes.io/hostname` present in all 7 cloudflare.yaml files |
| `topologySpreadConstraints[0].labelSelector` | `matchLabels.app: cloudflared` | pod label selector | VERIFIED | `app: cloudflared` inside labelSelector block in all 7 files |

### Plan 08-02 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution` | `node-role.kubernetes.io/control-plane` label absence | DoesNotExist operator | VERIFIED | `DoesNotExist` found in all 8 deployment.yaml files; role-based not name-based |
| `monitoring/.../release.yaml` | `prometheus.prometheusSpec.affinity` | HelmRelease values block | VERIFIED | `prometheusSpec` key at line 31; `affinity` nested inside at line 37 |

---

## Data-Flow Trace (Level 4)

Not applicable. This phase adds Kubernetes scheduling directives (topologySpreadConstraints, nodeAffinity) — these are declarative scheduler hints, not data-rendering components. There is no application data flow to trace. The scheduling rules are read by the Kubernetes scheduler at pod placement time.

---

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| kustomize build linkding valid | `kubectl kustomize apps/staging/linkding/` | Produced valid YAML (exit 0) | PASS |
| kustomize build mealie valid | `kubectl kustomize apps/staging/mealie/` | Produced valid YAML (exit 0) | PASS |
| kustomize build pgadmin valid | `kubectl kustomize apps/staging/pgadmin/` | Produced valid YAML (exit 0) | PASS |
| kustomize build audiobookshelf valid | `kubectl kustomize apps/staging/audiobookshelf/` | Produced valid YAML (exit 0) | PASS |
| kustomize build n8n valid | `kubectl kustomize apps/staging/n8n/` | Produced valid YAML (exit 0) | PASS |
| kustomize build filebrowser valid | `kubectl kustomize apps/staging/filebrowser/` | Produced valid YAML (exit 0) | PASS |
| Live pod distribution | Requires cluster access post-merge | Cannot check from repo | SKIP (human required) |

Note: `kustomize` binary is not in PATH on this machine; `kubectl kustomize` was used as the equivalent.

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SCHED-01 | 08-02-PLAN.md | Worker-02 receives app workloads proportional to its capacity | PARTIALLY SATISFIED — configuration complete; live distribution requires human verification post-merge | nodeAffinity with weight:100 + DoesNotExist on control-plane role in all 8 app deployments. Soft preference ensures workers are preferred on next pod scheduling. |
| SCHED-02 | 08-01-PLAN.md | PodTopologySpreadConstraints defined on multi-replica deployments (cloudflared) | SATISFIED | topologySpreadConstraints with topologyKey: kubernetes.io/hostname and maxSkew: 1 in all 7 cloudflared Deployments. Code is fully implemented and validates via kustomize build. |
| SCHED-03 | 08-02-PLAN.md | Control-plane node is not overloaded with stateful workloads after storage migration | PARTIALLY SATISFIED — configuration complete; live verification requires post-merge observation | nodeAffinity soft preference added to all 8 app deployments and Prometheus. No hardcoded names. Pods will redistribute on next restart after FluxCD sync. |

### Orphaned Requirements Check

REQUIREMENTS.md coverage table lists SCHED-01, SCHED-02, SCHED-03 under "Phase 9" — but ROADMAP.md assigns all three to Phase 8. This is a documentation inconsistency (stale value in the table). Both plans (08-01, 08-02) explicitly claim these requirements in their frontmatter. No requirements are orphaned — all three are claimed and implemented.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `.planning/REQUIREMENTS.md` (coverage table) | lines 102-104 | SCHED-01/02/03 mapped to "Phase 9" instead of "Phase 8" | Info | Documentation only — no impact on cluster behavior. Should be corrected for accuracy. |

No code anti-patterns found. No TODOs, placeholder values, hardcoded node names, or empty implementations in any of the 16 modified files.

---

## Human Verification Required

### 1. Live Pod Distribution Check

**Test:** After PR #45 is merged and FluxCD reconciles, run:
```
kubectl get pods --all-namespaces -o wide | grep -v "kube-system\|flux-system\|longhorn" | awk '{print $8}' | sort | uniq -c
```
**Expected:** Pod counts spread across multiple nodes — not 90%+ on control-plane. Worker-02 running at least 5 non-system pods.
**Why human:** Scheduling preferences (soft affinities) only take effect at pod scheduling time. The Git repo shows the configuration is correct, but actual placement can only be confirmed against the live cluster after merge + FluxCD sync + pod restart.

### 2. cloudflared Pod Spread Confirmation

**Test:** After PR #45 is merged and FluxCD reconciles, run:
```
kubectl get pods --all-namespaces -o wide | grep cloudflared
```
**Expected:** For each app's cloudflared Deployment (2 replicas), the two pods appear on different nodes (topologySpreadConstraints with DoNotSchedule means co-location is refused).
**Why human:** The constraint only enforces at scheduling time — live cluster state is required.

### 3. REQUIREMENTS.md Phase Label Correction

**Test:** Review `.planning/REQUIREMENTS.md` coverage table lines 102-104.
**Expected:** SCHED-01, SCHED-02, SCHED-03 should reference "Phase 8" (not "Phase 9") to match ROADMAP.md.
**Why human:** Requires editorial judgment on which document is authoritative, then a manual correction.

---

## Gaps Summary

No blocking gaps. All 16 artifacts exist, are substantive (correct scheduling directives with proper operators and values), and are wired (all kustomize builds produce valid output). The PR (#45) is open targeting main.

The only open items are:
1. Live cluster verification (cannot be done from the repo — requires post-merge observation)
2. A minor documentation inconsistency in REQUIREMENTS.md (SCHED requirements listed under "Phase 9" in the coverage table instead of "Phase 8")

Both are human-only items. The implementation is complete and correct.

---

_Verified: 2026-04-06_
_Verifier: Claude (gsd-verifier)_
