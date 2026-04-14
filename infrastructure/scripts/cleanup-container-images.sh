#!/bin/bash
# Container Image Cleanup Script
# Removes unused Docker images from all cluster nodes
# Recovers 50-70GB per node after months of accumulation
#
# Safe to run anytime - only deletes images not referenced by any pod
# Usage: ./cleanup-container-images.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Node IPs and SSH users (from CLAUDE.md)
NODES=(
  "192.168.1.115:root"           # Control-plane (local)
  "192.168.1.89:homelab-worker1" # Worker-01
  "192.168.1.68:homelab-worker2" # Worker-02
)

echo "🧹 Container Image Cleanup"
echo "=========================="
echo ""
echo "Starting cleanup on $(echo ${#NODES[@]}) nodes..."
echo "This may take 2-5 minutes per node."
echo ""

SUCCESS_COUNT=0
FAILED_COUNT=0

for node_info in "${NODES[@]}"; do
  IP="${node_info%%:*}"
  USER="${node_info##*:}"

  # Get hostname
  HOSTNAME=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$USER@$IP" 'hostname' 2>/dev/null || echo "unknown")

  echo "► Cleaning $HOSTNAME ($IP)..."

  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$USER@$IP" \
    "sudo k3s crictl rmi --prune" > /dev/null 2>&1; then
    echo "  ✓ Success"
    ((SUCCESS_COUNT++))
  else
    echo "  ✗ Failed (or SSH timeout)"
    ((FAILED_COUNT++))
  fi

  echo ""
done

echo "=========================="
echo "Results: $SUCCESS_COUNT successful, $FAILED_COUNT failed"
echo ""

if [ "$FAILED_COUNT" -eq 0 ]; then
  echo "✅ All nodes cleaned successfully!"
  exit 0
else
  echo "⚠️  Some nodes failed. Check SSH credentials in .env"
  exit 1
fi
