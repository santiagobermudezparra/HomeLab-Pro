---
phase: 13-observability-stack-loki-fluent-bit-gatus
plan: "02"
subsystem: infra
tags: [fluent-bit, loki, grafana, kubernetes, daemonset, helm, fluxcd, logging]

# Dependency graph
requires:
  - phase: 13-01
    provides: Loki HelmRelease SingleBinary at loki.monitoring.svc.cluster.local:3100

provides:
  - Fluent Bit DaemonSet collecting logs from all pods on all nodes
  - Fluent Bit forwarding to Loki via output plugin with Auto_Kubernetes_Labels
  - Loki Grafana datasource ConfigMap auto-provisioned via sidecar

affects:
  - 13-03-gatus (observability stack completion)

# Tech tracking
tech-stack:
  added:
    - fluent-bit 0.48.3 (fluent.github.io/helm-charts)
    - Loki datasource provisioning via Grafana sidecar
  patterns:
    - HelmRepository per chart vendor (fluent HelmRepo for fluent.github.io charts)
    - Grafana datasource ConfigMap with grafana_datasource: "1" label for sidecar auto-provisioning
    - Control-plane toleration on DaemonSets requiring cluster-wide coverage

key-files:
  created:
    - monitoring/controllers/base/fluent-bit/namespace.yaml
    - monitoring/controllers/base/fluent-bit/repository.yaml
    - monitoring/controllers/base/fluent-bit/release.yaml
    - monitoring/controllers/base/fluent-bit/kustomization.yaml
    - monitoring/controllers/staging/fluent-bit/kustomization.yaml
    - monitoring/configs/staging/kube-prometheus-stack/loki-datasource.yaml
  modified:
    - monitoring/controllers/staging/kustomization.yaml
    - monitoring/configs/staging/kube-prometheus-stack/kustomization.yaml

key-decisions:
  - "namespace.yaml excluded from fluent-bit base kustomization (same as loki pattern) — including it causes duplicate Namespace/monitoring conflict when kustomize merges kube-prometheus-stack, loki, and fluent-bit in staging"
  - "Separate fluent HelmRepository created (fluent.github.io/helm-charts) — distinct from grafana repo; reuses monitoring namespace alongside grafana HelmRepository"
  - "grafana_datasource: \"1\" ConfigMap label triggers Grafana sidecar auto-provisioning — no manual Grafana configuration required"
  - "Fluent Bit outputs section uses Match kube.* (not Match *) to forward only Kubernetes pod logs, not Fluent Bit's own internal metrics"

patterns-established:
  - "DaemonSet log collectors require control-plane toleration (node-role.kubernetes.io/control-plane: Exists, NoSchedule) to collect logs from all 3 nodes"
  - "Grafana datasource provisioning via labeled ConfigMap (grafana_datasource: \"1\") in monitoring namespace — consistent with dashboard injection pattern"

requirements-completed:
  - OBS-LOG-01

# Metrics
duration: 10min
completed: 2026-04-11
---

# Phase 13 Plan 02: Fluent Bit + Loki Datasource Summary

**Fluent Bit DaemonSet (0.48.3) collecting Kubernetes pod logs from all 3 nodes and forwarding to Loki, with Loki auto-provisioned as a Grafana datasource via sidecar ConfigMap**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-11T07:25:00Z
- **Completed:** 2026-04-11T07:30:54Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments

- Fluent Bit HelmRelease as DaemonSet with tail input (`/var/log/containers/*.log`), Kubernetes metadata filter, and Loki output with `Auto_Kubernetes_Labels On`
- Control-plane toleration ensures Fluent Bit pods run on all 3 nodes (including the control-plane node)
- Loki datasource ConfigMap with `grafana_datasource: "1"` label auto-provisioned by Grafana sidecar — no manual Grafana configuration needed
- Both kustomize trees (`monitoring/controllers/staging/` and `monitoring/configs/staging/`) build cleanly with zero errors

## Task Commits

1. **Task 1: Fluent Bit HelmRelease (DaemonSet forwarding to Loki)** - `cfada45` (feat)
2. **Task 2: Loki Grafana datasource ConfigMap** - `44f5462` (feat)

## Files Created/Modified

- `monitoring/controllers/base/fluent-bit/namespace.yaml` - Monitoring namespace definition (excluded from kustomization per conflict pattern)
- `monitoring/controllers/base/fluent-bit/repository.yaml` - fluent HelmRepository pointing to fluent.github.io/helm-charts
- `monitoring/controllers/base/fluent-bit/release.yaml` - Fluent Bit HelmRelease 0.48.3 as DaemonSet with Loki output
- `monitoring/controllers/base/fluent-bit/kustomization.yaml` - Base kustomization (repository + release only, no namespace)
- `monitoring/controllers/staging/fluent-bit/kustomization.yaml` - Staging overlay referencing base with monitoring namespace
- `monitoring/controllers/staging/kustomization.yaml` - Added fluent-bit to resources list
- `monitoring/configs/staging/kube-prometheus-stack/loki-datasource.yaml` - Grafana datasource ConfigMap for Loki
- `monitoring/configs/staging/kube-prometheus-stack/kustomization.yaml` - Added loki-datasource.yaml to resources

## Decisions Made

- `namespace.yaml` excluded from the fluent-bit base kustomization (same pattern as loki Plan 01): including it causes a duplicate `Namespace/monitoring` conflict when kustomize merges all three controller overlays (kube-prometheus-stack, loki, fluent-bit). The monitoring namespace is owned by kube-prometheus-stack.
- A separate `fluent` HelmRepository is required — Fluent Bit is hosted at `fluent.github.io/helm-charts`, distinct from the `grafana` HelmRepository at `grafana.github.io/helm-charts` that serves Loki.
- `grafana_datasource: "1"` label on the ConfigMap triggers Grafana's sidecar container to auto-provision the datasource without any manual Grafana UI steps or kube-prometheus-stack HelmRelease changes.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Excluded namespace.yaml from base kustomization**
- **Found during:** Task 1 (Fluent Bit HelmRelease)
- **Issue:** The plan's `kustomization.yaml` includes `namespace.yaml` in resources. Phase 13-01 established that including a Namespace/monitoring resource causes a duplicate conflict when merged with kube-prometheus-stack and loki overlays in staging. Including it would cause `kustomize build` to fail.
- **Fix:** Followed the loki precedent — excluded `namespace.yaml` from `kustomization.yaml`, keeping only `repository.yaml` and `release.yaml`. The namespace.yaml file is still created for documentation/reference but not included in the build.
- **Files modified:** monitoring/controllers/base/fluent-bit/kustomization.yaml
- **Verification:** `kubectl kustomize monitoring/controllers/staging/` exits 0
- **Committed in:** cfada45 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 2 — missing critical: prevented kustomize build failure)
**Impact on plan:** Necessary correctness fix following the established pattern from Plan 01. No functional scope change — Fluent Bit still deploys to the monitoring namespace via the staging overlay's namespace field.

## Issues Encountered

None — both tasks executed cleanly following the established patterns from Phase 13 Plan 01.

## User Setup Required

None - no external service configuration required. FluxCD will apply these manifests automatically once the PR is merged to main.

## Next Phase Readiness

- Fluent Bit + Loki data pipeline is complete: logs flow from pods → Fluent Bit → Loki
- Grafana Explore tab will show Loki as a datasource after FluxCD applies
- Ready for Phase 13 Plan 03: Gatus uptime monitoring

---
*Phase: 13-observability-stack-loki-fluent-bit-gatus*
*Completed: 2026-04-11*
