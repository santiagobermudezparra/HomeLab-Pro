---
phase: 14-pihole-network-dns-adblocking
plan: 01
subsystem: PiHole Network DNS
tags: [dns, adblocking, network-services, pihole, traefik]
dependencies:
  requires: [longhorn-storage, traefik-ingress, cert-manager]
  provides: [network-dns-service, internal-dns-resolver]
  affects: [network-queries, client-device-configuration]
tech_stack:
  - added: [pihole/pihole:latest, Traefik Ingress, cert-manager TLS]
  - patterns: [base/overlay, Kubernetes deployment, ClusterIP service]
key_files:
  - created:
      - apps/base/pihole/namespace.yaml
      - apps/base/pihole/storage.yaml
      - apps/base/pihole/deployment.yaml
      - apps/base/pihole/service.yaml
      - apps/base/pihole/kustomization.yaml
      - apps/staging/pihole/kustomization.yaml
      - apps/staging/pihole/ingress.yaml
  - modified:
      - apps/staging/kustomization.yaml
decisions:
  - "PiHole runs as single replica (1) with node affinity preferring non-control-plane nodes"
  - "Storage: 1Gi PVC with longhorn storageClass (persistent query logs and config)"
  - "Admin dashboard accessible at pihole.internal.watarystack.org via Traefik Ingress with cert-manager TLS"
  - "DNS service exposed on ClusterIP port 53 (TCP+UDP) for internal cluster DNS resolution"
  - "Resource limits: requests (100m CPU, 128Mi RAM) / limits (500m CPU, 512Mi RAM)"
metrics:
  duration_minutes: 5
  completed_date: 2026-04-12
  files_created: 7
  files_modified: 1
  tasks_completed: 3
---

# Phase 14 Plan 01: PiHole Network DNS Service Summary

## What Was Built

PiHole base manifests and staging overlay for network-wide DNS filtering and ad-blocking in the K3s cluster. PiHole provides a centralized DNS resolver with integrated ad-blocking, accessible internally via Traefik Ingress.

## Implementation Details

### Base Manifests (apps/base/pihole/)

1. **namespace.yaml** — Creates `pihole` namespace for workload isolation
2. **storage.yaml** — PersistentVolumeClaim (1Gi, longhorn storageClass) for persistent query logs and configuration
3. **deployment.yaml** — PiHole pod specification with:
   - Image: `pihole/pihole:latest`
   - Ports: DNS (53/TCP+UDP), HTTP (80/TCP) for admin dashboard
   - Environment: WEBPASSWORD=changeme, DNSMASQ_LISTENING=all, INTERFACE=0.0.0.0, IPv6=True
   - Resource requests: 100m CPU, 128Mi RAM
   - Resource limits: 500m CPU, 512Mi RAM
   - Health checks: livenessProbe + readinessProbe on HTTP /admin endpoint
   - Node affinity: prefers non-control-plane nodes (weight: 100)
   - Volume mounts: /etc/pihole (PVC) + /etc/dnsmasq.d (emptyDir)
4. **service.yaml** — ClusterIP service exposing:
   - DNS: port 53/TCP + 53/UDP
   - HTTP: port 80/TCP
5. **kustomization.yaml** — References all base manifests

### Staging Overlay (apps/staging/pihole/)

1. **kustomization.yaml** — References base pihole, sets namespace=pihole, includes ingress.yaml
2. **ingress.yaml** — Traefik Ingress configuration:
   - Hostname: `pihole.internal.watarystack.org`
   - TLS: cert-manager annotation (letsencrypt-cloudflare-prod)
   - Backend: pihole service on port 80
   - HTTP redirect middleware enabled

### Apps Staging Kustomization Update

Updated `apps/staging/kustomization.yaml` to include pihole overlay in resources list (alphabetically ordered after mealie).

## Verifications Passed

✓ All 5 base manifest files exist with correct YAML structure
✓ All 2 staging overlay files exist with correct YAML structure
✓ PVC reference (pihole-data-pvc) linked correctly in deployment
✓ Service selects correct pod label (app: pihole)
✓ Ingress backend references pihole service on port 80
✓ Staging kustomization includes pihole in resources
✓ Resource requests and limits properly configured
✓ Health check probes configured correctly
✓ Node affinity preference set for non-control-plane nodes

## Commits Created

| Commit | Message |
|--------|---------|
| 509e687 | feat(14-01): add pihole base manifests for network-wide DNS |
| 974bed4 | feat(14-01): add pihole staging overlay with Traefik ingress |
| 323cabb | feat(14-01): add pihole to staging kustomization resources |

## Deviations from Plan

None — plan executed exactly as written. All manifests follow established patterns (base/overlay, Kubernetes standard structures, matching existing app deployments like linkding and gatus).

## Known Stubs

1. **pihole/deployment.yaml, line 47** — WEBPASSWORD=changeme
   - Default password hardcoded for deployment. Should be changed post-deployment via dashboard (Admin > Settings > API/Web Interface) or rotated via new secret in future plan.
   - Reason: PiHole web UI uses independent password store (not easily injectable via K8s Secret without sidecar); changeme serves as deployment placeholder.
   - Future: Plan 14-02 (Network DNS Configuration) will document password rotation procedure.

## Next Steps

1. **Plan 14-02: Network DNS Configuration** — Configure PiHole upstream servers, whitelist/blacklist, and validate DNS resolution from pods
2. **Plan 14-03: PiHole Backup & Recovery** — Set up automated config backup and recovery procedures
3. **Future: Headlamp Dashboard** — Add PiHole to the dashboard UI once deployed

## Status

Ready for FluxCD deployment. No further action needed this plan — manifests committed to Git, awaiting FluxCD sync on main branch merge. Actual pod deployment and dashboard accessibility will be verified during cluster execute-phase.
