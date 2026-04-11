# Phase 14: PiHole Network-Wide DNS & Ad-Blocking — Context

**Phase Goal:** PiHole is deployed in K3s and configured as the network's primary DNS server, providing network-wide ad-blocking and privacy protection for all devices (phones, laptops, IoT devices) without requiring per-device configuration.

**Requirements:** NET-DNS-01, NET-DNS-02, NET-DNS-03, NET-DNS-04, SEC-DNS-01

---

## Phase Scope

### Plan 14-01: PiHole Base & Staging Manifests
- Create `apps/base/pihole/` with namespace, deployment, service, kustomization.yaml
- PiHole container: `pihole/pihole:latest` (v5.18+)
- Internal Traefik Ingress at `pihole.internal.watarystack.org` for admin dashboard
- Persistent storage: 1Gi PVC for query logs and whitelist/blacklist configuration
- Port 53 (DNS) exposed via ClusterIP service (internal DNS queries)
- Port 80 (HTTP admin) exposed via service for Traefik routing
- Create `apps/staging/pihole/` overlay with any staging-specific patches
- Resource requests: 100m CPU, 128Mi RAM; limits: 500m CPU, 512Mi RAM

### Plan 14-02: Network DNS Configuration
- Determine network gateway/router IP and SSH access method
- Configure gateway to use PiHole's IP as primary DNS resolver
- Verify all DHCP clients receive PiHole IP as nameserver
- Test ad-blocking on multiple client devices (mobile, laptop, IoT)
- Document DNS resolution flow: device → PiHole → CoreDNS (cluster queries) / upstream (external)

### Plan 14-03: Grafana Dashboard & Homepage Integration
- Create Grafana dashboard showing PiHole metrics (query count, blocked %, top clients, top domains)
- Wire dashboard into existing Grafana instance (kube-prometheus-stack)
- Add PiHole entry to `apps/base/homepage/` with query stats summary
- Verify dashboard loads and shows real-time data

---

## Context: PiHole Architecture

### Network DNS Flow
```
┌─────────────┐         ┌──────────────┐         ┌────────────────┐
│ Device      │         │ PiHole       │         │ Upstream DNS   │
│ (phone/     │ --DNS→  │ (in K3s)     │ --DNS→  │ (8.8.8.8, etc) │
│ laptop/IoT) │         │              │         │                │
└─────────────┘         └──────────────┘         └────────────────┘
                              ↓
                        (cluster queries)
                              ↓
                         ┌─────────────┐
                         │ CoreDNS     │
                         │ (K3s built-in)
                         └─────────────┘
```

### Key Points
- PiHole sits upstream of K3s's CoreDNS for network devices
- CoreDNS handles cluster-internal DNS (`service.namespace.svc.cluster.local`)
- PiHole forwards non-cluster queries to upstream resolvers
- Benefits: network-wide ad-blocking, privacy (no ISP logging), query analytics, content filtering
- Persistent storage ensures query history and configuration survive pod restarts

---

## Cluster Prerequisites
- FluxCD managing all deployments (existing, verified)
- Traefik ingress controller in kube-system (existing, verified)
- cert-manager for TLS (existing, verified) — **Note**: PiHole admin dashboard uses HTTP-only on internal Traefik

---

## Success Criteria

**Done when:**
1. PiHole admin dashboard is accessible at `pihole.internal.watarystack.org`
2. Network gateway/router is configured to use PiHole IP as primary DNS
3. At least 3 client devices (phone, laptop, IoT) are resolving through PiHole
4. Ad-blocking is verified (ads blocked on client devices)
5. Grafana dashboard displays PiHole metrics (query count, blocked count, top clients/domains)
6. Homepage dashboard has PiHole entry with query stats summary
7. All manifests are in Git, changes merged to main, FluxCD synced

---

## Dependencies & Constraints
- **No breaking changes**: PiHole deployment must not affect existing apps or cluster networking
- **GitOps first**: All changes via Git → PR → FluxCD sync, never direct kubectl apply to main
- **Network access**: Gateway/router must be accessible via SSH or Web UI for DNS configuration
- **Testing scope**: Ad-blocking verification requires actual client devices (cannot mock DNS resolution fully)

---

## Known Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| PiHole pod crashes → devices lose DNS | Critical | Persistent config, resource limits, health checks in deployment |
| Gateway not responding to DNS config changes | High | Test DNS propagation with `dig @pihole.ip example.com` on multiple clients |
| Existing queries break after deployment | Medium | CoreDNS handles cluster queries; test internal DNS (`kubectl exec -it ...`) before device rollout |
| Query logs overwhelm PVC (1Gi limit) | Low | PiHole has built-in retention/cleanup; monitor with `kubectl exec pihole -- du -h /etc/pihole/` |

---

## Related Phases
- **Phase 13** (Observability): Loki/Fluent Bit for cluster-wide logs — PiHole query logs separate (local PVC)
- **Phase 9** (Cilium): If Cilium is deployed later, PiHole DNS rules must be compatible with NetworkPolicies
- **Phase 11** (Velero): Future backups should include PiHole namespace for configuration preservation

---

*Context created: 2026-04-12*
*Phase goal: Network-wide DNS & ad-blocking without per-device configuration*
