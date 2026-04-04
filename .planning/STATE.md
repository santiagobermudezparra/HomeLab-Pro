---
gsd_state_version: 1.0
milestone: v2.5.1
milestone_name: milestone
status: completed
stopped_at: Completed 01-fix-fluxcd-bootstrap-race-condition/01-01-PLAN.md
last_updated: "2026-04-04T10:50:11.508Z"
progress:
  total_phases: 3
  completed_phases: 2
  total_plans: 2
  completed_plans: 2
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-04)

**Core value:** Every stateful app survives any single node failure without data loss
**Current focus:** Phase 03 — grafana-admin-password-as-sops-secret
**Milestone:** v1 — Cluster Hardening & Resilience

## Current Phase

**Phase 1: Fix FluxCD Bootstrap Race Condition**
Status: Complete — PR pending merge (`feat/phase-1-fix-fluxcd-bootstrap-race-condition`)
Stopped at: Completed 01-fix-fluxcd-bootstrap-race-condition/01-01-PLAN.md
Next action: Merge PR, then `/gsd:plan-phase 2`

## Key Decisions (Phase 01)

- FluxCD apps Kustomization now depends on `databases`, completing bootstrap chain: `infrastructure-controllers -> databases -> apps`
- No `wait: true` or healthChecks added to apps.yaml — minimal change sufficient, out of scope for this phase

## Phase Progress

| Phase | Name | Status |
|-------|------|--------|
| 1 | Fix FluxCD Bootstrap Race | ✓ Complete |
| 2 | Resource Limits — audiobookshelf | ○ Pending |
| 3 | Pin All Image Tags | ○ Pending |
| 4 | Grafana Password to Secret | ○ Pending |
| 5 | Fix Renovate Errors | ○ Pending |
| 6 | n8n Database Backup | ○ Pending |
| 7 | Fix linkding Backup Destination | ○ Pending |
| 8 | Install Longhorn Storage | ○ Pending |
| 9 | Migrate PVCs to Longhorn | ○ Pending |
| 10 | Balance Workloads to Workers | ○ Pending |
| 11 | Cilium CNI Migration | ○ Pending |
| 12 | NetworkPolicies per Namespace | ○ Pending |
| 13 | Velero Full Backup | ○ Pending |
| 14 | Headlamp Dashboard | ○ Pending |

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
- Renovate `external-host-error` on 2d-ago runs, recent runs OK — investigate in Phase 5
- Phase 11 (Cilium) is the highest-risk phase — requires maintenance window, node config changes

---
*State initialized: 2026-04-04*
