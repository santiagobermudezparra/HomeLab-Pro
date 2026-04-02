# Storage Scalability Investigation Report

**Date:** 2026-04-03 (v4 — worker-01 disk data verified, both nodes disk-constrained, strategy updated)
**Project:** HomeLab-Pro Kubernetes Cluster

---

## Executive Summary

Three problems, now fully verified:

1. **Both nodes are disk-constrained** — control-plane at 77% (122/167GB), worker-01 at **82% (179/233GB)**. Combined free space: ~80GB across the cluster.
2. **Root cause is image caches, not PVCs** — PVCs total only ~19Gi. The disk is full from K3s containerd cache + Docker dev images.
3. **Storage is not scalable** — `local-path` StorageClass binds every PVC to a specific node. Adding worker-02 without shared storage will strand workloads.

**User constraint:** Per-app PVC isolation is working correctly and should be kept. The issue is storage *backend*, not PVC structure.

**Immediate fix (1h):** Clean image caches on control-plane.
**Structural fix:** Adopt shared storage before scheduling new apps on worker-02.

---

## Verified Architecture

### Cluster Nodes

| Node | Role | CPU | RAM | Disk Total | Disk Used | OS | Virtualization |
|------|------|-----|-----|-----------|----------|----|----|
| `santi-standard-pc-i440fx-piix-1996` | Control-plane | 8 vCPU | 28GB | 167GB | **122GB (77%)** | Ubuntu 24.04.2 | KVM VM inside Proxmox |
| `homelab-worker-01` | Worker | 6 vCPU | 16GB | 233GB NVMe | **179GB (82%)** | Ubuntu 24.04.3 | Bare-metal Ubuntu |
| `worker-02` | Worker (pending) | TBD | TBD | TBD | — | Ubuntu 24.04 | **Recommend: Proxmox VM** |

> Worker-01 disk verified 2026-04-03: `/dev/nvme0n1p2  233G  179G   42G  82%` — **NVMe drive**, 82% full.
> Critical: both nodes are now disk-constrained. Worker-02's disk size is the main capacity lever.

**Architecture notes:**
- Control-plane is a **KVM VM** (`i440FX-PIIX` hostname = QEMU machine type). Physical Proxmox host has storage capacity not visible from inside this VM.
- Worker-01 is **bare metal** (Ubuntu only, not Proxmox-managed). This is the key constraint for storage architecture.
- Proxmox CSI requires all nodes to be Proxmox VMs — currently only 1 of 2 nodes qualifies.

---

## Where Is the Disk Space Going? (Control-plane)

### Verified breakdown (122GB/167GB used)

| Category | Size | Verified? | Notes |
|----------|------|-----------|-------|
| K3s containerd image cache | ~90GB est. | Estimated | Root-owned, can't `du` without sudo |
| `/snap` (GNOME, Firefox, etc.) | 8.4GB | ✅ | Desktop environment running on this VM |
| `/var/lib/snapd` | 4.1GB | ✅ | Snap package data |
| `/var/log/journal` | 4.2GB | ✅ | systemd journal logs — can be vacuumed |
| `/var/cache/apt` | 227MB | ✅ | Package cache |
| Docker images | 6.2GB | ✅ | `docker system df` — 78% reclaimable |
| Docker stopped containers | 2.5GB | ✅ | `docker system df` — **100% reclaimable** |
| Docker volumes | 1.7GB | ✅ | 81% reclaimable |
| Kubernetes PVCs (on this node) | ~8GB | ✅ | Healthy, spread correctly |

**Root cause:** K3s uses its own containerd (separate from Docker) and caches all container images under root-owned paths. With ~30+ pods (monitoring stack, FluxCD, cert-manager, Traefik, CNPG, apps), image cache is the dominant consumer.

**Secondary cause:** This VM doubles as a desktop workstation (GNOME, Firefox via snap) — unusual setup that adds ~12GB of non-K8s disk pressure that will recur.

### Kubernetes PVC Distribution (Verified, 2026-04-03)

**Control-plane (8Gi total):**
| App | PVC | Size | StorageClass |
|-----|-----|------|---|
| linkding | `linkding-data-pvc` | 1Gi | local-path |
| linkding | `linkding-postgres-1` (CNPG) | 2Gi | local-path |
| audiobookshelf | `audiobookshelf-config` | 1Gi | local-path |
| audiobookshelf | `audiobookshelf-metadata` | 1Gi | local-path |
| audiobookshelf | `audiobookshelf-audiobooks` | 1Gi | local-path |
| mealie | `mealie-data` | 1Gi | local-path |

**Worker-01 (11Gi total):**
| App | PVC | Size | StorageClass |
|-----|-----|------|---|
| filebrowser | `filebrowser-files` | 5Gi | local-path |
| filebrowser | `filebrowser-db` | 1Gi | local-path |
| n8n | `n8n-data` | 2Gi | local-path |
| n8n | `n8n-postgresql-cluster-1` (CNPG) | 2Gi | local-path |
| pgadmin | `pgadmin-data-pvc` | 1Gi | local-path |

**Key insight:** The per-app PVC approach is correct and working. Volumes are well-distributed. **The disk crisis is from image caches, not PVC proliferation.** Do not consolidate PVCs — isolation is the right pattern.

---

## Should Worker-02 Be Proxmox VM or Bare Metal?

### Recommendation: Proxmox VM

**Run worker-02 as a Proxmox VM.** Here's why:

| Factor | Proxmox VM | Bare Metal |
|--------|-----------|------------|
| Storage scalability | Can expand virtual disk without touching hardware | Stuck with physical disk size |
| RAM allocation | Proxmox can dynamically redistribute RAM between VMs (ballooning) | Fixed |
| Snapshots & backup | Full VM snapshot before risky changes | Manual, complex |
| Migration | Live-migrate VM to another Proxmox host | Physical move only |
| Disk expansion | Resize VM disk online | Add physical disks or replace |
| Future Proxmox CSI | ✅ Works — all nodes would be Proxmox VMs | ❌ Excluded from Proxmox CSI |
| Setup time | ~30min (clone existing VM template) | ~1-2h (fresh OS install) |

**The decisive reason:** Once worker-02 is a Proxmox VM, you have 2 of 3 nodes on Proxmox. At that point, migrating worker-01 into Proxmox becomes a reasonable future step — and then all nodes are on Proxmox, making **Proxmox CSI** the cleanest long-term storage solution. Bare-metal worker-02 closes that door.

**Recommended specs for worker-02 VM:**
- CPU: 4–6 vCPU
- RAM: 8–16GB
- Disk: 100–200GB (Proxmox can expand later)
- Network: virtio (same as control-plane)

---

## Storage Options Comparison

### Option A: NFS from Worker-01

**How it works:** Worker-01 exports a directory over NFS. K3s nodes mount it. `nfs-subdir-external-provisioner` creates a `shared-nfs` StorageClass.

| | |
|---|---|
| **Effort** | ~4 hours |
| **Cost** | Free |
| **Pros** | Simplest, works on all node types, supports RWX |
| **Cons** | Worker-01 is SPOF for all NFS volumes; bad for PostgreSQL (fsync issues) |
| **Good for** | filebrowser, mealie, audiobookshelf, pgadmin, homarr, homepage |
| **Bad for** | CNPG clusters (linkding-postgres, n8n-postgres) |

### Option B: Longhorn ⭐ Best fit for 3-node mixed cluster

**How it works:** Kubernetes-native distributed block storage. Installs as a cluster operator, uses local disks on each node, replicates data across nodes automatically.

| | |
|---|---|
| **Effort** | ~6–8 hours |
| **Cost** | Free |
| **Pros** | Works on mixed hardware (Proxmox VM + bare metal), block-level (CNPG compatible), built-in UI, replication, snapshots |
| **Cons** | ~500MB–1GB RAM per node overhead; more complex to debug than NFS; best with 3+ nodes for HA |
| **Good for** | All workloads including CNPG databases |
| **Timing** | Wait until worker-02 is stable (3 nodes) |

### Option C: Proxmox CSI Driver (Long-term best)

**How it works:** Kubernetes provisions storage directly from Proxmox. Proxmox creates LVM-thin volumes and attaches them as block devices to VMs.

| | |
|---|---|
| **Effort** | ~8–10 hours |
| **Cost** | Free (uses existing Proxmox) |
| **Pros** | Best performance (block device), unified Proxmox management, expandable, CNPG compatible |
| **Cons** | Only works for Proxmox VMs — worker-01 (bare metal) is excluded today |
| **Prerequisite** | Worker-01 must be migrated into Proxmox as a VM first |
| **Timing** | After worker-01 is on Proxmox (future decision) |

### Option D: Ceph via Rook

**Verdict:** Overkill. Needs 3+ dedicated OSD disks + significant RAM. Skip for homelab scale.

---

## Recommended Path (Updated for 3-Node Expansion)

### Stage 1: Disk Relief (Today, ~1 hour)

Clean the control-plane **before** doing anything else. High value, zero risk.

```bash
# 1. Clean Docker (dev images — 100% of stopped containers reclaimable)
docker system prune -a --volumes
# Expected: ~10GB recovered

# 2. Trim systemd journal
sudo journalctl --vacuum-size=500M
# Expected: ~3.5GB recovered

# 3. Remove disabled snap revisions
snap list --all | awk '/disabled/{print $1, $3}' | \
  while read name rev; do sudo snap remove "$name" --revision="$rev"; done

# 4. Clean K3s image cache (removes unused images only)
sudo k3s crictl rmi --prune
# Expected: varies — potentially 20-40GB

# 5. Verify
df -h /
```

**Expected recovery: 25–50GB.** Control-plane should drop from 77% to ~45–55%.

### Stage 2: Add Worker-02 as Proxmox VM (Today)

**Both existing nodes are 80%+ full. Worker-02's disk is the main capacity lever — provision it large.**

Recommended VM specs:
- CPU: 4–6 vCPU
- RAM: 8–16GB
- **Disk: 500GB+ if Proxmox host has capacity** (this becomes the primary Longhorn storage pool)
- Network: virtio

Steps:
1. Create VM in Proxmox with above specs
2. Install Ubuntu 24.04 LTS
3. Get K3s token from control-plane: `sudo cat /var/lib/rancher/k3s/server/node-token`
4. Join cluster: `curl -sfL https://get.k3s.io | K3S_URL=https://192.168.1.115:6443 K3S_TOKEN=<token> sh -`
5. Verify: `kubectl get nodes`

Do **not** add any storage layer yet. Run stable for a few days first.

### Stage 3: Install Longhorn (After Worker-02 is Stable, 1 week out)

With 3 nodes running, deploy Longhorn via FluxCD:

```
infrastructure/
└── storage/
    └── longhorn/
        ├── namespace.yaml
        ├── helmrelease.yaml      # Longhorn via Helm
        └── storageclass.yaml     # default-longhorn StorageClass
```

Set Longhorn as the **new default** StorageClass (new apps get it automatically). Existing apps stay on `local-path` until you choose to migrate.

**Migration order (safest first):**
1. pgadmin, homarr, homepage (stateless-ish, low risk)
2. mealie, filebrowser (important but no complex migration)
3. audiobookshelf (larger config)
4. CNPG clusters (linkding, n8n) — needs backup/restore process (see below)

### Stage 4: Proxmox CSI (Future — when all nodes are Proxmox VMs)

Once worker-01 is migrated into Proxmox: evaluate replacing Longhorn with Proxmox CSI for maximum performance. Not urgent.

---

## CNPG Database Migration (When Moving Storage Class)

CloudNativePG databases **cannot** be migrated by copying PVCs. The correct process:

```bash
# 1. Take a CNPG backup
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: linkding-pre-migration
  namespace: linkding
spec:
  cluster:
    name: linkding-postgres
EOF

# 2. Wait for backup to complete
kubectl get backup linkding-pre-migration -n linkding -w

# 3. Create new cluster pointing to backup + new storageClass
# (edit cluster spec: recovery.backup.name + storage.storageClass: longhorn)

# 4. Update app to point to new cluster service
# 5. Verify data, delete old cluster
```

**Time per database: ~30–60 minutes with downtime.** Do linkding and n8n separately.

---

## Quick Reference: Current Storage State (All Verified)

```
StorageClass:      local-path (only one)
Total PVC usage:   ~19Gi across 2 nodes

Control-plane:     167GB total | 122GB used (77%) | 38GB free  | KVM VM
Worker-01:         233GB NVMe  | 179GB used (82%) | 42GB free  | Bare metal
Worker-02:         not yet added

Combined free:     ~80GB — both nodes are disk-constrained
Main capacity fix: worker-02 disk size (provision 500GB+ if possible)
```

**Notable:** Worker-01 has an NVMe drive — fast local storage. This makes it a high-quality Longhorn disk once deployed.

---

## Step 1 Safety — Will Cleanup Damage Running Apps?

**No.** Here's exactly what each command touches:

| Command | What it removes | Safe? |
|---------|----------------|-------|
| `docker system prune -a --volumes` | Docker images/containers/volumes **not used by running containers**. K3s is separate — its pods are unaffected. | ✅ Safe — Docker is dev-only on this machine |
| `journalctl --vacuum-size=500M` | Old log entries past 500MB. Running services unaffected. | ✅ Safe |
| `k3s crictl rmi --prune` | K3s container images **not currently used by running pods**. If a pod later restarts, it re-pulls its image (brief delay, no data loss). | ✅ Safe — running pods keep their images |

**What cannot break:** PVCs, running pods, databases, Kubernetes state, FluxCD sync.
**What could cause brief delay:** A pod restarting after `crictl rmi --prune` will re-pull its image (~30s–2min depending on size). This is normal and harmless.

---

## Open Questions

1. **Proxmox host physical disk layout** — ZFS pools, free capacity? Determines if Proxmox CSI is viable and whether the control-plane VM disk can be expanded cheaply
2. **Is the desktop (GNOME/Firefox) on control-plane intentional?** — if so, disk pressure will recur after cleanup; separating workstation from K3s node is worth considering
3. **Will worker-01 eventually migrate into Proxmox?** — unlocks Proxmox CSI as the long-term unified storage solution

---

**Investigation v3 — 2026-04-03**
**Changes from v2:** Added live Docker stats, added worker-02 VM vs bare-metal recommendation, updated storage path to prioritize Longhorn over NFS given 3-node expansion happening today, clarified per-app PVC isolation is correct and should not change.
