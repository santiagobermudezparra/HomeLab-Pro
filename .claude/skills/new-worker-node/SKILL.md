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

## Summary: what's automatic vs manual

| Task | Automatic? |
|------|-----------|
| K3s agent join | ❌ Manual (curl install command) |
| iscsi-installer (open-iscsi) | ✅ DaemonSet deploys automatically |
| Longhorn storage detection | ✅ Automatic after iscsi is ready |
| Prometheus node monitoring | ✅ DaemonSet deploys automatically |
| Traefik load balancing | ✅ Joins LB pool automatically |
| FluxCD workload scheduling | ✅ Kubernetes schedules automatically |
