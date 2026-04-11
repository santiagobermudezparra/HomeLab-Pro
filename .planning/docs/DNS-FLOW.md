# PiHole Network DNS Flow — Phase 14 Documentation

## DNS Resolution Path

```
Client Device (e.g., 192.168.1.100)
     ↓
[DHCP provides nameserver: 10.43.244.220 (PiHole ClusterIP)]
     ↓
PiHole (in K3s, port 53/TCP+UDP)
     ├→ [Check against blocklists/gravity]
     ├→ [If blocked: return NXDOMAIN or 0.0.0.0]
     ├→ [If allowed & cluster domain (*.svc.cluster.local): forward to CoreDNS (10.43.0.10:53)]
     └→ [If allowed & external domain: forward to upstream DNS (8.8.8.8, 1.1.1.1, etc)]
```

## Network Topology

| Component | IP/Address | Role |
|-----------|-----------|------|
| Network Gateway (Huawei HG659b) | 192.168.1.1 | DHCP server, router |
| PiHole Service | 10.43.244.220 | DNS resolver, ad-blocker (ClusterIP) |
| PiHole Pod | 10.42.1.119 | Running instance on homelab-worker-01 |
| CoreDNS | 10.43.0.10 | Cluster-internal DNS (kube-system) |
| Upstream DNS | 8.8.8.8, 1.1.1.1 | External DNS for non-cluster queries |

## Deployment Details

### PiHole Pod
- **Namespace:** pihole
- **Image:** pihole/pihole:latest
- **Pod Name:** pihole-6d748b6c48-nczln
- **Node:** homelab-worker-01 (10.42.1.119)
- **Service:** pihole (ClusterIP 10.43.244.220)
- **Ports:**
  - 53/TCP (DNS over TCP)
  - 53/UDP (DNS over UDP)
  - 80/TCP (Web admin interface)
- **Storage:** 1Gi PVC at /etc/pihole (persistent)
- **Resource limits:** 500m CPU, 512Mi RAM
- **Status:** Running (1/1 Ready)

### Gateway Configuration
- **Router Type:** Huawei HG659b (Hardware Version B)
- **DHCP Server:** Configured to provide PiHole ClusterIP as primary DNS
- **Primary DNS:** 10.43.244.220 (PiHole)
- **Configuration Updated:** 2026-04-12
- **Method:** Via router web UI settings

## Verification Steps

### 1. PiHole Pod Running
```bash
kubectl get pods -n pihole
# Expected: pihole pod in Running state
```

### 2. Service Has ClusterIP
```bash
kubectl get svc -n pihole pihole -o wide
# Expected: pihole service with CLUSTER-IP 10.43.244.220 and endpoints active
```

### 3. DNS Resolution Working (example.com)
```bash
kubectl exec deployment/pihole -n pihole -- nslookup example.com localhost
# Expected: Resolves to 104.20.23.154 and 172.66.147.243
```

### 4. Ad-Blocking Working (ads.google.com)
```bash
kubectl exec deployment/pihole -n pihole -- nslookup ads.google.com localhost
# Expected: Returns 0.0.0.0 or :: (blocked)
```

### 5. Client Device Verification
**On each client device (phone, laptop, IoT):**

**Windows (PowerShell):**
```powershell
ipconfig /all | grep "DNS Servers"
nslookup example.com
nslookup ads.google.com
```

**macOS/Linux:**
```bash
resolvectl status
nslookup example.com
dig ads.google.com
```

**iOS/iPadOS:**
- Settings > Wi-Fi > (tap network name) > DNS

**Android:**
- Settings > Wi-Fi > (tap network) > Advanced > DNS

## Troubleshooting

### Client devices still using old DNS
**Cause:** DHCP lease not renewed after gateway configuration change
**Fix:**
- Restart network interface on client device (toggle Wi-Fi)
- Force DHCP lease renewal:
  - Windows: `ipconfig /release && ipconfig /renew`
  - macOS: System Preferences > Network > (disconnect/reconnect Wi-Fi)
  - Linux: `sudo dhclient -r && sudo dhclient`
  - Mobile: Forget Wi-Fi network and reconnect

### External domains not resolving
**Cause:** PiHole not forwarding to upstream DNS or network connectivity issue
**Fix:**
- Check PiHole pod logs: `kubectl logs deployment/pihole -n pihole`
- Verify PiHole pod has internet connectivity
- Check upstream DNS in PiHole admin dashboard: http://pihole.watarystack.org/admin

### Ad-blocking not working
**Cause:** Blocklists not enabled or not updated yet
**Fix:**
- Access PiHole admin dashboard: http://pihole.watarystack.org/admin
- Navigate to Adlists section, verify blocklists are enabled
- Wait 5-10 minutes for gravity (cache) to update
- Restart PiHole: `kubectl rollout restart deployment/pihole -n pihole`

### PiHole pod crashes (CrashLoopBackOff)
**Cause:** Permission issue, resource exhaustion, missing PVC, or config error
**Fix:**
- Check pod status: `kubectl describe pod -n pihole <pod-name>`
- Check logs: `kubectl logs deployment/pihole -n pihole --tail=50`
- Verify PVC is mounted: `kubectl get pvc -n pihole`

## Next Steps

1. Verify all client devices are using PiHole DNS
2. Monitor query logs in PiHole dashboard for 24+ hours to verify blocking
3. Review ad-blocking effectiveness weekly via dashboard statistics
4. Plan PiHole backup as part of Phase 11 (Velero) once complete
5. Consider setting up PiHole Grafana dashboard (Phase 14-03)
6. Plan DNS redundancy (secondary PiHole replica) in future phase if critical
