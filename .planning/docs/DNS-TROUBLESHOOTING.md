# PiHole DNS Troubleshooting Runbook

## Quick Diagnosis

### Is the PiHole pod running?
```bash
kubectl get pods -n pihole
# Should see: pihole pod in Running state (1/1 Ready)

# If not running:
kubectl describe pod -n pihole <pod-name>
kubectl logs deployment/pihole -n pihole --tail=50
```

### Is the service accessible?
```bash
kubectl get svc -n pihole pihole
# Should show: CLUSTER-IP 10.43.244.220 with port 53/TCP,53/UDP,80/TCP

kubectl get endpoints -n pihole pihole
# Should show: 10.42.x.x:53,10.42.x.x:80,10.42.x.x:53 (active endpoints)
```

### Is DNS resolution working in the cluster?
```bash
kubectl exec deployment/pihole -n pihole -- nslookup example.com localhost
# Expected: Returns IP addresses for example.com
```

### Are blocklists enabled?
```bash
# Access PiHole admin dashboard: http://pihole.watarystack.org/admin
# Login and check: Settings > Blocklists
# At least one blocklist should be enabled
```

---

## Common Issues and Fixes

### Issue 1: DNS queries timeout
**Symptoms:**
- Client devices can't resolve any domains
- nslookup returns "connection timed out; no servers could be reached"

**Root causes:**
1. PiHole pod not running
2. Service not exposing port 53
3. Network connectivity issue between client and cluster
4. Firewall blocking port 53/UDP

**Diagnostics:**
```bash
# 1. Check if pod is running
kubectl get pods -n pihole
# Expected: Running, 1/1 Ready

# 2. Check service endpoints
kubectl get endpoints -n pihole pihole
# Expected: Should list active pod IPs with port 53

# 3. Check if port 53 is open on gateway
# (From gateway)
netstat -tuln | grep 53
# Should show: UDP port 53 open (if using dnsmasq)

# 4. Check K3s network policies
kubectl get networkpolicies -A
# Look for policies that might block DNS traffic
```

**Fixes:**
```bash
# Restart PiHole pod
kubectl rollout restart deployment/pihole -n pihole

# Check logs for errors
kubectl logs deployment/pihole -n pihole --tail=50

# Verify service is correctly configured
kubectl get svc -n pihole pihole -o yaml | grep -A 5 ports

# If service is missing, re-apply kustomization
kubectl apply -k apps/staging/pihole/
```

---

### Issue 2: Ad-blocking not working (ads still loading)

**Symptoms:**
- ads.google.com resolves to an IP instead of 0.0.0.0
- Ads appear on websites normally
- dig ads.google.com shows normal A record

**Root causes:**
1. Blocklists not enabled
2. Blocklists not updated yet
3. Gravity database not synced
4. Client not actually using PiHole DNS

**Diagnostics:**
```bash
# 1. Check if blocklists are enabled
# Access: http://pihole.watarystack.org/admin
# Settings > Blocklists > verify at least one is enabled

# 2. Check gravity database
kubectl exec deployment/pihole -n pihole -- ls -la /etc/pihole/gravity.db
# Should exist and be recent

# 3. Test from PiHole pod
kubectl exec deployment/pihole -n pihole -- nslookup ads.google.com localhost
# Should return 0.0.0.0 if blocklists are enabled

# 4. Check client is actually using PiHole
# On client device:
# Windows: ipconfig /all | grep "DNS Servers"
# macOS: networksetup -getdnsservers "Wi-Fi"
# Linux: cat /etc/resolv.conf | grep nameserver
```

**Fixes:**
```bash
# 1. Enable blocklists via admin UI
# http://pihole.watarystack.org/admin > Settings > Blocklists > Add list

# Recommended blocklists:
# - https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
# - https://mirror1.malwaredomains.com/files/justdomains
# - https://dbl.oisd.nl/

# 2. Force gravity update (may take 5-10 minutes after enabling)
# In PiHole UI: Tools > Gravity

# 3. Restart PiHole pod to reload gravity
kubectl rollout restart deployment/pihole -n pihole

# 4. If client still not using PiHole, force DHCP renewal (see Issue 3)
```

---

### Issue 3: Client devices not receiving PiHole DNS from DHCP

**Symptoms:**
- ipconfig /all shows old DNS server
- Client still using ISP DNS
- DHCP lease shows different DNS than configured on gateway

**Root causes:**
1. Gateway DHCP not restarted after config change
2. Client not renewing DHCP lease
3. Gateway configuration not saved properly

**Diagnostics:**
```bash
# 1. Check gateway DHCP configuration
# For Huawei HG659b: Log in to http://192.168.1.1
# Navigate to: Network Setup > DHCP Server > DNS Settings
# Verify Primary DNS is set to 10.43.244.220

# 2. On client, check current DNS:
# Windows:
ipconfig /all | grep -i "dns"

# macOS:
networksetup -getdnsservers "Wi-Fi"

# Linux:
cat /etc/resolv.conf | grep nameserver
```

**Fixes:**
```bash
# 1. Force DHCP lease renewal on client:

# Windows (PowerShell):
ipconfig /release
ipconfig /renew

# macOS:
# System Preferences > Network > Wi-Fi > Advanced > TCP/IP > Renew DHCP Lease
# Or via CLI: networksetup -renew "Wi-Fi"

# Linux:
sudo dhclient -r
sudo dhclient

# iOS:
# Settings > Wi-Fi > Forget Network > Reconnect

# Android:
# Settings > Wi-Fi > Forget Network > Reconnect

# 2. If still not working, restart gateway DHCP service:
# Via Huawei web UI: 
# Network Setup > DHCP Server > Restart Service
# Or via SSH:
ssh admin@192.168.1.1
dnsmasq restart
# or: /etc/init.d/dnsmasq restart

# 3. Verify gateway configuration was saved:
# Check that PiHole IP (10.43.244.220) is set in DHCP settings
# Not the gateway IP (192.168.1.1)
```

---

### Issue 4: Some domains resolve, others timeout

**Symptoms:**
- example.com resolves fine
- cloudflare.com times out
- Upstream DNS queries failing

**Root causes:**
1. Upstream DNS not configured in PiHole
2. Network connectivity issue from PiHole to upstream
3. Upstream DNS IP is incorrect or not reachable

**Diagnostics:**
```bash
# 1. Check upstream DNS configuration
# Access: http://pihole.watarystack.org/admin
# Settings > DNS > Upstream DNS Servers
# Should have at least one upstream configured (e.g., 8.8.8.8)

# 2. Test connectivity from PiHole pod to upstream
kubectl exec deployment/pihole -n pihole -- ping -c 2 8.8.8.8
# Should respond if internet connectivity is available

# 3. Test specific domain from PiHole
kubectl exec deployment/pihole -n pihole -- nslookup cloudflare.com localhost
# Should resolve if upstream DNS is working

# 4. Check PiHole logs
kubectl logs deployment/pihole -n pihole | grep -i "error\|fail\|dns"
```

**Fixes:**
```bash
# 1. Configure upstream DNS via admin UI
# http://pihole.watarystack.org/admin > Settings > DNS > Upstream DNS Servers
# Add: 8.8.8.8, 1.1.1.1, or other public DNS

# 2. Verify cluster pod has internet access
kubectl run debug --image=busybox --rm -it -- sh
ping 8.8.8.8
nslookup google.com
exit

# 3. Check firewall rules on cluster
# PiHole pod may need egress rule to reach upstream DNS
kubectl get networkpolicies -A
kubectl describe networkpolicy -n pihole

# 4. Restart PiHole pod
kubectl rollout restart deployment/pihole -n pihole
```

---

### Issue 5: PiHole pod crash (CrashLoopBackOff)

**Symptoms:**
- Pod status shows CrashLoopBackOff
- Restarts continuously
- No logs available or logs show errors

**Root causes:**
1. PVC not mounted or not available
2. Insufficient permissions on /etc/pihole
3. Invalid configuration
4. Resource limits exceeded
5. Port 53 already in use

**Diagnostics:**
```bash
# 1. Check pod status and events
kubectl describe pod -n pihole <pod-name>
# Look for events section showing error details

# 2. Check logs (if available)
kubectl logs deployment/pihole -n pihole --tail=50
# May be empty if pod fails to start

# 3. Check PVC status
kubectl get pvc -n pihole
# Should be Bound

# 4. Check node resources
kubectl top nodes
# Check CPU and memory availability

# 5. Check file permissions on node
# (If you have node SSH access)
ssh <node-ip>
ls -la /var/lib/longhorn/  # or check mount point
```

**Fixes:**
```bash
# 1. If PVC issue:
kubectl get pvc -n pihole
# If status is Pending, Longhorn may not be ready
kubectl get pods -n longhorn-system
# Verify longhorn pods are running

# 2. If permissions issue:
kubectl delete pod -n pihole <pod-name>
# Pod will be recreated with fresh permissions

# 3. If port conflict:
# Check if another service is using port 53
sudo netstat -tuln | grep 53

# 4. If resource limits exceeded:
# Check current usage:
kubectl top pods -n pihole

# 5. Force recreation:
kubectl rollout restart deployment/pihole -n pihole

# 6. Check node disk space
df -h
# Ensure cluster node has free space
```

---

### Issue 6: PiHole web UI not accessible

**Symptoms:**
- Cannot reach http://pihole.watarystack.org/admin
- Connection refused or timeout
- Port 80 not responding

**Root causes:**
1. PiHole pod crashed
2. Service port 80 not exposed
3. DNS not resolving pihole.watarystack.org
4. Network connectivity issue

**Diagnostics:**
```bash
# 1. Check pod status
kubectl get pods -n pihole
# Should be Running, 1/1 Ready

# 2. Check service port 80
kubectl get svc -n pihole pihole
# Should list 80/TCP in PORT(S)

# 3. Try direct IP access
# Forward local port to service
kubectl port-forward svc/pihole 8080:80 -n pihole &
# Then visit: http://localhost:8080/admin

# 4. Check if pihole.watarystack.org resolves
nslookup pihole.watarystack.org
# Should resolve to cluster IP or internal IP

# 5. Check logs
kubectl logs deployment/pihole -n pihole | grep -i "http\|admin"
```

**Fixes:**
```bash
# 1. Restart PiHole pod
kubectl rollout restart deployment/pihole -n pihole

# 2. If service is misconfigured:
kubectl delete svc -n pihole pihole
kubectl apply -k apps/staging/pihole/

# 3. Use port-forward to access directly:
kubectl port-forward svc/pihole 8080:80 -n pihole
# Then visit: http://localhost:8080/admin

# 4. Check DNS resolution
# If pihole.watarystack.org doesn't resolve, add DNS entry
# or use direct IP: kubectl get svc -n pihole pihole -o jsonpath='{.spec.clusterIP}'
```

---

## Quick Reference Commands

```bash
# Overall health check
kubectl get pods -n pihole && \
kubectl get svc -n pihole && \
kubectl get pvc -n pihole

# Full diagnostics
echo "=== Pod Status ===" && \
kubectl get pods -n pihole -o wide && \
echo "=== Service ===" && \
kubectl get svc -n pihole -o wide && \
echo "=== DNS Test ===" && \
kubectl exec deployment/pihole -n pihole -- nslookup example.com localhost && \
echo "=== Ad-block Test ===" && \
kubectl exec deployment/pihole -n pihole -- nslookup ads.google.com localhost

# Restart PiHole
kubectl rollout restart deployment/pihole -n pihole

# View real-time logs
kubectl logs -f deployment/pihole -n pihole

# Check resource usage
kubectl top pod -n pihole

# Describe pod for events
kubectl describe pod -n pihole <pod-name>
```

---

## When to Escalate

If none of the above fixes work:

1. **Cluster connectivity issue:**
   - Check if cluster is reachable
   - Verify K3s control plane is responsive
   - Run: `kubectl get nodes`

2. **Network infrastructure issue:**
   - Verify gateway is accessible
   - Check if other cluster pods can reach gateway
   - Ping gateway from cluster pod

3. **Storage issue:**
   - Check Longhorn cluster health
   - Verify PVC can be mounted by other pods
   - Check node disk space

4. **DNS/routing issue:**
   - Verify CoreDNS is running in kube-system
   - Check K3s cluster DNS configuration
   - Review network policies for blocking rules

Contact cluster administrator with:
- Output of: `kubectl describe pod -n pihole <pod-name>`
- Last 50 lines of logs: `kubectl logs deployment/pihole -n pihole --tail=50`
- Service status: `kubectl get svc -n pihole pihole -o yaml`
