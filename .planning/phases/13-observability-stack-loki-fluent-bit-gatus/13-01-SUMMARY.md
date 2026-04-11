---
phase: 13-observability-stack-loki-fluent-bit-gatus
plan: "01"
subsystem: monitoring
tags: [loki, helm, fluxcd, observability, logging]
dependency_graph:
  requires: []
  provides: [loki-helmrelease, grafana-helmrepository]
  affects: [monitoring/controllers/staging]
tech_stack:
  added: [loki 6.29.0, grafana HelmRepository]
  patterns: [HelmRelease single-binary, filesystem backend, FluxCD GitOps]
key_files:
  created:
    - monitoring/controllers/base/loki/namespace.yaml
    - monitoring/controllers/base/loki/repository.yaml
    - monitoring/controllers/base/loki/release.yaml
    - monitoring/controllers/base/loki/kustomization.yaml
    - monitoring/controllers/staging/loki/kustomization.yaml
  modified:
    - monitoring/controllers/staging/kustomization.yaml
decisions:
  - "namespace.yaml excluded from loki base kustomization to prevent duplicate Namespace/monitoring conflict with kube-prometheus-stack when merged in staging"
  - "HelmRepository named grafana (not loki) to be reused by Fluent Bit and future Grafana-ecosystem charts"
  - "Loki 6.29.0 SingleBinary mode with auth_enabled: false and gateway disabled for homelab simplicity"
  - "longhorn 10Gi PVC for log storage; nodeAffinity prefers non-control-plane nodes"
metrics:
  duration: 66s
  completed_date: "2026-04-11"
  tasks_completed: 3
  tasks_total: 3
  files_created: 5
  files_modified: 1
---

# Phase 13 Plan 01: Loki HelmRelease (Single-Binary, Filesystem Backend) Summary

Loki deployed via FluxCD HelmRelease in single-binary mode using filesystem storage on a 10Gi Longhorn PVC, reachable at `http://loki.monitoring.svc.cluster.local:3100`.

## What Was Built

Deployed Loki 6.x via a FluxCD HelmRelease targeting the `grafana` HelmRepository. Uses SingleBinary deployment mode with a local filesystem backend (no object storage complexity), auth disabled, and gateway disabled. The HelmRelease is wired into the existing staging monitoring controller hierarchy so FluxCD will reconcile it alongside kube-prometheus-stack.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Loki HelmRepository and namespace | 6c10e03 | monitoring/controllers/base/loki/namespace.yaml, repository.yaml |
| 2 | Loki HelmRelease (single-binary, filesystem backend) | 3e8717b | monitoring/controllers/base/loki/release.yaml, kustomization.yaml |
| 3 | Wire Loki into staging controller hierarchy | 3306246 | monitoring/controllers/staging/loki/kustomization.yaml, staging/kustomization.yaml |

## Verification Results

- `monitoring/controllers/base/loki/` contains: namespace.yaml, repository.yaml, release.yaml, kustomization.yaml
- `monitoring/controllers/staging/loki/kustomization.yaml` points to `../../base/loki/`
- `monitoring/controllers/staging/kustomization.yaml` contains `- loki`
- `kubectl kustomize monitoring/controllers/staging/` exits 0 — produces Namespace, both HelmReleases, both HelmRepositories
- release.yaml has `deploymentMode: SingleBinary`, `auth_enabled: false`, `storageClass: longhorn`, `replication_factor: 1`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed duplicate Namespace/monitoring from loki base kustomization**
- **Found during:** Task 3 verification
- **Issue:** Both `kube-prometheus-stack` and `loki` base dirs included `namespace.yaml` with `name: monitoring`. When kustomize merges them in staging, it errors: "may not add resource with an already registered id: Namespace.v1.[noGrp]/monitoring.[noNs]"
- **Fix:** Removed `namespace.yaml` from `monitoring/controllers/base/loki/kustomization.yaml` resources list. The `namespace.yaml` file is retained for reference but not included in the kustomization build. The monitoring namespace is owned by kube-prometheus-stack.
- **Files modified:** monitoring/controllers/base/loki/kustomization.yaml
- **Commit:** 3306246

## Known Stubs

None — no UI components, no placeholder data sources. Loki HelmRelease references real chart version and real HelmRepository URL.

## Self-Check: PASSED

Files verified:
- monitoring/controllers/base/loki/namespace.yaml — FOUND
- monitoring/controllers/base/loki/repository.yaml — FOUND
- monitoring/controllers/base/loki/release.yaml — FOUND
- monitoring/controllers/base/loki/kustomization.yaml — FOUND
- monitoring/controllers/staging/loki/kustomization.yaml — FOUND
- monitoring/controllers/staging/kustomization.yaml (modified) — FOUND

Commits verified:
- 6c10e03 — FOUND
- 3e8717b — FOUND
- 3306246 — FOUND
