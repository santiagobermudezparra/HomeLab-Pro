---
phase: 10-networkpolicies-per-namespace-isolation
plan: "01"
subsystem: infra
tags: [kubernetes, networkpolicy, cilium, security, namespace-isolation]

# Dependency graph
requires: []
provides:
  - NetworkPolicy manifests for all 8 app namespaces in apps/base/
  - default-deny-ingress per namespace (SEC-03)
  - Explicit allow rules: same-namespace, monitoring scraping, CNPG controller, Traefik ingress (SEC-04)
  - SEC-05 preserved: flux-system imperative NetworkPolicies left untouched
affects:
  - phase 10 plan 02 (staging overlay verification / FluxCD sync)
  - any future app onboarding (establishes NetworkPolicy template pattern)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "3-policy baseline per namespace: default-deny-ingress + allow-same-namespace + allow-monitoring-scraping"
    - "CNPG namespaces add allow-cnpg-controller targeting cnpg.io/podRole: instance pods from cnpg-system"
    - "Traefik namespaces add allow-traefik-ingress using combined namespaceSelector+podSelector (AND semantics)"

key-files:
  created:
    - apps/base/audiobookshelf/network-policy.yaml
    - apps/base/filebrowser/network-policy.yaml
    - apps/base/mealie/network-policy.yaml
    - apps/base/pgadmin/network-policy.yaml
    - apps/base/linkding/network-policy.yaml
    - apps/base/n8n/network-policy.yaml
    - apps/base/homepage/network-policy.yaml
    - apps/base/xm-spotify-sync/network-policy.yaml
  modified:
    - apps/base/audiobookshelf/kustomization.yaml
    - apps/base/filebrowser/kustomization.yaml
    - apps/base/mealie/kustomization.yaml
    - apps/base/pgadmin/kustomization.yaml
    - apps/base/linkding/kustomization.yaml
    - apps/base/n8n/kustomization.yaml
    - apps/base/homepage/kustomization.yaml
    - apps/base/xm-spotify-sync/kustomization.yaml

key-decisions:
  - "Traefik allow rule uses combined namespaceSelector+podSelector (single from-entry, AND semantics) to restrict to Traefik pods in kube-system only, not all kube-system pods"
  - "CNPG allow-cnpg-controller targets cnpg.io/podRole: instance pods specifically, not all pods in the namespace"
  - "xm-spotify-sync allow-same-namespace covers cloudflared (same ns), allow-traefik-ingress covers Traefik — no separate cloudflared policy needed"
  - "flux-system NetworkPolicies left untouched — they exist imperatively in cluster, not in git (SEC-05 is preservation, not creation)"

patterns-established:
  - "NetworkPolicy baseline: 3 policies for cloudflared-only apps, 4 for CNPG or Traefik apps"
  - "All policies placed in apps/base/{ns}/network-policy.yaml for reuse across environments"
  - "kustomize resources list: network-policy.yaml appended at end of existing resources"

requirements-completed: [SEC-03, SEC-04, SEC-05]

# Metrics
duration: 15min
completed: 2026-04-11
---

# Phase 10 Plan 01: NetworkPolicies — Per-Namespace Isolation Summary

**8 Kubernetes NetworkPolicy manifests created with default-deny-ingress plus targeted allow rules for cloudflared (same-ns), Prometheus scraping, CNPG controller, and Traefik ingress — isolating all app namespaces from unauthorized cross-namespace traffic**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-11T00:00:00Z
- **Completed:** 2026-04-11T00:15:00Z
- **Tasks:** 4 (3 create, 1 validate)
- **Files modified:** 16 (8 created, 8 updated)

## Accomplishments
- Created 8 network-policy.yaml files in apps/base/ covering all homelab app namespaces
- Each namespace gets default-deny-ingress as baseline (implements SEC-03)
- Explicit allow rules tailored per namespace: same-namespace for cloudflared, monitoring namespace for Prometheus, cnpg-system for CNPG controller, kube-system+traefik for Traefik ingress (implements SEC-04)
- All 8 kustomize builds pass with correct NetworkPolicy counts (3 per basic namespace, 4 per CNPG/Traefik namespace)
- flux-system imperative NetworkPolicies preserved untouched (SEC-05)

## Task Commits

Each task was committed atomically:

1. **Task 1: NetworkPolicies for cloudflared-only namespaces** - `b934d7c` (feat)
2. **Task 2: NetworkPolicies for CNPG namespaces (linkding, n8n)** - `7565680` (feat)
3. **Task 3: NetworkPolicies for Traefik-accessed namespaces (homepage, xm-spotify-sync)** - `9ff0a99` (feat)
4. **Task 4: Validate all kustomize builds** - validation only, no commit needed

## Files Created/Modified

- `apps/base/audiobookshelf/network-policy.yaml` - 3 policies: default-deny, allow-same-ns, allow-monitoring
- `apps/base/filebrowser/network-policy.yaml` - 3 policies: default-deny, allow-same-ns, allow-monitoring
- `apps/base/mealie/network-policy.yaml` - 3 policies: default-deny, allow-same-ns, allow-monitoring
- `apps/base/pgadmin/network-policy.yaml` - 3 policies: default-deny, allow-same-ns, allow-monitoring
- `apps/base/linkding/network-policy.yaml` - 4 policies: + allow-cnpg-controller
- `apps/base/n8n/network-policy.yaml` - 4 policies: + allow-cnpg-controller
- `apps/base/homepage/network-policy.yaml` - 4 policies: + allow-traefik-ingress
- `apps/base/xm-spotify-sync/network-policy.yaml` - 4 policies: + allow-traefik-ingress
- `apps/base/*/kustomization.yaml` (8 files) - each updated to include network-policy.yaml in resources

## Decisions Made

- Traefik allow rule uses combined namespaceSelector+podSelector in a single `from` entry (AND semantics in Kubernetes NetworkPolicy), ensuring only Traefik pods in kube-system can ingress — not all kube-system pods
- CNPG allow-cnpg-controller targets `cnpg.io/podRole: instance` pods, not all namespace pods — minimizing allowed surface
- xm-spotify-sync uses allow-same-namespace for cloudflared (same ns) and allow-traefik-ingress for Traefik — no separate cloudflared policy required
- flux-system NetworkPolicies exist imperatively in cluster (not in git) and were not touched per SEC-05 requirement

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- `kustomize` standalone binary not installed on this machine; `kubectl kustomize` was used instead and worked identically for validation

## User Setup Required

None - no external service configuration required. FluxCD will apply these NetworkPolicies automatically when the branch is merged to main.

## Next Phase Readiness

- All 8 network-policy.yaml files are in apps/base/ — ready for FluxCD to apply via staging overlay
- After merge to main, FluxCD will enforce namespace isolation cluster-wide
- Phase 10 Plan 02 (if any) or verifier can confirm policies are enforced by checking cross-namespace access is blocked

---
*Phase: 10-networkpolicies-per-namespace-isolation*
*Completed: 2026-04-11*
