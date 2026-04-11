# PiHole Network DNS Flow — Phase 14 Documentation

## DNS Resolution Path

```
Client Device (e.g., 192.168.1.100)
     ↓
[DHCP provides nameserver: 10.43.244.220 (PiHole ClusterIP)]
     ↓
PiHole (in K3s, port 53)
     ├→ [Check against blocklists/gravity]
     ├→ [If blocked: return NXDOMAIN or 0.0.0.0]
     ├→ [If allowed & cluster domain (*.svc.cluster.local): forward to CoreDNS (10.43.0.10:53)]
     └→ [If allowed & external domain: forward to upstream DNS (8.8.8.8, 1.1.1.1, etc)]
```

## Network Topology

| Component | IP/Address | Role |
|-----------|-----------|------|
| Network Gateway | 192.168.1.1 (or your gateway IP) | DHCP server, router |
| PiHole Service | 10.43.244.220 | DNS resolver, ad-blocker |
| CoreDNS | 10.43.0.10 | Cluster-internal DNS |
| Upstream DNS | 8.8.8.8, 1.1.1.1 | External DNS for non-cluster queries |
| Client Device 1 | 192.168.1.100+ | Phone/Laptop/IoT |
| Client Device 2 | 192.168.1.100+ | Phone/Laptop/IoT |
| Client Device 3 | 192.168.1.100+ | Phone/Laptop/IoT |

## Deployment Details

**PiHole Pod:**
- Namespace: pihole
- Image: pihole/pihole:latest
- Service: pihole (ClusterIP 10.43.244.220, ports 53 TCP/UDP and 80 TCP)
- Storage: 1Gi PVC at /etc/pihole (longhorn backend)
- Resource limits: requests (100m CPU, 128Mi RAM) / limits (500m CPU, 512Mi RAM)
- Health probes: livenessProbe + readinessProbe on HTTP /admin endpoint

**Gateway Configuration:**
- DHCP Server: [TO BE CONFIGURED] — must provide PIHOLE_CLUSTER_IP (10.43.244.220) as primary DNS
- Router Type: [USER TO PROVIDE]
- Config Location: [USER TO PROVIDE]
- Last Updated: [TO BE RECORDED]

## Verification Steps

### 1. PiHole Pod Running
```bash
kubectl get pods -n pihole
# Expected: pihole pod in Running state
```

### 2. Service Has ClusterIP
```bash
kubectl get svc -n pihole
# Expected: pihole service with CLUSTER-IP 10.43.244.220 assigned
```

### 3. Client Device Using PiHole DNS
```bash
# On client device:
nslookup example.com
# Should respond from 10.43.244.220 (PiHole)
```

### 4. Ad-Blocking Working
```bash
dig ads.google.com
# Expected: NXDOMAIN or 0.0.0.0 response
```

### 5. Cluster Queries Working
```bash
# From within cluster
kubectl exec -it deployment/pihole -n pihole -- nslookup kubernetes.default.svc.cluster.local
# Expected: Should resolve to K3s service IP
```

## Troubleshooting

### Symptom: Client devices still using old DNS
**Cause:** DHCP lease not renewed
**Fix:**
- Restart network interface on client device (toggle Wi-Fi)
- Force DHCP lease renewal:
  - Windows: `ipconfig /release && ipconfig /renew`
  - macOS: System Preferences > Network > (disconnect/reconnect)
  - Linux: `sudo dhclient -r && sudo dhclient`
  - Mobile: Forget Wi-Fi network and reconnect

### Symptom: External domains not resolving
**Cause:** PiHole not forwarding to upstream DNS
**Fix:**
- Check PiHole pod logs: `kubectl logs -f deployment/pihole -n pihole`
- Verify PiHole pod has internet access (e.g., test upstream DNS from pod)
- Check if upstream DNS is set in PiHole admin dashboard

### Symptom: Cluster domains not resolving (*.svc.cluster.local)
**Cause:** PiHole not forwarding to CoreDNS
**Fix:**
- Verify CoreDNS is running: `kubectl get pods -n kube-system | grep coredns`
- Check PiHole dnsmasq config for CoreDNS forwarding rule
- Verify K3s service CIDR: `kubectl cluster-info dump | grep service-cidr`

### Symptom: Ad-blocking not working (ads still loading)
**Cause:** Blocklists not enabled or not updated
**Fix:**
- Access PiHole admin dashboard: https://pihole.internal.watarystack.org/admin (or http on internal network)
- Navigate to Adlists section, enable blocklists
- Wait 5-10 minutes for gravity (cache) to update
- Restart PiHole: `kubectl rollout restart deployment/pihole -n pihole`

### Symptom: PiHole pod crashes (CrashLoopBackOff)
**Cause:** Permission issue, resource exhaustion, or config error
**Fix:**
- Check pod status: `kubectl describe pod -n pihole <pod-name>`
- Check logs: `kubectl logs -f deployment/pihole -n pihole`
- Verify PVC is mounted: `kubectl get pvc -n pihole`
- Check resource usage: `kubectl top pods -n pihole`
- If PVC issue: Ensure longhorn is default StorageClass

### Symptom: Gateway can't reach PiHole service (ClusterIP)
**Cause:** Gateway is outside the Kubernetes cluster network
**Fix:**
- The gateway/router (192.168.1.1) is on a different network segment than the K3s ClusterIP (10.43.x.x)
- Solution: Gateway must be on the same physical network as a K3s node
- Verify: `ping 10.43.244.220` from the gateway — should work if on same network
- If on different network: Use a K3s node's IP as DNS server instead (requires node-level dnsmasq config)

## Next Steps

- Monitor query logs in PiHole dashboard daily
- Review ad-blocking effectiveness weekly
- Plan PiHole backup as part of Phase 11 (Velero) once complete
- Consider setting up PiHole Grafana dashboard (Phase 14-03)
- Plan DNS redundancy (secondary PiHole replica) in future phase if critical for network
