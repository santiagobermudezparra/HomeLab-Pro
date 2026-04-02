# Project State

## Current Position

**Phase:** Storage scalability investigation (pre-milestone)
**Plan:** —
**Status:** Investigation complete — ready to define milestone
**Last activity:** 2026-04-03 — Storage investigation updated (v4), worker-01 disk verified (82% NVMe), both nodes disk-constrained

---

## Accumulated Context

GSD structure in place. Storage investigation is complete with enough context to define a milestone.

**Completed:**
- ✅ Project context captured (PROJECT.md)
- ✅ GSD workflow configured
- ✅ Storage investigation v4 complete (STORAGE_INVESTIGATION.md)
- ✅ Worker-01 disk verified: 233GB NVMe, 179GB used (82%)

**Key decisions made this session:**
- Per-app PVC isolation is correct — do not change this pattern
- Disk crisis is from K3s/Docker image caches, not PVCs (~90GB K3s cache estimated)
- Worker-02 should be a **Proxmox VM** (not bare metal) — unlocks Proxmox CSI long-term
- Recommended storage path: Longhorn (3-node) over NFS, once worker-02 is stable

**Open before planning:**
- Worker-01 disk usage unknown (SSH needs password)
- Proxmox host physical disk layout unknown
- Whether GNOME/desktop on control-plane is intentional

---

## Recommended Next Steps

### Today
1. Clean control-plane disk (`docker system prune -a --volumes`, `journalctl --vacuum`, `k3s crictl rmi --prune`)
2. Add worker-02 as Proxmox VM and join K3s cluster

### This Week
3. Define storage milestone via `/gsd:new-milestone`
4. Plan NFS or Longhorn deployment phase

### Month Out
5. Deploy Longhorn once 3-node cluster is stable
6. Migrate non-DB workloads to Longhorn first
7. Migrate CNPG clusters via backup/restore

---

## Session Checkpoints

- **2026-04-03 Initial:** GSD structure created on `gsd/init-milestone-planning` branch
- **2026-04-03 Session 2:** Storage investigation updated to v3 with live data, worker-02 recommendation added
