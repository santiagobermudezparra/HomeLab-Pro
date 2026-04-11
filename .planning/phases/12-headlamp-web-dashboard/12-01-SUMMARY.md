---
phase: 12-headlamp-web-dashboard
plan: "01"
subsystem: infra
tags: [headlamp, kubernetes, dashboard, traefik, rbac, networkpolicy, homepage, kustomize]

requires:
  - phase: 10-network-policies
    provides: NetworkPolicy four-policy pattern (default-deny, same-ns, monitoring, traefik)
  - phase: 06-longhorn-storage
    provides: Traefik Ingress with cert-manager pattern established

provides:
  - Headlamp Kubernetes dashboard deployed at headlamp.internal.watarystack.org
  - Read-only ClusterRole + ClusterRoleBinding for cluster visibility
  - NetworkPolicies isolating headlamp namespace
  - Homepage auto-discovery via gethomepage.dev Ingress annotations
  - FluxCD kustomization wiring via apps/staging/

affects: [homepage-dashboard, flux-wiring, monitoring]

tech-stack:
  added: [ghcr.io/headlamp-k8s/headlamp:v0.26.0]
  patterns: [base/overlay kustomize, traefik-ingress-with-tls, four-policy-networkpolicy, homepage-ingress-annotation-discovery]

key-files:
  created:
    - apps/base/headlamp/namespace.yaml
    - apps/base/headlamp/deployment.yaml
    - apps/base/headlamp/service.yaml
    - apps/base/headlamp/rbac.yaml
    - apps/base/headlamp/network-policy.yaml
    - apps/base/headlamp/kustomization.yaml
    - apps/staging/headlamp/ingress.yaml
    - apps/staging/headlamp/kustomization.yaml
  modified:
    - apps/staging/kustomization.yaml

key-decisions:
  - "Headlamp uses --in-cluster flag with a dedicated ServiceAccount + ClusterRole (not token-based); RBAC is read-only covering all workload resources"
  - "readOnlyRootFilesystem: true with no tmpfs — Headlamp v0.26.0 serves static files from binary, no writable filesystem needed"
  - "gethomepage.dev/group: Infrastructure (not Cluster Management) — Headlamp is infrastructure tooling distinct from Homepage itself"
  - "No separate gethomepage.dev/href annotation needed — Homepage derives href from Ingress host rule when gethomepage.dev/enabled: true"

patterns-established:
  - "Headlamp RBAC pattern: ServiceAccount + ClusterRole (read-only) + ClusterRoleBinding in single rbac.yaml multi-doc"
  - "Homepage auto-discovery for Traefik apps: gethomepage.dev/enabled, name, description, group, icon annotations on Ingress"

requirements-completed: [OBS-01]

duration: 15min
completed: 2026-04-11
---

# Phase 12 Plan 01: Headlamp Web Dashboard Summary

**Headlamp v0.26.0 deployed via Traefik Ingress at headlamp.internal.watarystack.org with read-only ClusterRole RBAC, four-policy NetworkPolicy isolation, and Homepage auto-discovery annotations**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-11T00:00:00Z
- **Completed:** 2026-04-11T00:15:00Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments

- Full Headlamp base manifest set: namespace, deployment, service, RBAC (ServiceAccount + ClusterRole + ClusterRoleBinding), NetworkPolicy (four-policy pattern), kustomization
- Staging overlay with Traefik Ingress at headlamp.internal.watarystack.org, cert-manager TLS, and gethomepage.dev annotations for Homepage auto-discovery
- FluxCD wired via apps/staging/kustomization.yaml — Headlamp will reconcile on next flux sync after PR merge

## Task Commits

1. **Task 1: Create Headlamp base manifests** - `12311db` (feat)
2. **Task 2: Create staging overlay + wire into FluxCD** - `5936fc7` (feat)

## Files Created/Modified

- `apps/base/headlamp/namespace.yaml` - Headlamp namespace definition
- `apps/base/headlamp/deployment.yaml` - Headlamp pod spec (ghcr.io/headlamp-k8s/headlamp:v0.26.0, port 4466, --in-cluster flag)
- `apps/base/headlamp/service.yaml` - ClusterIP service on port 4466
- `apps/base/headlamp/rbac.yaml` - ServiceAccount + ClusterRole (read-only) + ClusterRoleBinding
- `apps/base/headlamp/network-policy.yaml` - Four-policy NetworkPolicy (default-deny, same-ns, monitoring, traefik)
- `apps/base/headlamp/kustomization.yaml` - Base kustomization wiring all five resources
- `apps/staging/headlamp/ingress.yaml` - Traefik Ingress at headlamp.internal.watarystack.org with TLS + Homepage annotations
- `apps/staging/headlamp/kustomization.yaml` - Staging overlay referencing base + ingress
- `apps/staging/kustomization.yaml` - Added `- headlamp` to resources list

## Decisions Made

- Headlamp uses `--in-cluster` flag with a dedicated ServiceAccount + read-only ClusterRole — no token secrets needed, cleaner RBAC than token-based approach
- `readOnlyRootFilesystem: true` with no tmpfs — Headlamp v0.26.0 serves static files embedded in binary, no writable filesystem required
- `gethomepage.dev/group: Infrastructure` chosen over "Cluster Management" — Headlamp is infrastructure tooling; differentiates from Homepage itself in the dashboard
- No `gethomepage.dev/href` annotation needed — Homepage derives the URL from the Ingress host rule automatically when `gethomepage.dev/enabled: "true"` is set (consistent with existing codebase pattern)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None — `kustomize` binary not on PATH but `kubectl kustomize` was available; used that for verification. Both `kubectl kustomize` and `kubectl apply --dry-run=client` exited 0.

## User Setup Required

None - no external service configuration required. After PR merge, FluxCD will reconcile headlamp automatically. Access at `headlamp.internal.watarystack.org` requires `/etc/hosts` entry pointing to Traefik LAN IP (192.168.1.115).

## Next Phase Readiness

- Phase 12 Plan 01 complete — all Headlamp manifests committed and kustomize-validated
- Ready for PR merge and live cluster verification
- OBS-01 satisfied: cluster visibility (namespaces, pods, workloads) via web UI without kubectl

---
*Phase: 12-headlamp-web-dashboard*
*Completed: 2026-04-11*
