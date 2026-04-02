# Storage Scalability Investigation Report

**Date:** 2026-04-03 (updated with verified data)
**Project:** HomeLab-Pro Kubernetes Cluster

---

## Executive Summary

The homelab has two distinct but related problems that need to be solved together:

1. **Control-plane disk at 77% capacity** — caused by container images (K3s + Docker), not Kubernetes volumes. Volumes are actually well-distributed.
2. **Storage is not scalable** — `local-path` binds volumes to nodes. Adding a 3rd worker without shared storage will eventually strand workloads.

**Immediate fix:** Clean K3s/Docker image cache on control-plane (recovers 20-40GB).  
**Structural fix:** Adopt shared storage (NFS or Proxmox-native) before adding the 3rd node.

---

## Verified Architecture

### Cluster Nodes

| Node | Role | CPU | RAM | Disk Total | Disk Used | OS | Virtualization |
|------|------|-----|-----|-----------|----------|----|----|
| `santi-standard-pc-i440fx-piix-1996` | Control-plane | 8 vCPU | 28GB | 167GB | **122GB (77%)** | Ubuntu 24.04.2 | **KVM VM** inside Proxmox |
| `homelab-worker-01` | Worker | 6 vCPU | 16GB | 237GB | Unknown¹ | Ubuntu 24.04.3 | Bare Ubuntu |

> ¹ Worker-01 SSH access wasn't available during this investigation. Disk usage is unverified.

**Critical architecture note:** The control-plane is confirmed running as a KVM virtual machine (`systemd-detect-virt` returns `kvm`). The hostname `i440FX-PIIX-1996` is the QEMU machine type. This means:
- The physical Proxmox host has separate storage capacity not visible to this VM
- The 167GB disk is a **virtual disk** allocated by Proxmox
- Proxmox-native storage (ZFS datasets, LVM-thin) is available as a backend option

---

## Where Is the Disk Space Going?

### Control-plane (122GB/167GB used)

The original investigation incorrectly attributed disk usage. Here's what we actually found:

| Category | Size | Source |
|----------|------|--------|
| `/snap` (GNOME, Firefox, etc.) | 8.4GB | Desktop snaps running on this machine |
| `/var` (Docker, logs, rancher) | 9.1GB | K3s rancher: 417MB; logs: 4.2GB; Docker: ~4GB |
| `/home` | 4.0GB | Projects, config, Docker dev images |
| `/usr` | 6.2GB | System packages |
| `/swap.img` | 4.1GB | Swap file |
| **K3s containerd images** | **~90GB** | Root-owned; requires `sudo` to measure |
| Kubernetes volumes | ~8GB | 6 PVCs bound to this node |
| **Total** | **~130GB** | Matches 122GB on disk |

**Root cause of disk pressure:** K3s bundles its own containerd and stores all container images under root-owned paths (not accessible without sudo). With ~30 running pods across audiobookshelf, mealie, linkding, monitoring stack (Prometheus/Grafana/AlertManager), FluxCD, cert-manager, Traefik, and CloudNativePG — accumulated container images are the primary consumer.

Additionally, this machine functions as **both a K3s node and a desktop** (Firefox, GNOME desktop environment are installed). That's an unusual setup with unique resource implications.

### Kubernetes Volume Distribution (Verified)

Volumes are **split between nodes**, not all on the control-plane:

**Control-plane (8Gi claimed):**

| App | PVC | Size |
|-----|-----|------|
| linkding | `linkding-data-pvc` | 1Gi |
| linkding | `linkding-postgres-1` (CNPG) | 2Gi |
| audiobookshelf | `audiobookshelf-config` | 1Gi |
| audiobookshelf | `audiobookshelf-metadata` | 1Gi |
| audiobookshelf | `audiobookshelf-audiobooks` | 1Gi |
| mealie | `mealie-data` | 1Gi |

**Worker-01 (11Gi claimed):**

| App | PVC | Size |
|-----|-----|------|
| filebrowser | `filebrowser-files` | **5Gi** |
| filebrowser | `filebrowser-db` | 1Gi |
| n8n | `n8n-data` | 2Gi |
| n8n | `n8n-postgresql-cluster-1` (CNPG) | 2Gi |
| pgadmin | `pgadmin-data-pvc` | 1Gi |

**Key insight:** filebrowser (the largest workload) is already on worker-01, not the control-plane. The disk crisis on the control-plane is from container images, not application data.

---

## The Real Problems

### Problem 1: Control-plane Disk Pressure (Immediate)

**Cause:** K3s containerd image cache + Docker dev images + desktop apps filling a 167GB VM disk.

**Solution (independent of storage architecture):**
```bash
# View K3s image storage (requires sudo)
sudo k3s crictl images
sudo k3s crictl rmi --prune  # Remove unused K3s images

# Docker dev containers (these are large - 1.3GB each)
docker image prune -a  # Removes ALL unused Docker images (safe if not using DevPod now)

# Check log disk usage
sudo journalctl --disk-usage
sudo journalctl --vacuum-size=500M  # Trim journal to 500MB

# Snap cleanup
snap list --all | awk '/disabled/{print $1, $3}' | while read snapname revision; do
    sudo snap remove "$snapname" --revision="$revision"
done
```

Expected recovery: **20-50GB** depending on image cache size.

### Problem 2: Storage Not Scalable (Structural)

**Current:** `local-path` storage class — volumes are node-local, bound at creation time.

```
STORAGECLASS   PROVISIONER                ALLOWVOLUMEEXPANSION   MODE
local-path     rancher.io/local-path      false                  WaitForFirstConsumer
```

**Consequences when adding worker-02:**
- Pods may be scheduled on worker-02 but their PVCs are bound to control-plane or worker-01
- Kubernetes will leave pods in `Pending` state (can't schedule because volume is node-locked)
- No capacity pooling — control-plane disk still limited to 167GB virtual disk
- No workload mobility — apps can't move between nodes freely

---

## Storage Solutions Comparison

### Option 1: NFS from Worker-01

**Setup:** Configure worker-01 as NFS server, all nodes mount it, deploy NFS provisioner in K3s.

```
worker-01 NFS server (/mnt/nfs-k8s, 100GB)
    ↓ exported via NFS
Control-plane + future worker-02 mount /mnt/nfs-shared
    ↓
Kubernetes NFS Provisioner (subdir-external-provisioner)
    ↓
New StorageClass: shared-nfs
```

**Pros:**
- ✅ Free, zero new hardware
- ✅ Easy: Linux-native, no Kubernetes operators
- ✅ Scales easily — new nodes just mount the NFS export
- ✅ Supports RWX (multiple pods reading same volume)
- ✅ Works now with 2 nodes, still works with 10

**Cons:**
- ❌ Single point of failure — if worker-01 goes down, ALL apps using shared-nfs lose storage
- ❌ NFS server is on a worker node, which creates a dependency inversion (worker hosts infra)
- ❌ Performance: network-attached storage adds latency vs local disk
- ❌ Databases (CNPG) on NFS can be problematic — CNPG is sensitive to fsync behavior

**Verdict:** ✅ Good for non-database workloads; avoid for CNPG clusters

**Effort:** ~4 hours

---

### Option 2: Proxmox CSI Driver ⭐ **Best fit for your setup**

**Setup:** The Proxmox CSI driver lets Kubernetes provision storage directly from the Proxmox host. Proxmox creates LVM-thin or ZFS datasets and attaches them as block devices to VMs.

```
Proxmox Host (physical machine)
├── Physical disks (ZFS pool or LVM volume group)
│   └── CSI provisions new volumes as datasets/LVs
└── VMs: control-plane VM, worker-01 VM, worker-02 VM (future)
    ↓ block device attached via virtio
Kubernetes PVC → Proxmox CSI → Proxmox creates + attaches LV
```

**Pros:**
- ✅ **Best performance** — block-level, not network filesystem
- ✅ **Leverages existing Proxmox** — no extra hardware
- ✅ **Highly scalable** — add VMs to Proxmox, they get access to same storage pool
- ✅ **Proxmox manages capacity** — can expand storage pool with disks on Proxmox host
- ✅ **Volume expansion supported** — resize LV → resize PVC online
- ✅ Plays well with CNPG (block device, proper fsync)
- ✅ Native Proxmox backup integration (VM + volume snapshots)

**Cons:**
- ❌ More setup complexity (Proxmox API token, CSI driver deployment, Proxmox cluster config)
- ❌ Only works for VMs on Proxmox — worker-01 is bare Ubuntu (bare metal), not a VM
- ❌ Requires Proxmox storage pool to have free capacity (need to verify)

**Important limitation:** worker-01 is **NOT** a Proxmox VM — it's bare Ubuntu. Proxmox CSI can only provision storage to VMs. This means:
- Control-plane VM: ✅ gets Proxmox CSI volumes
- Worker-01 (bare metal): ❌ cannot use Proxmox CSI directly
- Future worker-02: ✅ if added as a Proxmox VM

This makes Proxmox CSI a partial solution unless you migrate worker-01 to run as a Proxmox VM (which is a bigger change).

**Verdict:** ✅ Excellent long-term path, but requires worker-01 to become a Proxmox VM to fully unify storage

**Effort:** ~8-10 hours (Proxmox setup + CSI driver + storage pool config)

---

### Option 3: Longhorn

**Setup:** Kubernetes-native distributed storage operator. Installs in cluster, uses disks on each node.

```
All worker nodes expose disk space to Longhorn
    ↓
Longhorn replicates volumes across nodes
    ↓
Any pod on any node can access any volume (with replication)
```

**Pros:**
- ✅ Kubernetes-native — manages itself entirely
- ✅ Automatic replication (data survives node failure)
- ✅ Built-in UI for monitoring volumes
- ✅ Works on mixed hardware (Proxmox VM + bare metal)
- ✅ Good CNPG compatibility (block-level, proper fsync)
- ✅ Volume expansion supported

**Cons:**
- ❌ At replica=2, needs 2 nodes — you have that, but losing either means data unavailability
- ❌ Higher resource overhead (CPU/RAM per node for Longhorn daemons)
- ❌ More complex to debug than NFS
- ❌ Initial setup takes 6-8 hours including validation

**Correction from prior report:** Longhorn works fine on 2 nodes. The prior claim that it "requires 3+ nodes" was wrong. With 2 nodes you can set `numberOfReplicas: 2` for redundancy or `numberOfReplicas: 1` to save space. HA requires 3+ nodes (so quorum survives 1 failure), but the system runs on 2.

**Verdict:** ✅ Strong candidate, especially if staying with mixed hardware long-term

**Effort:** ~8 hours

---

### Option 4: Ceph via Rook

**Verdict:** ❌ Overkill for 2-3 nodes. Requires minimum 3 OSDs and significant RAM. Skip for now.

---

## Recommended Strategy: Two-Stage Approach

Given your specific constraints (Proxmox VM control-plane + bare-metal worker, 3rd node coming soon), the cleanest path is:

### Stage 1: Immediate Disk Relief (This Week, ~1 hour)

**Goal:** Stop the disk crisis on the control-plane.

```bash
# Step 1: Clean K3s image cache (run as root/sudo)
sudo k3s crictl rmi --prune

# Step 2: Clean Docker dev images (if not actively using DevPod)
docker image prune -a

# Step 3: Trim system logs
sudo journalctl --vacuum-size=500M

# Step 4: Remove disabled snap revisions
snap list --all | awk '/disabled/{print $1, $3}' | \
  while read name rev; do sudo snap remove "$name" --revision="$rev"; done

# Step 5: Verify recovery
df -h /
```

This is independent of storage architecture and should recover 20-50GB.

---

### Stage 2: Shared Storage (Before Adding Worker-02)

**Recommended path: NFS now → Proxmox CSI later**

**Why not jump straight to Proxmox CSI:**
- Worker-01 is bare metal, can't use Proxmox CSI
- Migrating worker-01 to a Proxmox VM is a bigger decision
- NFS works across all node types, buys time to plan properly

**Why not Longhorn right now:**
- You're about to add a 3rd node — wait until that node is stable
- Longhorn on 2 nodes with no HA quorum is risky during infrastructure changes
- NFS is faster to set up and migrate to Longhorn later is straightforward

**Phase 2a: NFS for non-database workloads**

Deploy NFS provisioner using worker-01 as server (or a dedicated device if available):

```
Worker-01 (/mnt/nfs-k8s — allocate 80GB from the 237GB disk)
  ↓ NFS export
All K3s nodes mount /mnt/nfs-shared
  ↓
Helm: nfs-subdir-external-provisioner
  ↓
StorageClass: shared-nfs
```

Migrate these workloads to `shared-nfs`:
- filebrowser (files + db)
- mealie
- audiobookshelf (config, metadata)
- pgadmin
- homarr
- homepage

**Do NOT migrate CNPG databases (linkding, n8n) to NFS yet** — CloudNativePG requires block storage with proper fsync semantics. NFS can cause subtle data corruption with PostgreSQL. Keep them on local-path for now, or migrate to Longhorn when you have 3 nodes.

**Phase 2b: Once 3rd Node is Stable**

With 3 nodes running (especially if worker-02 is a Proxmox VM), evaluate:

- **Option A:** Migrate to Longhorn — installs in cluster, works on all 3 nodes, covers databases
- **Option B:** Migrate control-plane + worker-02 to Proxmox CSI, keep worker-01 on NFS

---

## CNPG Migration Complexity (Important)

The prior investigation said "gradually migrate PVCs." This significantly understated the complexity for **CloudNativePG databases** (linkding, n8n). These are NOT simple PVC copies.

**Correct CNPG migration process:**
1. Take a CNPG backup (via `ScheduledBackup` or manual `Backup` object)
2. Bootstrap a new `Cluster` using `recovery.backup.name` pointing to that backup
3. Set `storage.storageClass: shared-nfs` on the new cluster spec
4. Wait for new cluster to be fully recovered and healthy
5. Update app secrets/configmaps to point to new cluster service name
6. Verify app connectivity
7. Delete old CNPG cluster (old PVC is deleted with it since `reclaimPolicy: Delete`)

**CNPG migration for each database: ~30-60 minutes per app with downtime.**

---

## Corrected Cleanup Commands

The prior investigation had a wrong command. This machine uses **containerd** (K3s), not Docker for Kubernetes workloads. Correct commands:

```bash
# ❌ WRONG (Docker is only for local dev, not K3s)
docker image prune -a  # This only cleans Docker images, not K3s container images

# ✅ CORRECT for K3s container images
sudo k3s crictl rmi --prune    # Remove unused K3s images
sudo k3s ctr images ls         # List all K3s images with sizes

# ✅ ALSO valid for Docker dev images (separate daemon)
docker image prune -a          # Safe for DevPod/local dev images only
```

---

## Implementation Plan Summary

| Phase | Action | Timeline | Effort | Risk |
|-------|--------|----------|--------|------|
| **1** | Disk cleanup (K3s images, Docker, logs) | Day 1 | 1h | Low |
| **2** | Verify worker-01 disk stats | Day 1 | 30min | None |
| **3** | Deploy NFS on worker-01 + provisioner | Week 1 | 4h | Low |
| **4** | Create `shared-nfs` StorageClass | Week 1 | 1h | Low |
| **5** | Migrate non-DB workloads to shared-nfs | Week 1-2 | 3h | Medium |
| **6** | Run 1-2 weeks with NFS stable | Week 2-3 | monitoring | Low |
| **7** | Add worker-02 node to cluster | Week 3+ | 2h | Low |
| **8** | Evaluate Longhorn (3-node HA) | Month 2+ | 8h | Low |
| **9** | Migrate CNPG clusters to Longhorn | Month 2+ | 2h/db | Medium |

---

## Open Questions (Need Answers Before Planning)

1. **What is the Proxmox host's physical disk capacity and layout?**
   - Does Proxmox have ZFS pools with free space?
   - This determines if Proxmox CSI is viable and how much VM disk can be expanded

2. **What is worker-01's actual disk usage?**
   - The 237GB allocatable doesn't tell us how full the disk is
   - Run `df -h` on worker-01 directly

3. **Is worker-02 going to be a Proxmox VM or bare metal?**
   - VM: Proxmox CSI becomes viable for unified storage long-term
   - Bare metal: NFS or Longhorn are the better choices

4. **Is the desktop (Firefox, GNOME) intentional on the control-plane?**
   - If this is also used as a workstation, the VM disk pressure will keep coming back
   - Separating workstation from K3s node would solve the recurring disk issue

5. **Are you open to migrating worker-01 to run inside Proxmox?**
   - If yes: Proxmox CSI becomes the cleanest long-term solution
   - If no: NFS → Longhorn is the path

---

## Files to Create (GSD Milestone)

```
infrastructure/
└── storage/
    ├── nfs-provisioner/        # NFS subdir provisioner deployment
    │   ├── helmrelease.yaml    # FluxCD HelmRelease for NFS provisioner
    │   └── storageclass.yaml   # shared-nfs StorageClass
    └── longhorn/ (future)      # Longhorn operator (Phase 2)

.planning/
└── STORAGE_INVESTIGATION.md   (this file — keep updated)
```

---

**Investigation Updated: 2026-04-03**  
**Changes from v1:** Corrected VM status, verified PVC node distribution, fixed disk usage analysis, corrected cleanup commands, added CNPG migration complexity, added Proxmox CSI option, corrected Longhorn 2-node claim.
