# Project State

## Current Position

**Phase:** Storage infrastructure planning (pre-milestone)
**Plan:** —
**Status:** Cleanup done, worker-02 being added, storage architecture defined
**Last activity:** 2026-04-03 — Disk cleanup complete (77%→33%), 3-node Proxmox+Ceph strategy documented

---

## Key Decisions Made

- **Per-app PVC isolation** is correct — do not change this pattern
- **Cleanup safe to re-run** — `k3s crictl rmi --prune` + `docker system prune` can be run anytime
- **Worker-02** → Proxmox VM, 500GB+ disk
- **Long-term storage** → 3-node Proxmox cluster + Ceph + Proxmox CSI driver
- **Interim storage** → Longhorn (once worker-02 stable, before Proxmox migration of worker-01)
- **CNPG migration** requires backup/restore, not PVC copy (~30-60min each, with downtime)

---

## Completed This Milestone

- ✅ Project context captured (PROJECT.md)
- ✅ GSD workflow configured
- ✅ Storage investigation complete (v5)
- ✅ Control-plane disk cleaned: 122GB → 53GB (69GB recovered, 77% → 33%)
- ✅ All 44 running pods verified healthy after cleanup

---

## Next Steps (In Order)

### Today
1. Add worker-02 as Proxmox VM (500GB+ disk, 4-6 vCPU, 8-16GB RAM)
2. Join K3s: `curl -sfL https://get.k3s.io | K3S_URL=https://192.168.1.115:6443 K3S_TOKEN=<token> sh -`
3. Verify: `kubectl get nodes`

### This Week
4. Run worker-02 stable for a few days
5. Define storage milestone: `/gsd:new-milestone`

### Week 2
6. Deploy Longhorn on 3 nodes via FluxCD
7. Migrate non-DB workloads to Longhorn StorageClass

### Month 2
8. Migrate CNPG clusters to Longhorn (backup → restore per DB)
9. Plan worker-01 → Proxmox migration

### Month 3+
10. Form 3-node Proxmox cluster
11. Deploy Ceph via Proxmox
12. Install Proxmox CSI driver
13. Migrate from Longhorn → Proxmox CSI (Ceph-backed)

---

## Context for Next Session

When resuming: check `.planning/STORAGE_INVESTIGATION.md` for full architecture.

**The plan in one line:** Add worker-02 (Proxmox VM, big disk) → Longhorn for interim shared storage → eventually all 3 physical machines run Proxmox + Ceph for unified enterprise storage.

**Worker-01 PVCs that need migrating before wiping it for Proxmox:**
- `filebrowser-files` (5Gi), `filebrowser-db` (1Gi) — rsync/Velero
- `n8n-data` (2Gi), `pgadmin-data-pvc` (1Gi) — rsync/Velero
- `n8n-postgresql-cluster-1` (2Gi) — CNPG backup/restore required

---

## Session Checkpoints

- **2026-04-03 Initial:** GSD structure created on `gsd/init-milestone-planning` branch
- **2026-04-03 Session 2:** Storage investigation v3-v4, worker-01 disk verified (82% NVMe)
- **2026-04-03 Session 3:** Cleanup complete (69GB recovered), 3-node Proxmox+Ceph strategy, STATE.md updated with full roadmap
