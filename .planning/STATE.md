---
gsd_state_version: 1.0
milestone: v2.5.1
milestone_name: milestone
status: in-progress
stopped_at: "Completed 06-02-PLAN.md"
last_updated: "2026-04-05T06:41:42.385Z"
progress:
  total_phases: 12
  completed_phases: 4
  total_plans: 8
  completed_plans: 5
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-04)

**Core value:** Every stateful app survives any single node failure without data loss
**Current focus:** Phase 06 — install-longhorn-distributed-storage (Plans 01 and 02 complete, Plan 03 next)
**Milestone:** v1 — Cluster Hardening & Resilience

## Current Phase

**Phase 4: n8n Database Backup**
Status: Complete — Verification checkpoint approved
Stopped at: Completed 06-02-PLAN.md
Next action: `/gsd:plan-phase 5`

## Key Decisions (Phase 01)

- FluxCD apps Kustomization now depends on `databases`, completing bootstrap chain: `infrastructure-controllers -> databases -> apps`
- No `wait: true` or healthChecks added to apps.yaml — minimal change sufficient, out of scope for this phase

## Key Decisions (Phase 06, Plan 01)

- Longhorn v1.7.3 iscsi-installer DaemonSet deployed as permanent fixture (not Job) so new nodes automatically get open-iscsi
- Staging overlay has no secrets — iscsi-installer requires no credentials, simpler than cert-manager overlay
- Manifests follow base/overlay pattern matching cert-manager and cloudnative-pg exactly

## Key Decisions (Phase 06, Plan 02)

- Longhorn 1.7.3 version pinned (research date 2026-04-05); re-verify if >30 days before deploying
- Both replica count fields required: `persistence.defaultClassReplicaCount: 2` (K8s StorageClass parameters) AND `defaultSettings.defaultReplicaCount: "2"` (must be string, Longhorn UI default)
- Ingress section omitted from release.yaml — handled in Plan 03 overlay (consistent with linkding pattern)
- ServiceMonitor label `release: kube-prometheus-stack` matches live cluster's serviceMonitorSelector confirmed via kubectl
- FluxCD reconciliation and smoke tests are post-merge concerns (GitOps constraint: FluxCD tracks main branch only)

## Phase Progress

| Phase | Name | Status |
|-------|------|--------|
| 1 | Fix FluxCD Bootstrap Race | ✓ Complete |
| 2 | Resource Limits — audiobookshelf | ○ Pending |
| 3 | Grafana Password to SOPS Secret | ○ Pending |
| 4 | n8n Database Backup | ✓ Complete |
| 5 | Fix linkding Backup Destination | ○ Pending |
| 6 | Install Longhorn Storage | ○ Pending |
| 7 | Migrate PVCs to Longhorn | ○ Pending |
| 8 | Balance Workloads to Workers | ○ Pending |
| 9 | Cilium CNI Migration | ○ Pending |
| 10 | NetworkPolicies per Namespace | ○ Pending |
| 11 | Velero Full Backup | ○ Pending |
| 12 | Headlamp Dashboard | ○ Pending |

## Cluster Snapshot (2026-04-04)

- **FluxCD**: v2.5.1, all 7 kustomizations synced at main@sha1:616ba732
- **K3s**: v1.30.0+k3s1 on all 3 nodes (Ubuntu 24.04)
- **Control-plane**: 11% CPU, 28% RAM (7836Mi/28GB), 21% disk (33GB/167GB)
- **Worker-01**: 0% CPU, 10% RAM — underutilized
- **Worker-02**: 0% CPU, 6% RAM — joined 18h ago, nearly empty
- **Storage**: 1 StorageClass (local-path), 11 PVCs total, all node-pinned
- **Monitoring**: kube-prometheus-stack v66.2.2, all healthy
- **HelmReleases**: 3 total, all True/healthy

## Key Context for Resuming

- Branch convention: `feat/phase-N-<slug>` off `feat/homelab-improvement`
- All secrets must be SOPS-encrypted before commit
- `apps/staging/kustomization.yaml` — homarr is commented out intentionally
- cert-manager-cainjector has 17100 restarts — monitor but not blocking
- Phase 9 (Cilium) is the highest-risk phase — requires maintenance window, node config changes

---
*State initialized: 2026-04-04*
