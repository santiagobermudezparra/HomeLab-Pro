# Skill: Add New Worker Node to HomeLab K3s Cluster

## When to use this skill
When the user says:
- "add a new worker node"
- "join a new node to the cluster"
- "expand the cluster with a new machine"
- "add a worker to k3s"

## What happens automatically (no action needed)

Once a node joins the cluster, these happen on their own:
- **Longhorn iscsi-installer DaemonSet** deploys automatically — installs open-iscsi on the new node
- **Longhorn** detects the new node and adds its disk to available storage capacity
- **FluxCD/kube-prometheus-stack** picks up the new node for monitoring automatically
- All existing DaemonSets (Prometheus node-exporter, etc.) schedule automatically

## What requires manual steps

### Step 0 — Prep the new machine (run on the new PC)

```bash
# Update system and install required tools
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl

# Set a meaningful hostname
sudo hostnamectl set-hostname homelab-worker-NN  # Replace NN with the next worker number

# Verify network connectivity to control-plane (192.168.1.115)
ping -c 3 192.168.1.115
nc -zv 192.168.1.115 6443
# Both should succeed before continuing
```

### Step 1 — Install K3s as an agent (run on the new PC)

```bash
# Get the server token from the control-plane
# (SSH to 192.168.1.115 or run this command on the control-plane)
sudo cat /var/lib/rancher/k3s/server/node-token

# On the NEW worker node, run (with your real K3S_TOKEN):
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.30.0+k3s1" \
  K3S_URL=https://192.168.1.115:6443 \
  K3S_TOKEN=<paste-token-here> \
  sh -

# After install completes, enable the agent service to auto-rejoin on reboot
sudo systemctl enable k3s-agent
```

### Step 2 — Verify it joined (run on control-plane)

```bash
kubectl get nodes -o wide
# New node should appear as Ready within 30-60 seconds
```

### Step 3 — Verify Longhorn picked it up (run on control-plane)

```bash
# Wait ~2 min for iscsi-installer DaemonSet to complete
kubectl get pods -n longhorn-system -l app=longhorn-iscsi-installation -o wide
# All pods (including new node) should show Running

# Check Longhorn sees the new node's disk
kubectl get lhn -n longhorn-system   # Longhorn Node resources
# New node should appear — check if it shows Schedulable: true
# If disk is <25% free, it shows Schedulable: false (expected for low-disk nodes)
```

### Step 3.5 — Verify Cilium agent is running on new node (run on control-plane)

The cluster uses Cilium as the CNI (replaced Flannel in Phase 9). Cilium deploys as a DaemonSet, so it automatically starts on the new node — but verify it reaches `Running` before declaring success. If the Cilium agent fails, pods on the new node will get no networking.

```bash
# Cilium agent should be Running on the new node within ~60 seconds
kubectl get pods -n kube-system -l k8s-app=cilium -o wide
# New node should appear with STATUS=Running

# If still initializing, watch it:
kubectl get pods -n kube-system -l k8s-app=cilium -o wide -w

# If the agent is stuck, check its logs:
kubectl logs -n kube-system -l k8s-app=cilium --tail=50

# Quick connectivity check (requires cilium CLI):
# cilium status --wait
```

> **Note:** Do NOT proceed to Step 4 (workload scheduling) until the Cilium agent on the new node is `Running`. Pods scheduled before Cilium is ready will fail with networking errors.

**If Cilium doesn't reach Running within 2 minutes:**
- This is the same issue that caused the April 12 incident
- See **Troubleshooting: Cilium Networking Failure** below for the fix

### Step 4 — Verify monitoring is active (run on control-plane)

```bash
# Prometheus node-exporter DaemonSet should be running on the new node
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-node-exporter -o wide
# New node should be listed and show Running

# Optional: Run a quick workload test
kubectl create deployment test-nginx --image=nginx:alpine
kubectl scale deployment test-nginx --replicas=2
kubectl get pods -o wide | grep test-nginx
# Pods should spread across nodes; then clean up:
kubectl delete deployment test-nginx
```

### Step 5 — Agent config notes

The `disable` flag in `/etc/rancher/k3s/config.yaml` is **server-only** and is **NOT valid for k3s agents**. Do NOT create a config.yaml on worker nodes with the `disable` key — it will cause k3s-agent to fail to start.

If the new worker needs any k3s-agent specific config (e.g., labels, taints), create `/etc/rancher/k3s/config.yaml` on the worker with only agent-valid flags:
```yaml
# Valid agent config example (only add what you need):
node-label:
  - "node-role.kubernetes.io/worker=true"
```

## Cluster node reference

| Role | Hostname | IP | SSH |
|------|----------|----|-----|
| Control-plane | santi-standard-pc-i440fx-piix-1996 | 192.168.1.115 | local |
| Worker 1 | homelab-worker-01 | 192.168.1.89 | `ssh homelab-worker1@192.168.1.89` |
| Worker 2 | homelab-worker-02 | 192.168.1.67 | `ssh homelab-worker2@192.168.1.67` |

**Worker SSH password**: in `.env` → `WORKER_NODES_PSWD`

## Container Image Cleanup on New Nodes

New worker nodes accumulate Docker images over time (pulled by Renovate, workloads, etc.). After 2-3 months, nodes can reach 70%+ disk usage. To prevent this, set up monthly cleanup.

### Option 1: Automated via Script (Recommended)
```bash
# Run this monthly to clean ALL nodes at once
./infrastructure/scripts/cleanup-container-images.sh
```

This runs `crictl rmi --prune` on all nodes via SSH. Recovers 50-70GB per node.

### Option 2: Manual per-node cleanup
```bash
# On the new worker node, run:
sudo k3s crictl rmi --prune

# What it does: Removes Docker images not referenced by any pod (safe)
# Result: Recovers 50-70GB
# Time: 1-2 minutes
```

### Option 3: Automated via CronJob (runs monthly reminder)
The cluster includes a monthly CronJob that reminds you to run cleanup:
```bash
# Check the CronJob
kubectl get cronjob -n kube-system container-image-cleanup

# It triggers monthly on the 1st at 2:00 AM
# Logs will remind you to run the script
```

---

## Troubleshooting

### Cilium Networking Failure (April 12 Incident)

**Symptom:** Cilium pod is stuck in `ContainerCreating` or `CrashLoopBackOff` on new node

**Why:** Cilium network agent didn't initialize properly on the new node

**Fix (run on control-plane):**
```bash
# Restart Cilium across all nodes to reset the network fabric
kubectl rollout restart daemonset/cilium -n kube-system
kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=60s

# If the issue persists only on one node, troubleshoot that node's networking
kubectl describe node <node-name> | grep -A 5 "Conditions:"
```

**Test connectivity (verify the fix worked):**
```bash
# From control-plane, try reaching Kubernetes service API from new node
ssh homelab-workerN@<IP> "timeout 3 curl -v http://10.43.42.90:9500/v1" 2>&1 | head -10
# Should connect, not timeout. If it hangs, Cilium is still broken.
```

### Node Disk Full

**Symptom:** New node disk fills quickly (50%+ in first week)

**Cause:** Container images accumulated from workloads

**Fix (temporary):**
```bash
ssh <node> "sudo k3s crictl rmi --prune"
```

**Long-term:** Set up monthly cleanup script as shown above

---

## Summary: what's automatic vs manual

| Task | Automatic? |
|------|-----------|
| K3s agent join | ❌ Manual (curl install command) |
| **Cilium agent (CNI)** | ✅ DaemonSet deploys automatically — **verify Running before scheduling workloads** |
| iscsi-installer (open-iscsi) | ✅ DaemonSet deploys automatically |
| Longhorn storage detection | ✅ Automatic after iscsi is ready |
| Prometheus node monitoring | ✅ DaemonSet deploys automatically |
| Traefik load balancing | ✅ Joins LB pool automatically |
| FluxCD workload scheduling | ✅ Kubernetes schedules automatically |
| Container image cleanup | ⚠️ Manual monthly (script or cron) |
