---
phase: 06-install-longhorn-distributed-storage
plan: 02
subsystem: infra
tags: [longhorn, helmrelease, helmrepository, fluxcd, storageclass, prometheus, servicemonitor, kustomize]

# Dependency graph
requires:
  - phase: 06-install-longhorn-distributed-storage/06-01
    provides: longhorn-system Namespace and iscsi-installer DaemonSet (open-iscsi prereq)
provides:
  - HelmRepository manifest pointing to https://charts.longhorn.io
  - HelmRelease manifest for longhorn 1.7.3 with default StorageClass + 2 replicas + ServiceMonitor
  - Updated base kustomization including repository.yaml and release.yaml
affects:
  - 06-install-longhorn-distributed-storage/06-03 (ingress overlay depends on HelmRelease being Ready)
  - 07-migrate-pvcs-to-longhorn (PVC migration requires longhorn StorageClass present)

# Tech tracking
tech-stack:
  added:
    - longhorn 1.7.3 HelmRelease (FluxCD HelmRelease + HelmRepository CRs)
  patterns:
    - HelmRepository + HelmRelease pair in base controller directory (matches cert-manager pattern)
    - ServiceMonitor label release=kube-prometheus-stack for Prometheus scraping
    - CRD management via install.crds: Create + upgrade.crds: CreateReplace

key-files:
  created:
    - infrastructure/controllers/base/longhorn/repository.yaml
    - infrastructure/controllers/base/longhorn/release.yaml
  modified:
    - infrastructure/controllers/base/longhorn/kustomization.yaml

key-decisions:
  - "Pinned version 1.7.3 — not floating; re-verify if >30 days from research date 2026-04-05"
  - "Both replica values set: persistence.defaultClassReplicaCount: 2 (StorageClass) AND defaultSettings.defaultReplicaCount: \"2\" (string, Longhorn UI)"
  - "Ingress section intentionally omitted from release.yaml — handled in Plan 03 as a standalone overlay"
  - "ServiceMonitor label matches live cluster's serviceMonitorSelector: {release: kube-prometheus-stack}"
  - "FluxCD reconciliation and live smoke tests are post-merge concerns — GitOps constraint applies"

patterns-established:
  - "HelmRepository and HelmRelease live in infrastructure/controllers/base/{name}/ alongside Namespace and DaemonSet prereqs"
  - "Two Longhorn replica settings required: defaultClassReplicaCount (K8s PVC provisioner) and defaultReplicaCount (Longhorn UI, must be string)"

requirements-completed: [STOR-01, STOR-02, STOR-03, OBS-02]

# Metrics
duration: 2min
completed: 2026-04-05
---

# Phase 06 Plan 02: Longhorn HelmRepository and HelmRelease Summary

**Longhorn 1.7.3 HelmRepository and HelmRelease manifests added to base controller directory with default StorageClass (2 replicas), Prometheus ServiceMonitor wired to kube-prometheus-stack, ready for FluxCD to apply on PR merge**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-05T06:39:00Z
- **Completed:** 2026-04-05T06:40:27Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Created `infrastructure/controllers/base/longhorn/repository.yaml` — HelmRepository pointing to https://charts.longhorn.io (24h interval)
- Created `infrastructure/controllers/base/longhorn/release.yaml` — HelmRelease for longhorn 1.7.3 with CRD management, default StorageClass, 2-replica settings for both StorageClass parameters and Longhorn UI, and ServiceMonitor with `release: kube-prometheus-stack`
- Updated `infrastructure/controllers/base/longhorn/kustomization.yaml` to include both new files
- Validated via `kubectl kustomize` — all four expected kinds (Namespace, DaemonSet, HelmRepository, HelmRelease) output without errors
- Pushed feature branch to origin — changes ready for PR merge

## Task Commits

Each task was committed atomically:

1. **Task 1: Add HelmRepository and HelmRelease to base longhorn** - `0c122a4` (feat)
2. **Task 2: Push to origin and document reconciliation expectations** - (push to origin; no new files — verification is post-merge per GitOps constraint)

**Plan metadata:** (created below)

## Files Created/Modified

- `infrastructure/controllers/base/longhorn/repository.yaml` - HelmRepository CR pointing to https://charts.longhorn.io, 24h sync interval
- `infrastructure/controllers/base/longhorn/release.yaml` - HelmRelease CR for longhorn 1.7.3; sets defaultClass=true, defaultClassReplicaCount=2, defaultReplicaCount="2", ServiceMonitor with kube-prometheus-stack label
- `infrastructure/controllers/base/longhorn/kustomization.yaml` - Updated to add repository.yaml and release.yaml to resources list

## Decisions Made

- Pinned to Longhorn v1.7.3 (researched 2026-04-05) — re-verify if deploying >30 days after research date
- Both replica count fields are required: `persistence.defaultClassReplicaCount: 2` sets `numberOfReplicas` in the StorageClass used by K8s PVC provisioner; `defaultSettings.defaultReplicaCount: "2"` (must be string) sets the Longhorn UI default — omitting either causes inconsistency
- `ingress:` section intentionally absent from release.yaml — the Longhorn UI ingress is Plan 03's concern, consistent with the pattern of keeping routing config in overlays
- ServiceMonitor label `release: kube-prometheus-stack` matches the live cluster's `serviceMonitorSelector` confirmed via `kubectl get prometheus kube-prometheus-stack-prometheus -n monitoring`

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

**FluxCD verification is post-merge only:** FluxCD tracks the `main` branch. Since changes are on feature branch `worktree-agent-a45fb7de`, the HelmRelease will not be applied until the PR is merged. The `kubectl kustomize` build confirmed manifests are structurally valid (all four kinds output cleanly). The runtime verifications (HelmRelease Ready=True, 10+ pods, StorageClass with default annotation, ServiceMonitor with correct label, 22 CRDs) are post-merge concerns.

This is expected and correct behavior per the project's GitOps constraint: "All changes go through Git → PR → FluxCD sync, never direct kubectl apply to main".

## Pre-Merge Manifest Validation

```
kubectl kustomize infrastructure/controllers/base/longhorn/
# Output kinds (verified): DaemonSet, HelmRelease, HelmRepository, Namespace — no errors
```

## Post-Merge Verification Commands

Once merged and FluxCD reconciles (~3-5 min for full Longhorn install), run these smoke tests:

```bash
# STOR-01: HelmRelease reconciled
kubectl get helmrelease longhorn -n longhorn-system \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# Expect: True

# STOR-01: Longhorn pods running (expect 10+ pods)
kubectl get pods -n longhorn-system --field-selector=status.phase=Running --no-headers | wc -l
# Expect: >=10

# STOR-02: Longhorn StorageClass is default
kubectl get sc longhorn -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}'
# Expect: true

# STOR-03: StorageClass replicaCount=2
kubectl get sc longhorn -o jsonpath='{.parameters.numberOfReplicas}'
# Expect: 2

# OBS-02: ServiceMonitor exists with correct label
kubectl get servicemonitor -n longhorn-system \
  -o jsonpath='{.items[0].metadata.labels.release}'
# Expect: kube-prometheus-stack

# CRD count
kubectl get crd | grep longhorn | wc -l
# Expect: 22

# Worker-01 disk status (EXPECTED: Schedulable: false — disk at 16.7% free, below 25% threshold)
kubectl get lhn -n longhorn-system
```

## Worker-01 Disk Note

Worker-01 (`homelab-worker-01`) has <25% free disk space (16.7% free). Longhorn's disk scheduling threshold is 25% free. After install, Worker-01 will show `Schedulable: false` on its disk condition in `kubectl get lhn -n longhorn-system`. This is **expected and correct behavior** — do not attempt to override it. Storage replication will use control-plane and Worker-02 only.

## User Setup Required

None - no external service configuration required. After merging the PR, FluxCD will automatically apply the manifests within 1 minute. Full Longhorn install (22 CRDs + all pods) takes 3-5 minutes. Monitor with:

```bash
flux get helmrelease longhorn -n longhorn-system --watch
kubectl get pods -n longhorn-system -w
```

## Next Phase Readiness

- Plan 03 (Longhorn UI ingress/access) can proceed once this PR is merged and HelmRelease shows Ready=True
- Plan 04 (demote local-path StorageClass default) can proceed after Longhorn is confirmed running
- No blockers — manifests validated, hierarchy correct, feature branch pushed to origin

---
*Phase: 06-install-longhorn-distributed-storage*
*Completed: 2026-04-05*
