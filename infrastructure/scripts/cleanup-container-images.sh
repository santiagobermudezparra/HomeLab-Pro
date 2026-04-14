#!/bin/bash
# Container Image Cleanup Script
# Removes unused Docker images from all cluster nodes
# Recovers 50-70GB per node after months of accumulation
#
# Safe to run anytime - only deletes images not referenced by any pod
# Automatically discovers cluster nodes and SSH users via kubectl
# Usage: ./cleanup-container-images.sh

set -euo pipefail

echo "🧹 Container Image Cleanup"
echo "=========================="
echo ""

# Verify kubectl access
if ! kubectl cluster-info &>/dev/null; then
  echo "❌ Error: Cannot reach the cluster via kubectl"
  exit 1
fi

# Get node info: name, IP, and whether control-plane
# Output format: <name> <ip> <is_control_plane>
NODE_DATA=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="InternalIP")].address}{"\t"}{.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}')

NODE_COUNT=$(echo "$NODE_DATA" | grep -c .)
if [ "$NODE_COUNT" -eq 0 ]; then
  echo "❌ Error: Could not discover any cluster nodes"
  exit 1
fi

echo "Found $NODE_COUNT node(s):"
echo "$NODE_DATA" | while IFS=$'\t' read -r name ip role; do
  role_label="${role:+control-plane}"
  echo "  - $name ($ip) ${role_label}"
done
echo ""
echo "This may take 2-5 minutes per node."
echo ""

SUCCESS_COUNT=0
FAILED_COUNT=0
FAILED_NODES=""

while IFS=$'\t' read -r name ip is_control_plane; do
  # Determine SSH user from node name:
  #   control-plane nodes → root
  #   homelab-worker-NN   → homelab-workerN (e.g. homelab-worker-01 → homelab-worker1)
  #   anything else       → ubuntu (fallback)
  if [ -n "$is_control_plane" ]; then
    SSH_USER="root"
  elif [[ "$name" =~ ^homelab-worker-([0-9]+)$ ]]; then
    # Strip leading zeros: homelab-worker-01 → homelab-worker1
    worker_num=$(echo "${BASH_REMATCH[1]}" | sed 's/^0*//')
    SSH_USER="homelab-worker${worker_num}"
  else
    SSH_USER="ubuntu"
  fi

  echo "► Cleaning $name ($ip) as $SSH_USER..."

  if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$ip" \
    "sudo k3s crictl rmi --prune" > /dev/null 2>&1; then
    echo "  ✓ Success"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo "  ✗ Failed (SSH error or crictl failed)"
    FAILED_NODES="$FAILED_NODES $name($ip)"
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi

  echo ""
done <<< "$NODE_DATA"

echo "=========================="
echo "Results: $SUCCESS_COUNT successful, $FAILED_COUNT failed"
echo ""

if [ "$FAILED_COUNT" -eq 0 ]; then
  echo "✅ All nodes cleaned successfully!"
  exit 0
else
  echo "⚠️  Some nodes failed:$FAILED_NODES"
  echo ""
  echo "Troubleshooting:"
  echo "1. Verify SSH access: ssh <user>@<ip> 'hostname'"
  echo "2. Verify k3s is running: ssh <user>@<ip> 'sudo k3s version'"
  echo "3. Check SSH credentials in .env"
  exit 1
fi
