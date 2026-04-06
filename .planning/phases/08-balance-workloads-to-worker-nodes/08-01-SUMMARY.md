---
phase: 08-balance-workloads-to-worker-nodes
plan: "01"
subsystem: scheduling
tags: [cloudflared, topology, scheduling, kubernetes]
dependency_graph:
  requires: []
  provides: [SCHED-02]
  affects: [linkding, mealie, pgadmin, audiobookshelf, homepage, n8n, filebrowser]
tech_stack:
  added: []
  patterns: [topologySpreadConstraints, pod-spread, kubernetes.io/hostname]
key_files:
  created: []
  modified:
    - apps/staging/linkding/cloudflare.yaml
    - apps/staging/mealie/cloudflare.yaml
    - apps/staging/pgadmin/cloudflare.yaml
    - apps/staging/audiobookshelf/cloudflare.yaml
    - apps/staging/homepage/cloudflare.yaml
    - apps/staging/n8n/cloudflare.yaml
    - apps/staging/filebrowser/cloudflare.yaml
decisions:
  - "topologyKey: kubernetes.io/hostname chosen — dynamic, works for any node count, no hardcoded names"
  - "whenUnsatisfiable: DoNotSchedule — prefer not scheduling over violating spread constraint"
  - "maxSkew: 1 — at most 1 pod difference between nodes for even distribution"
metrics:
  duration: "2m 9s"
  completed_date: "2026-04-06"
  tasks_completed: 3
  files_modified: 7
---

# Phase 08 Plan 01: Add topologySpreadConstraints to cloudflared Deployments Summary

**One-liner:** topologySpreadConstraints with `topologyKey: kubernetes.io/hostname` and `maxSkew: 1` added to all 7 active cloudflared Deployments so replicas spread dynamically across the 3-node cluster.

## What Was Built

Added `topologySpreadConstraints` to the `spec.template.spec` of 7 cloudflared Deployments across all active apps. Each deployment now has 2 replicas that will be spread across different nodes (not all landing on control-plane) as the cluster scales or reconciles.

The constraint block added to each file:

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: cloudflared
```

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add topologySpreadConstraints to linkding, mealie, pgadmin | 2018964 | apps/staging/linkding/cloudflare.yaml, apps/staging/mealie/cloudflare.yaml, apps/staging/pgadmin/cloudflare.yaml |
| 2 | Add topologySpreadConstraints to audiobookshelf, homepage, n8n, filebrowser | c80a402 | apps/staging/audiobookshelf/cloudflare.yaml, apps/staging/homepage/cloudflare.yaml, apps/staging/n8n/cloudflare.yaml, apps/staging/filebrowser/cloudflare.yaml |
| 3 | Create branch and open PR | (no separate commit — changes on feat/phase-08-balance-workloads) | PR #45 |

## Verification Results

- All 7 cloudflare.yaml files contain `topologySpreadConstraints`
- All 7 files contain `topologyKey: kubernetes.io/hostname`
- No hardcoded node names (`nodeName`, `worker-01`, `worker-02`) in any file
- All 6 kustomize builds pass (linkding, mealie, pgadmin, audiobookshelf, n8n, filebrowser)
- PR #45 open: https://github.com/santiagobermudezparra/HomeLab-Pro/pull/45

## Decisions Made

- `topologyKey: kubernetes.io/hostname` — dynamic key that works for any node count, never requires updating when nodes are added
- `whenUnsatisfiable: DoNotSchedule` — prevents replica co-location rather than allowing it with a warning; appropriate for HA tunnels
- `maxSkew: 1` — at most 1 pod difference between nodes, ensures even spread across all 3 nodes

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all 7 files are fully wired with real topologySpreadConstraints. No placeholder values.

## Self-Check: PASSED

Files verified:
- apps/staging/linkding/cloudflare.yaml — FOUND, contains topologySpreadConstraints
- apps/staging/mealie/cloudflare.yaml — FOUND, contains topologySpreadConstraints
- apps/staging/pgadmin/cloudflare.yaml — FOUND, contains topologySpreadConstraints
- apps/staging/audiobookshelf/cloudflare.yaml — FOUND, contains topologySpreadConstraints
- apps/staging/homepage/cloudflare.yaml — FOUND, contains topologySpreadConstraints
- apps/staging/n8n/cloudflare.yaml — FOUND, contains topologySpreadConstraints
- apps/staging/filebrowser/cloudflare.yaml — FOUND, contains topologySpreadConstraints

Commits verified:
- 2018964 — FOUND (Task 1)
- c80a402 — FOUND (Task 2)

PR verified:
- PR #45 OPEN targeting main
