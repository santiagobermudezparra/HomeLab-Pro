# Post-Migration Recovery Status — Phase 9 Cilium CNI

**Date:** 2026-04-09  
**Issue:** After Phase 9 (Flannel→Cilium migration), most apps returned 502 Bad Gateway.  
**Branch:** `feat/phase-9-cilium-cni-migration`

---

## Root Cause

The Longhorn instance manager pod on the control-plane (`instance-manager-4adc1b5b96aa77450a2ea252bb2da761`) had a **stale Flannel network namespace**. It was created before the Cilium migration and never restarted after the CNI switch.

**Symptom in Longhorn manager logs:**
```
dial tcp 10.42.0.116:8503: i/o timeout
```

This made ALL Longhorn volumes stuck in `detaching faulted` state on homelab-worker-01 because:
1. cloudflared pods were Running (tunnels up) but app pods couldn't start (no volume mounts)
2. Longhorn couldn't complete the detach/reattach cycle — port 8503 (gRPC) was unreachable
3. All volumes showed `detaching faulted` with `"All replicas are failed"` in manager logs

**Fix applied:** `kubectl delete pod instance-manager-4adc1b5b96aa77450a2ea252bb2da761 -n longhorn-system`
This gave the pod a fresh Cilium network namespace. All volumes immediately moved to `attached healthy`.

---

## Status at Context Clear (2026-04-09 ~19:45 NZST)

### App Pods
| App | Status |
|-----|--------|
| audiobookshelf | Running ✓ |
| pgadmin | Running ✓ |
| linkding-postgres | Running ✓ |
| n8n-postgres | Running ✓ |
| homepage | Running ✓ |
| xm-spotify-sync | Running ✓ |
| filebrowser | Running ✓ (recovered late) |
| **linkding** | ContainerCreating — volume reattaching |
| **mealie** | ContainerCreating — volume reattaching |
| **n8n** | Init:0/1 — volume reattaching |

### Longhorn Volumes
| Volume | Status | App |
|--------|--------|-----|
| pvc-89ecac9c (filebrowser-db) | attached healthy ✓ | |
| pvc-238c9c57 (filebrowser-files) | attached healthy ✓ | |
| pvc-83945d9a (n8n-data) | attached healthy ✓ | |
| pvc-9c373800 (linkding-data) | **detached** | linkding waiting |
| pvc-77bd20fd (mealie-data) | **detached** | mealie waiting |
| All audiobookshelf volumes | attached healthy ✓ | |
| All CNPG volumes | attached healthy ✓ | |

---

## What Still Needs Fixing

### 1. linkding, mealie, n8n pods still starting
The volumes were detached during recovery (to release them from control-plane).
They should auto-reattach to homelab-worker-01 as Longhorn processes the VolumeAttachment requests.

**Expected self-healing:** Wait 2-5 min and check again.

**If still stuck, run:**
```bash
# Delete the stuck pods to force reschedule
kubectl delete pod -n linkding $(kubectl get pods -n linkding --no-headers | grep -v cloudflared | grep -v postgres | awk '{print $1}')
kubectl delete pod -n mealie $(kubectl get pods -n mealie --no-headers | grep -v cloudflared | awk '{print $1}')
kubectl delete pod -n n8n $(kubectl get pods -n n8n --no-headers | grep -v cloudflared | grep -v postgres | awk '{print $1}')
```

### 2. Check homelab-worker-02 instance manager
The worker-02 instance manager (`instance-manager-0547daf8c65d53ca1917055f11b867b1`) was also restarted during recovery but may have the same stale Flannel namespace issue.

**Check:**
```bash
nc -zv -w3 $(kubectl get pod instance-manager-0547daf8c65d53ca1917055f11b867b1 -n longhorn-system -o jsonpath='{.status.podIP}') 8503
```

**If timeout, fix:**
```bash
kubectl delete pod instance-manager-0547daf8c65d53ca1917055f11b867b1 -n longhorn-system
```

### 3. Verify all apps accessible
After all pods are Running, verify these URLs respond:
- https://linkding.watarystack.org
- https://mealie.watarystack.org  
- https://n8n.watarystack.org
- https://filebrowser.watarystack.org
- https://audiobookshelf.watarystack.org
- https://pgadmin.watarystack.org

---

## Changes Made During Recovery (not in git — all kubectl operations)

1. Deleted stale VolumeAttachment CSI objects for all detached volumes
2. Restarted Longhorn manager, CSI plugin, CSI attacher, CSI provisioner daemonsets
3. Restarted k3s-agent on homelab-worker-01 (cleared stale instance managers)
4. Deleted Longhorn instance managers on worker-01 and worker-02 (they were recreated)
5. **KEY FIX:** Deleted instance-manager-4adc1b5b96aa77450a2ea252bb2da761 on control-plane
   - This pod had stale Flannel network namespace (predated Cilium migration)
   - Port 8503 was unreachable, blocking all Longhorn gRPC operations
   - After restart: all volumes immediately became `attached healthy`
6. Detached 5 volumes from control-plane (where they had been force-attached during recovery)
   - These are now reattaching to their proper nodes

---

## Lesson Learned

**After any CNI migration:** All long-running pods that use inter-pod gRPC communication (like Longhorn instance managers) MUST be restarted. They hold network namespaces from the old CNI that become incompatible after the switch.

For future migrations, add to the post-migration checklist:
```bash
# Restart ALL Longhorn instance managers after CNI migration
kubectl delete pods -n longhorn-system -l longhorn.io/component=instance-manager
```
