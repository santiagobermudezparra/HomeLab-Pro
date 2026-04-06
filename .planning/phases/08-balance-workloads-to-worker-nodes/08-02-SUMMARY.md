---
phase: 08-balance-workloads-to-worker-nodes
plan: 02
subsystem: infra
tags: [kubernetes, scheduling, nodeaffinity, prometheus, k3s, workload-balancing]

# Dependency graph
requires:
  - phase: 08-balance-workloads-to-worker-nodes/08-01
    provides: worker node topology awareness and cloudflared pod spreading

provides:
  - nodeAffinity (soft preference) on all 8 single-replica app Deployments — worker node preference
  - nodeAffinity on Prometheus HelmRelease prometheusSpec — Prometheus prefers worker nodes
  - Role-based scheduling using DoesNotExist on node-role.kubernetes.io/control-plane label

affects:
  - phase-09-cilium-cni (CNI changes must not break label-based affinity rules)
  - phase-10-networkpolicies (per-namespace policies, pods will be on worker nodes)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - nodeAffinity preferredDuringSchedulingIgnoredDuringExecution with DoesNotExist on control-plane role label
    - Role-based scheduling (label existence/absence) not name-based scheduling
    - Prometheus HelmRelease values.prometheus.prometheusSpec.affinity for Prometheus pod placement

key-files:
  created: []
  modified:
    - apps/base/linkding/deployment.yaml
    - apps/base/mealie/deployment.yaml
    - apps/base/pgadmin/deployment.yaml
    - apps/base/filebrowser/deployment.yaml
    - apps/base/audiobookshelf/deployment.yaml
    - apps/base/homepage/deployment.yaml
    - apps/base/n8n/deployment.yaml
    - apps/base/xm-spotify-sync/deployment.yaml
    - monitoring/controllers/base/kube-prometheus-stack/release.yaml

key-decisions:
  - "Soft preference (preferredDuringSchedulingIgnoredDuringExecution, weight: 100) chosen over hard requirement — pods still schedule if workers are unavailable, preventing cluster starvation"
  - "DoesNotExist on node-role.kubernetes.io/control-plane is role-based (not name-based) — works with any node name, any cluster topology"
  - "Prometheus affinity placed under spec.values.prometheus.prometheusSpec.affinity in HelmRelease — not at chart root, not alertmanager, not grafana"

patterns-established:
  - "Worker-preference pattern: preferredDuringSchedulingIgnoredDuringExecution + DoesNotExist on control-plane role label + weight: 100"
  - "Affinity block placed before containers: in spec.template.spec for consistency across all deployments"

requirements-completed: [SCHED-01, SCHED-03]

# Metrics
duration: 12min
completed: 2026-04-06
---

# Phase 8 Plan 02: Balance Workloads — nodeAffinity for Apps and Prometheus

**Soft nodeAffinity (weight: 100, DoesNotExist on control-plane role label) added to all 8 single-replica app Deployments and Prometheus HelmRelease — pods prefer worker nodes without hardcoded node names**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-04-06T00:00:00Z
- **Completed:** 2026-04-06T00:12:00Z
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments

- All 8 app Deployments (linkding, mealie, pgadmin, filebrowser, audiobookshelf, homepage, n8n, xm-spotify-sync) have nodeAffinity preferring worker nodes
- Prometheus HelmRelease updated with `prometheusSpec.affinity` block — Prometheus pod prefers workers
- All kubectl dry-run validations pass (7 apps + monitoring stack)
- No hardcoded node names anywhere — rule is purely role-based using K3s label absence
- PR #45 open on GitHub targeting main (shared with 08-01 parallel plan)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add nodeAffinity to linkding, mealie, pgadmin, filebrowser** - `bf3a177` (feat)
2. **Task 2: Add nodeAffinity to audiobookshelf, homepage, n8n, xm-spotify-sync** - `5541f46` (feat)
3. **Task 3: Add nodeAffinity to Prometheus HelmRelease and open PR** - `e911980` (feat)

## Files Created/Modified

- `apps/base/linkding/deployment.yaml` — Added affinity block before securityContext
- `apps/base/mealie/deployment.yaml` — Added affinity block before containers
- `apps/base/pgadmin/deployment.yaml` — Added affinity block before securityContext
- `apps/base/filebrowser/deployment.yaml` — Added affinity block before initContainers
- `apps/base/audiobookshelf/deployment.yaml` — Added affinity block before securityContext
- `apps/base/homepage/deployment.yaml` — Added affinity block after automountServiceAccountToken, before dnsPolicy
- `apps/base/n8n/deployment.yaml` — Added affinity block before initContainers
- `apps/base/xm-spotify-sync/deployment.yaml` — Added affinity block before securityContext
- `monitoring/controllers/base/kube-prometheus-stack/release.yaml` — Added affinity under prometheus.prometheusSpec

## Decisions Made

- Soft preference chosen over hard requirement: `preferredDuringSchedulingIgnoredDuringExecution` instead of `requiredDuringSchedulingIgnoredDuringExecution`. This prevents scheduling failures if workers are temporarily unavailable or at capacity.
- Role-based scheduling using `DoesNotExist` operator on `node-role.kubernetes.io/control-plane` label — this is how K3s marks control-plane nodes. Worker nodes simply lack this label, so the DoesNotExist operator naturally targets them without naming any node.
- Weight of 100 (maximum) used to give scheduler the strongest possible guidance toward worker nodes.

## Deviations from Plan

None - plan executed exactly as written. The PR already existed from the 08-01 parallel agent (PR #45) targeting the same branch `feat/phase-08-balance-workloads`; no new PR was created, both plans' commits share the same PR.

## Issues Encountered

The parallel 08-01 agent had already created PR #45 for branch `feat/phase-08-balance-workloads`. The `gh pr create` command detected the existing PR and reported it. Both 08-01 and 08-02 commits are on the same branch and will be merged together via PR #45, which is the correct outcome given the parallel execution design.

## Known Stubs

None - all nodeAffinity rules are fully wired. Post-merge pod redistribution will be verified via `kubectl get pods --all-namespaces -o wide`.

## User Setup Required

None - no external service configuration required. After PR #45 is merged, FluxCD will sync and pods will be rescheduled with the new affinity preferences on their next restart.

## Next Phase Readiness

- All 8 app Deployments and Prometheus prefer worker nodes — SCHED-01 and SCHED-03 satisfied
- Post-merge: pods redistribute naturally on restart; monitor with `kubectl get pods --all-namespaces -o wide`
- Phase 09 (Cilium CNI) is next — highest risk phase, requires maintenance window

---
*Phase: 08-balance-workloads-to-worker-nodes*
*Completed: 2026-04-06*
