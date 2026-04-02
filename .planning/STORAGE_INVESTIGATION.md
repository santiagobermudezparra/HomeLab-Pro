# Storage Scalability Investigation Report

**Date:** 2026-04-03 (v5 — cleanup complete, 3-node Proxmox cluster strategy added)
**Project:** HomeLab-Pro Kubernetes Cluster

---

## Executive Summary

**Immediate crisis resolved.** Control-plane cleaned from 77% → 33% (69GB recovered). All pods intact.

**Structural path:** The best long-term storage solution is a **3-node Proxmox cluster with Ceph**, giving Kubernetes replicated, enterprise-grade block storage via the Proxmox CSI driver. This requires installing Proxmox on worker-01 (bare metal) and worker-02 — both become Proxmox nodes.

---

## Cluster Nodes (Fully Verified)

| Node | Role | CPU | RAM | Disk | Used | Virtualization |
|------|------|-----|-----|------|------|----------------|
| `santi-standard-pc-i440fx-piix-1996` | Control-plane | 8 vCPU | 28GB | 167GB vdisk | **53GB (33%)** ✅ cleaned | KVM VM inside Proxmox host |
| `homelab-worker-01` | Worker | 6 CPU | 16GB | 233GB NVMe | **179GB (82%)** | Bare-metal Ubuntu 24.04 |
| `worker-02` | Worker (adding today) | TBD | TBD | TBD | — | To be set up |

---

## Stage 1: Disk Cleanup — COMPLETE ✅

**Executed 2026-04-03. No pods were affected.**

| Action | Recovered | Method |
|--------|-----------|--------|
| K3s containerd image cache (`k3s crictl rmi --prune`) | ~62GB | Removed unused K3s images |
| Docker images, stopped containers, build cache (`docker system prune -a --volumes`) | 7.3GB | Dev images only — K3s unaffected |
| systemd journal | <500MB cap in place | `journalctl --vacuum-size=500M` |
| **Total recovered** | **~69GB** | |

**Before:** 122GB used (77%) → **After:** 53GB used (33%). Control-plane has 107GB free.

All 44 running pods verified healthy before and after. Only pre-existing Renovate cron errors present (unrelated to cleanup).

---

## Long-Term Storage Architecture: 3-Node Proxmox Cluster with Ceph

### The Vision

```
Physical Machine 1 (already Proxmox)
  └── K3s control-plane VM (current)

Physical Machine 2 (worker-01, bare metal today → Proxmox after migration)
  └── K3s worker-01 VM

Physical Machine 3 (worker-02, new)
  └── K3s worker-02 VM

Proxmox Cluster (3 nodes)
  └── Ceph distributed storage pool (data replicated across all 3 machines)
       └── Proxmox CSI driver → Kubernetes PVCs backed by Ceph
```

### Why This is the Best Setup

| Factor | 3-node Proxmox + Ceph | Longhorn | NFS |
|--------|-----------------------|----------|-----|
| Storage performance | Block device, no overhead | Block with replication overhead | Network filesystem (worst) |
| CNPG (PostgreSQL) compatible | ✅ Yes | ✅ Yes | ❌ Risk of data corruption |
| Survives 1 node failure | ✅ Yes (Ceph replication) | ✅ Yes (replicas=2+) | ❌ No (SPOF) |
| Centralized management | ✅ Proxmox UI | Longhorn UI (K8s only) | Manual |
| VM snapshot + backup | ✅ Proxmox handles VMs + storage | Storage only | No |
| Expandable disks | ✅ Resize vdisk in Proxmox UI | Manual | Manual |
| Live VM migration | ✅ Proxmox vMotion | N/A | N/A |
| K8s storage dynamic provisioning | ✅ Proxmox CSI | ✅ Longhorn | ✅ NFS provisioner |
| Setup complexity | High (one-time) | Medium | Low |

**The decisive advantage:** With all 3 physical machines running Proxmox, you get one unified management plane for both compute (VMs) and storage (Ceph). Adding capacity in the future = add a disk to Proxmox or add a 4th Proxmox node. Kubernetes just sees PVCs appearing — no changes to K8s config.

### Does Installing Proxmox on Worker-01 Work?

**Yes, absolutely.** Worker-01 is bare-metal Ubuntu — you can wipe it and install Proxmox. The process:

1. **Drain worker-01 from K8s first** — move all workloads to other nodes
2. **Wipe and install Proxmox** on the physical machine
3. **Create a K3s worker VM** inside the new Proxmox
4. **Rejoin the K3s cluster** from inside the new VM
5. **Reschedule workloads** back onto it

The NVMe drive (`/dev/nvme0n1`) becomes a Proxmox storage pool — fast Ceph OSD disk.

**Critical note:** The 5 PVCs currently on worker-01 (filebrowser, n8n-data, n8n-postgres, pgadmin) will be **lost** when you wipe the machine. You must migrate them first.

---

## Migration Plan for Worker-01 → Proxmox

This is a future milestone, not today. Capture the steps here for planning.

### Pre-migration: Move PVCs off Worker-01

Worker-01 currently holds:
- `filebrowser-files` (5Gi) — file data
- `filebrowser-db` (1Gi)
- `n8n-data` (2Gi)
- `n8n-postgresql-cluster-1` (2Gi) — CNPG database
- `pgadmin-data-pvc` (1Gi)

**Non-CNPG workloads (filebrowser, n8n-data, pgadmin):** Can use a PVC migration tool (Velero or manual rsync) to copy to control-plane or new worker-02.

**CNPG databases (n8n-postgres):** Requires backup → restore to new cluster. See CNPG migration section.

### Migration Steps (Future Milestone)

```
Phase A: Deploy worker-02 + establish baseline (today)
Phase B: Install Longhorn on 3 nodes OR set up NFS temporarily (week 1-2)
Phase C: Migrate worker-01 PVCs to Longhorn/NFS (week 2)
Phase D: Drain and wipe worker-01, install Proxmox (week 3)
Phase E: Rejoin worker-01 as VM inside new Proxmox (week 3)
Phase F: Form 3-node Proxmox cluster, deploy Ceph (month 2)
Phase G: Deploy Proxmox CSI, migrate storage from Longhorn → Ceph (month 2-3)
```

---

## Today's Immediate Plan (Worker-02)

**Make worker-02 a Proxmox VM** (aligns with the 3-node Proxmox goal):

1. In the Proxmox UI, create new VM:
   - CPU: 4–6 vCPU
   - RAM: 8–16GB
   - **Disk: 500GB+** (this becomes the main capacity add for the cluster)
   - Network: virtio bridge
   - OS: Ubuntu 24.04 LTS

2. Install Ubuntu 24.04, then join K3s:
```bash
# Get token from control-plane first:
sudo cat /var/lib/rancher/k3s/server/node-token

# On worker-02:
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.1.115:6443 K3S_TOKEN=<token> sh -
```

3. Verify:
```bash
kubectl get nodes
```

Do **not** deploy storage yet — let the node stabilize for a few days.

---

## Intermediate Storage: Longhorn (3-Node, Before Proxmox Ceph)

While the Proxmox migration of worker-01 is being planned, deploy Longhorn as the interim shared storage layer. It works on mixed hardware (Proxmox VM + bare metal) and will handle all workloads including CNPG databases.

Deploy via FluxCD:
```
infrastructure/
└── storage/
    └── longhorn/
        ├── namespace.yaml
        ├── helmrelease.yaml      # Longhorn Helm chart
        └── storageclass.yaml     # longhorn StorageClass (set as default)
```

Migration order (safest first):
1. `pgadmin`, `homarr`, `homepage` — low risk, minimal data
2. `mealie`, `filebrowser` — important but simple migration
3. `audiobookshelf` — larger config volume
4. CNPG clusters (`linkding-postgres`, `n8n-postgres`) — requires backup/restore process

---

## CNPG Database Migration (When Changing StorageClass)

CloudNativePG databases cannot be migrated by copying PVCs. Correct process:

```bash
# 1. Create backup
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: n8n-pre-migration
  namespace: n8n
spec:
  cluster:
    name: n8n-postgresql-cluster
EOF

# 2. Wait for completion
kubectl get backup n8n-pre-migration -n n8n -w

# 3. Bootstrap new cluster with new storageClass pointing to backup
# 4. Update app secrets/configmaps to new cluster service name
# 5. Verify data, delete old cluster
```

Time per database: ~30–60 minutes with downtime. Do linkding and n8n separately.

---

## Cleanup Commands Reference

```bash
# K3s image cache (run periodically when disk fills up — safe at any time)
sudo k3s crictl rmi --prune

# Docker dev images (safe — separate from K3s)
docker system prune -a --volumes

# Journal logs
sudo journalctl --vacuum-size=500M

# Snap old revisions
snap list --all | awk '/disabled/{print $1, $3}' | \
  while read name rev; do sudo snap remove "$name" --revision="$rev"; done

# Check disk
df -h /
```

**Safe to run at any time.** None of these touch running pods, PVCs, or databases.

---

## Current State Summary

```
Control-plane:  167GB | 53GB used  (33%) ✅  — healthy after cleanup
Worker-01:      233GB | 179GB used (82%)  ⚠️  — needs PVC migration before Proxmox install
Worker-02:      adding today              —  — set as Proxmox VM, 500GB+ disk

StorageClass:   local-path (only one — all PVCs node-local)
Total PVCs:     ~19Gi across 2 nodes
Goal:           3-node Proxmox cluster → Ceph → Proxmox CSI (long-term)
Interim:        Longhorn (once worker-02 is stable)
```

---

## Open Questions

1. **Proxmox host disk layout** — how much free space does the physical Proxmox machine have? Determines how large the control-plane VM disk can be expanded and if there's room for a Ceph OSD.
2. **Is GNOME/desktop intentional on control-plane?** — K3s image prune will need to be re-run periodically (~every 2-3 months) as long as the desktop stays on this VM. Consider moving desktop to a dedicated VM.
3. **Worker-02 hardware specs** — what physical machine is this? Affects how large the VM can be.

---

**Investigation v5 — 2026-04-03**
**Changes from v4:** Cleanup complete (69GB recovered, 77%→33%), added 3-node Proxmox+Ceph strategy, added worker-01 migration plan, added Longhorn as interim layer, updated current state.
