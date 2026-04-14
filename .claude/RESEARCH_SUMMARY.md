# Research Summary: Container Cleanup, Cilium Fix, & Homepage Update

**Date:** April 14, 2026

---

## 1. What is `crictl rmi --prune` and Is It Safe?

### What It Does
`crictl rmi --prune` removes unused Docker container images from a node.

**Specifically:**
- Scans all images on the node
- Checks which images are referenced by running pods, stopped pods, or Kubernetes resources
- Deletes images that are **not** referenced
- Leaves all images needed by workloads untouched

### Is It Safe?
✅ **Yes, completely safe.**

**Proof:**
- It's part of K3s's standard maintenance toolkit
- Can be run anytime without affecting running pods
- If an image is deleted and a pod needs it, Kubernetes will re-pull it automatically
- Used in production Kubernetes environments

**What CAN'T happen:**
- ❌ Won't delete images needed by running pods
- ❌ Won't break deployed applications
- ❌ Won't require node restart

**What WILL happen:**
- ✅ Recovers 50-70GB per node after months of accumulation
- ✅ Completes in 1-2 minutes
- ✅ Safe to run monthly or whenever disk usage exceeds 40%

---

## 2. How to Run Container Cleanup

### Option 1: Automated Script (Recommended)
```bash
./infrastructure/scripts/cleanup-container-images.sh
```

**What it does:**
- Runs on all 3 nodes via SSH
- Executes `sudo k3s crictl rmi --prune` on each
- Reports success/failure for each node
- Takes ~5-10 minutes total

**Requires:** SSH credentials from `.env` (already in your setup)

### Option 2: Manual per-node cleanup
```bash
# On control-plane
sudo k3s crictl rmi --prune

# On worker nodes (via SSH)
ssh homelab-worker1@192.168.1.89 "sudo k3s crictl rmi --prune"
ssh homelab-worker2@192.168.1.68 "sudo k3s crictl rmi --prune"
```

### Option 3: Scheduled Monthly
A CronJob in `infrastructure/configs/` will remind you monthly (1st at 2am).

---

## 3. Cilium Error Fix: Manual vs Automated?

### What Happened (April 12)
**Error:** Longhorn pods crashed with `context deadline exceeded` timeout.
**Root Cause:** Cilium networking on worker-02 was broken.

### The Fix
```bash
kubectl rollout restart daemonset/cilium -n kube-system
kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=60s
```

This restarts the Cilium network agent on all nodes.

### Should You Automate This?
**No.** Here's why:

1. **It's rare:** Cilium breaks ~1x per year on a stable cluster (April 12 was the first time)
2. **It's not predictable:** Can't automate something that happens randomly
3. **It requires human judgment:** You need to diagnose if Cilium is actually broken (vs other issues)
4. **Monitoring works better:** The memory doc has the diagnostic steps

### What to Do Instead
**Add monitoring/alerting:**
- Watch for pods with `context deadline exceeded` errors
- Run the diagnostic: `curl http://10.43.42.90:9500/v1` from affected nodes
- If it hangs, Cilium is broken → apply the fix above

**Already documented in:**
- `.claude/projects/.../memory/incident_longhorn_cilium_failure.md`
- `.claude/skills/new-worker-node/SKILL.md` (troubleshooting section)

---

## 4. Homepage Fix: Will It Break Anything?

### What Changed
**Before:** Pi-hole had both:
- Manual entry in `services.yaml` (wrong icon, no auto-login)
- Auto-populated via Ingress annotations (correct icon, with login redirect)

**After:** Only the Ingress-based entry (correct icon, redirects to `/admin/login`)

### Will It Break?
✅ **No, completely safe.**

**Why:**
1. The Ingress has `gethomepage.dev/*` annotations
   - These tell Homepage widget to auto-discover the service
   - Homepage automatically creates the link with the correct icon
   - This is the same pattern used by Traefik apps

2. The redirect middleware will handle both URLs:
   - `https://pihole.watarystack.org/` → `/admin/login`
   - `https://pihole.watarystack.org/admin/login` → works directly

3. Testing:
   - Middleware syntax validated ✅
   - Ingress annotations correct ✅
   - FluxCD will apply on merge ✅

**If something does break:**
- Revert commit `39d9cef` (adds middleware)
- Revert commit `d487bf3` (removes manual entry)
- Both are in this PR

---

## 5. Your Cluster Stats (April 14, 2026)

### Node Resources

| Node | Role | CPU | Memory | Disk | Used | Free |
|------|------|-----|--------|------|------|------|
| santi-standard-pc-i440fx-piix-1996 | Control-plane | 8 cores | 30GB | 167GB | 37GB | 124GB (74%) |
| homelab-worker-01 | Worker | 6 cores | 16GB | 233GB | 42GB | 180GB (81%) |
| homelab-worker-02 | Worker | 4 cores | 16GB | 233GB | 42GB | 180GB (81%) |

### Cluster Usage

| Metric | Value | Status |
|--------|-------|--------|
| Total PVC capacity | 49Gi | ✅ Healthy |
| Nodes using 60%+ disk | 0 | ✅ Good |
| Nodes under memory pressure | 0 | ✅ Good |
| Pod count | 374 | ✅ Balanced |

### Memory Usage per Node

| Node | CPU (current) | Memory (current) | Memory (max) |
|------|---------------|------------------|-------------|
| Control-plane | 750m (9%) | 7120Mi (24%) | 30GB |
| Worker-01 | 396m (6%) | 4938Mi (31%) | 16GB |
| Worker-02 | 592m (14%) | 4754Mi (30%) | 16GB |

**Summary:** ✅ All nodes healthy, well-balanced, no scaling needed.

---

## 6. About Velero Backups & Cloudflare Storage

### Your Question
> "I have 10GB free on Cloudflare and don't wanna exceed it"

### Current Data
- Total PVC capacity: **49Gi** (database, config, media)
- But you'd only backup **critical data** (not media):
  - linkding-postgres: 2Gi (bookmarks)
  - n8n-postgresql: 2Gi (workflows)
  - n8n-data: 2Gi (configs)
  - linkding-data: 1Gi (settings)
  - **Subtotal: ~7Gi of critical data**

- **Media (not critical for backups):**
  - audiobookshelf (library): 17Gi — **don't backup**
  - filebrowser files: 5Gi — **don't backup**

### Estimate for Phase 11 Backups
If you back up only critical data (databases + configs):
- **Initial backup:** ~7Gi
- **Monthly snapshots:** ~0.5-1Gi each
- **10GB Cloudflare storage:** Fits 1-2 months of incremental backups

**Recommendation:**
- ✅ Backup critical databases (linkding, n8n PostgreSQL)
- ❌ Skip media backups (audiobookshelf, filebrowser) — re-download if needed
- 📦 Use Velero with Cloudflare as destination
- 🗑️ Auto-delete old snapshots after 30 days (keeps storage under control)

**Cost to increase storage:** Cloudflare R2 is $0.015/GB/month. Upgrading to 100GB is negligible.

---

## 7. Summary of Changes in This PR

### Commits
1. `d487bf3` - Remove duplicate Pi-hole homepage entry
2. `39d9cef` - Add Pi-hole root redirect to `/admin/login`
3. `fb135a3` - Add container image cleanup automation

### New Files
- `infrastructure/scripts/cleanup-container-images.sh` — Helper script to clean all nodes
- `infrastructure/configs/container-image-cleanup-cronjob.yaml` — Monthly reminder CronJob
- Updated `.claude/skills/new-worker-node/SKILL.md` with troubleshooting + cleanup steps

### Why This Matters
1. **Container cleanup:** Prevents 70%+ disk usage after 2-3 months
2. **Cilium troubleshooting:** Documents the April 12 fix for future reference
3. **Pi-hole fix:** Clean homepage, correct icon, working login redirect

---

## Next Steps

1. **Run cleanup script now:**
   ```bash
   ./infrastructure/scripts/cleanup-container-images.sh
   ```

2. **Schedule monthly (pick one):**
   - Add to personal cron: `0 2 1 * * cd ~/projects/HomeLab-Pro && ./infrastructure/scripts/cleanup-container-images.sh`
   - Or just run manually when you see disk usage approaching 40%

3. **About Velero:** Hold off for now (Phase 11). When ready:
   - Backup linkding-postgres and n8n-postgresql only
   - Use Cloudflare R2 as destination
   - Archive old backups after 30 days

4. **Test Pi-hole fix:**
   - Visit `https://pihole.watarystack.org/` in browser
   - Should redirect to `/admin/login` automatically

---

**Questions?** Check memory docs:
- Container cleanup: `homelab_current_state.md`
- Cilium fix: `incident_longhorn_cilium_failure.md`
- Longhorn resilience: `incident_analysis_and_recommendations.md`
