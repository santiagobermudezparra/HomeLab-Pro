---
plan: 13-03
status: complete
completed: 2026-04-11
---

## Summary

Deployed Gatus as a self-hosted status page at `status.watarystack.org` via Cloudflare Tunnel.

## What Was Built

- `apps/base/gatus/` — namespace, deployment (ghcr.io/twin/gatus:v5.12.1), service (port 8080), configmap with endpoint checks for all homelab services, kustomization
- `apps/staging/gatus/cloudflare.yaml` — cloudflared Deployment (2 replicas) + ConfigMap routing status.watarystack.org → gatus:8080
- `apps/staging/gatus/cloudflare-secret.yaml` — SOPS-encrypted tunnel credentials (tunnel: c2a903eb-4c21-4191-a94b-3ea234a53bed)
- `apps/staging/gatus/kustomization.yaml` — staging overlay wiring base + cloudflare resources
- `apps/staging/kustomization.yaml` — added gatus to staging resources
- `apps/base/homepage/homepage-configmap.yaml` — Gatus entry added to Monitoring group

## Monitored Services

Media: Audiobookshelf, Spotify Sync
Productivity: Linkding, Mealie, n8n, Filebrowser
Monitoring: Grafana, Prometheus
Infrastructure: PgAdmin, Headlamp (at headlamp.watarystack.org)

## Deviations

- Cloudflare tunnel created programmatically (not by user) — tunnel ID: c2a903eb-4c21-4191-a94b-3ea234a53bed
- User needs to add DNS CNAME in Cloudflare Dashboard: `status` → `c2a903eb-4c21-4191-a94b-3ea234a53bed.cfargotunnel.com` (proxied)
- headlamp URL updated from headlamp.internal.watarystack.org to headlamp.watarystack.org across ingress, homepage, and Gatus config

## Key Files

- apps/base/gatus/configmap.yaml — endpoint probe configuration
- apps/staging/gatus/cloudflare.yaml — tunnel routing
- apps/staging/gatus/cloudflare-secret.yaml — encrypted credentials
