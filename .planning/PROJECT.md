# HomeLab-Pro: Project Context

**Project Type:** Infrastructure + GitOps | **Status:** Active | **Domain:** Kubernetes Homelab

## 🎯 Core Value

Production-grade Kubernetes homelab managed with GitOps principles. Runs on K3s with FluxCD for declarative deployments, Cloudflare Tunnels for secure external access, and SOPS/age for encrypted secrets. Demonstrates enterprise-grade practices in a personal lab environment.

## What This Is

A self-hosted Kubernetes cluster managing multiple user-facing applications and infrastructure services. Central principle: **all state in Git**, reconciled automatically by FluxCD every minute. Applications accessed via Cloudflare Tunnels (external) or Traefik Ingress (internal).

## Current Infrastructure

**Cluster:** K3s on staging environment

**Core Components:**
- FluxCD (GitOps controller)
- Kustomize (native templating)
- SOPS + age (secret encryption)
- cert-manager (automated TLS)
- Traefik (ingress + load balancer)
- Cloudflare Tunnels (external access)

**Monitoring Stack:**
- Prometheus (metrics)
- Grafana (dashboards)
- AlertManager (alert routing)

**Current Applications:**
- audiobookshelf, homarr, linkding, mealie, n8n, pgadmin, xm-spotify-sync, homepage

## Architecture Decisions

### External Access Strategy
- **Cloudflare Tunnels** for user-facing apps (zero-trust, no port forwarding)
- Each app gets its own cloudflared deployment
- CNAME records proxied via Cloudflare (orange cloud)

### Internal/Infrastructure Access
- **Traefik Ingress** with cert-manager
- DNS-01 validation via Cloudflare
- Internal services: monitoring, FluxCD

### Secret Management
- All secrets encrypted with SOPS + age (at rest in Git)
- `clusters/staging/.sops.yaml` defines age key
- FluxCD decrypts automatically in cluster via `sops-age` secret
- Encryption regex: only `data` and `stringData` fields

### Deployment Pattern
- **Base/Overlay:** Base configs in `apps/base/{app}`, environment-specific in `apps/staging/{app}`
- Each app gets namespace isolation
- Kustomize patches for environment customization
- FluxCD Kustomization resources tie everything together

## Validated Requirements (Shipped)

✅ K3s cluster with FluxCD
✅ Base/overlay app deployment pattern
✅ Cloudflare Tunnel integration (external access)
✅ SOPS secret encryption (encrypted at rest in Git)
✅ cert-manager TLS automation
✅ Traefik ingress controller
✅ Prometheus/Grafana monitoring
✅ AlertManager alert routing
✅ Multiple production applications running
✅ Automated dependency updates (Renovate)

## Current Milestone

(To be defined in `/gsd:new-milestone`)

## Key Decisions

### Why GitOps?
- Single source of truth: Git repository
- Automatic reconciliation: FluxCD syncs every 60 seconds
- Auditability: All changes tracked in Git history
- Disaster recovery: Full cluster state in Git

### Why Cloudflare Tunnels for external?
- Zero-trust security (no port forwarding)
- DDoS protection built-in
- Global CDN for performance
- Single tunnel per app (isolation)

### Why Traefik for internal?
- Direct cluster access (no external dependency)
- cert-manager integration (TLS automation)
- Multiple certificate sources
- Already running in cluster

## Out of Scope (Intentional)

- Multi-region setup
- HA/failover (single-node K3s acceptable for homelab)
- Production database backups (git-backed configs only)
- Compliance frameworks (personal lab, not enterprise)

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---

**Last Updated:** 2026-04-03 (GSD initialization)
**Created by:** Santiago Bermudez
**Project Repo:** `santiagobermudezparra/HomeLab-Pro`
