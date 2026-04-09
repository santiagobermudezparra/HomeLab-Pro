---
plan: 09-01
phase: 09-cilium-cni-migration
status: complete
completed: 2026-04-09
---

## Summary

Disabled Flannel CNI on all 3 nodes and opened the maintenance window for Cilium installation.

## Tasks Completed

1. **Pre-migration baseline confirmed** — All 3 nodes Ready, 3 flux-system NetworkPolicies present, BPF mounted, flannel.1 existed
2. **K3s config updated and nodes restarted** — Appended `flannel-backend: none` and `disable-network-policy: true` to `/etc/rancher/k3s/config.yaml` on control-plane; restarted k3s on control-plane and k3s-agent on both workers; deleted flannel.1 on all 3 nodes (control-plane + workers had it)

## Deviations

- Plan said to delete flannel.1 only on control-plane; workers also had flannel.1 — deleted on all 3 (required for Cilium vxlan to work without address conflict)

## Outcome

All 3 nodes in NotReady state with no active CNI. flannel.1 interface deleted on all nodes. Ready for Plan 02.
