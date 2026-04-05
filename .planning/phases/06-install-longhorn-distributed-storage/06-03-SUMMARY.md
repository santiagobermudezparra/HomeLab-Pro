---
phase: 06-install-longhorn-distributed-storage
plan: 03
subsystem: infra
tags: [longhorn, traefik, ingress, kustomize, fluxcd, ui]

# Dependency graph
requires:
  - phase: 06-install-longhorn-distributed-storage/06-02
    provides: longhorn HelmRelease deploying longhorn-frontend ClusterIP service on port 80

provides:
  - Traefik Ingress routing longhorn.watarystack.org to longhorn-frontend:80 in longhorn-system
  - Updated staging overlay kustomization including ingress.yaml

affects:
  - 06-install-longhorn-distributed-storage/06-04 (demote local-path StorageClass; depends on Longhorn UI accessible for operator verification)
  - 07-migrate-pvcs-to-longhorn (PVC migration operators will use Longhorn UI to monitor progress)

# Tech tracking
tech-stack:
  added: [Traefik Ingress for longhorn-ui]
  patterns:
    - Plain HTTP Traefik Ingress (no TLS) for internal-only admin dashboards
    - Standalone ingress.yaml in staging overlay (not in base) — routing is environment-specific

key-files:
  created:
    - infrastructure/controllers/staging/longhorn/ingress.yaml
  modified:
    - infrastructure/controllers/staging/longhorn/kustomization.yaml

key-decisions:
  - "No TLS on Longhorn ingress — internal-only dashboard accessed on LAN; cert-manager annotation omitted intentionally"
  - "Matched linkding ingress pattern exactly — same spec structure, ingressClassName: traefik, pathType: Prefix"
  - "Ingress placed in staging overlay, not base — routing config is environment-specific per established convention"
  - "FluxCD reconciliation and HTTP 200 probe are post-merge concerns per GitOps constraint (FluxCD tracks main branch)"

patterns-established:
  - "Internal-only admin UIs use plain Traefik Ingress (no Cloudflare tunnel, no TLS, no secrets required)"

requirements-completed: [STOR-06]

# Metrics
duration: 2min
completed: 2026-04-05
---

# Phase 06 Plan 03: Longhorn UI Traefik Ingress Summary

**Traefik Ingress resource added to longhorn-system staging overlay routing longhorn.watarystack.org to longhorn-frontend:80; kustomize build validates cleanly with all 5 expected resource kinds**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-05T06:47:25Z
- **Completed:** 2026-04-05T06:49:17Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Created `infrastructure/controllers/staging/longhorn/ingress.yaml` — Traefik Ingress routing `longhorn.watarystack.org` to `longhorn-frontend:80`, matching the linkding ingress pattern exactly
- Updated `infrastructure/controllers/staging/longhorn/kustomization.yaml` to include `ingress.yaml` in resources list
- Validated via `kubectl kustomize` — all 5 kinds output cleanly: Namespace, DaemonSet, HelmRelease, HelmRepository, Ingress
- Pushed feature branch `worktree-agent-a202cd9c` to origin — changes ready for PR merge

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ingress.yaml and update staging overlay kustomization** - `f4c07b7` (feat)
2. **Task 2: Push to origin and document reconciliation expectations** - (push to origin; no new files — verification is post-merge per GitOps constraint)

**Plan metadata:** (created below)

## Files Created/Modified

- `infrastructure/controllers/staging/longhorn/ingress.yaml` - Traefik Ingress CR routing `longhorn.watarystack.org` to `longhorn-frontend` service port 80 in `longhorn-system` namespace; plain HTTP (no TLS), internal LAN access only
- `infrastructure/controllers/staging/longhorn/kustomization.yaml` - Added `ingress.yaml` to resources list alongside `../../base/longhorn/`

## Decisions Made

- **No TLS on Longhorn UI ingress**: This is an internal-only operator dashboard, not exposed to the internet. The cert-manager annotation (`cert-manager.io/cluster-issuer`) was intentionally omitted. Browser access requires LAN network only.
- **Matched linkding ingress pattern exactly**: Used identical spec structure (`ingressClassName: traefik`, `pathType: Prefix`, `path: /`). The only differences are name, host, service name, and port.
- **No Cloudflare tunnel**: Internal services use Traefik Ingress per the homelab pattern. Longhorn UI is operator-only and should not be internet-accessible.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

**Worktree was behind feature branch:** This agent's worktree (`worktree-agent-a202cd9c`) was based on an older commit and lacked the longhorn infrastructure files from plans 06-01 and 06-02. Resolved by merging `origin/feat/homelab-improvement` and `worktree-agent-a45fb7de` branches into the worktree branch. Merge conflicts in `.planning/STATE.md` and `.planning/REQUIREMENTS.md` were resolved by taking the most current state from the 06-02 plan branch.

**FluxCD verification is post-merge only:** FluxCD tracks the `main` branch. Since changes are on `worktree-agent-a202cd9c` (feature branch), the Ingress will not be applied until the PR is merged. The `kubectl kustomize` build confirmed manifests are structurally valid. The runtime verifications (`kubectl get ingress longhorn-ui -n longhorn-system` and HTTP 200 probe) are post-merge concerns.

This is expected and correct behavior per the project's GitOps constraint established in plans 06-01 and 06-02.

## Ingress Specification

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: longhorn-ui
  namespace: longhorn-system
spec:
  ingressClassName: traefik
  rules:
    - host: longhorn.watarystack.org
      http:
        paths:
          - backend:
              service:
                name: longhorn-frontend
                port:
                  number: 80
            path: /
            pathType: Prefix
```

## Pre-Merge Manifest Validation

```
kubectl kustomize infrastructure/controllers/staging/longhorn/
# Output kinds (verified): DaemonSet, HelmRelease, HelmRepository, Namespace, Ingress — no errors
# Ingress host: longhorn.watarystack.org
# Backend service: longhorn-frontend:80
```

## Post-Merge Verification Commands

Once the longhorn PRs (06-01, 06-02, 06-03) are merged and FluxCD reconciles, run:

```bash
# 1. Ingress exists
kubectl get ingress longhorn-ui -n longhorn-system
# Expect: longhorn-ui   traefik   longhorn.watarystack.org   192.168.1.115   80   <age>

# 2. Ingress routes to correct backend
kubectl get ingress longhorn-ui -n longhorn-system \
  -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}'
# Expect: longhorn-frontend

# 3. longhorn-frontend service exists (created by HelmRelease)
kubectl get svc longhorn-frontend -n longhorn-system
# Expect: ClusterIP service on port 80

# 4. HTTP probe via Traefik LAN IP (192.168.1.115)
curl -s -o /dev/null -w "%{http_code}" -H "Host: longhorn.watarystack.org" http://192.168.1.115/
# Expect: 200
```

## Traefik IP and Browser Access

- **Traefik LAN IP**: `192.168.1.115`
- **curl command**: `curl -H "Host: longhorn.watarystack.org" http://192.168.1.115/`
- **Expected HTTP response**: 200

For browser access on any LAN workstation, add to `/etc/hosts`:
```
192.168.1.115  longhorn.watarystack.org
```

This is an internal-only service. No Cloudflare DNS record is needed or desired.

## User Setup Required

None required at commit time. After merging the PR:
1. FluxCD will apply the Ingress within 1 minute of merge
2. For browser access, add the `/etc/hosts` entry above to each workstation
3. Monitor with: `kubectl get ingress -n longhorn-system`

## Next Phase Readiness

- Plan 04 (demote local-path StorageClass default) can proceed once this PR is merged and the Longhorn UI is verified accessible
- No blockers — manifest validated, hierarchy correct, feature branch pushed to origin

---
*Phase: 06-install-longhorn-distributed-storage*
*Completed: 2026-04-05*

## Self-Check: PASSED

All created files exist on disk and all task commits are present in git history.
