---
name: new-house-move
description: Recovery checklist for when the HomeLab cluster moves to a new house/network. Use this skill when the user says things like "I moved to a new house", "new house new network", "my IP changed", "services are down after moving", "status page shows everything red after move", "changed networks and cluster is broken". This handles DNS, CoreDNS, Cloudflare tunnel updates, and Pi-hole config after a network change.
compatibility: kubectl, ssh, git
---

# New House Move — HomeLab Recovery Skill

## Context

**Cluster:** K3s on `santi@192.168.68.112` (control plane), workers at `192.168.68.110` and `192.168.68.111`
**Git:** `https://github.com/santiagobermudezparra/HomeLab-Pro`, all pushes from the server
**Access pattern:**
- **Traefik Ingress** services (internal): DNS must resolve to the Traefik LoadBalancer IP
- **Cloudflare Tunnel** services (public via cloudflared): DNS goes through Cloudflare → tunnel, IP-independent

## Step 0 — Connect to the new node

```bash
ssh santi@<NEW_IP>
```

Ask the user for the new IP if not already known. Then update the session memory with the new IP.

## Step 1 — Check cluster health

```bash
kubectl get nodes -o wide
kubectl get pods -A | grep -v "Running\|Completed"
```

**Expected:** All nodes Ready. If nodes are NotReady, workers have not reconfigured yet — ask the user to check their k3s-agent config (`/etc/systemd/system/k3s-agent.service`) and ensure `K3S_URL` points to the new control-plane IP.

## Step 2 — Identify what is failing

```bash
kubectl logs -n gatus $(kubectl get pods -n gatus --no-headers | grep "^gatus-" | awk "{print \$1}") --tail=40
```

**Pattern to look for:**
- Services with `duration=10s` or `10.001s` → DNS timeout (cannot resolve hostname)
- Services with `duration=<100ms` and `success=false` → TCP refused / TLS error
- Services with `success=true` → already working (Cloudflare tunnel services are usually fine)

**Traefik Ingress services** (internal DNS dependent) — typically fail after move:
- `homepage.watarystack.org`, `forgejo.watarystack.org`, `grafana.watarystack.org`
- `prometheus.watarystack.org`, `alertmanager.watarystack.org`, `headlamp.watarystack.org`
- `pihole.watarystack.org`, `longhorn.watarystack.org`, `hubble.watarystack.org`
- `xmspotify.watarystack.org`

**Cloudflare Tunnel services** (IP-independent) — usually survive a house move:
- `linkding`, `mealie`, `n8n`, `filebrowser`, `wallabag`, `pgadmin`, `audiobookshelf`

## Step 3 — Fix CoreDNS (root cause for Traefik services)

The cluster internal DNS (CoreDNS) forwards `watarystack.org` queries upstream, which returns the OLD IP.

First, find the new Traefik LoadBalancer IP:
```bash
kubectl get svc -n kube-system traefik
# Use the control-plane IP from EXTERNAL-IP
```

Then apply the override (replace `NEW_TRAEFIK_IP` with the actual IP):

```bash
kubectl apply -f - << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  watarystack.server: |
    watarystack.org:53 {
      errors
      hosts {
        NEW_TRAEFIK_IP homepage.watarystack.org
        NEW_TRAEFIK_IP forgejo.watarystack.org
        NEW_TRAEFIK_IP grafana.watarystack.org
        NEW_TRAEFIK_IP prometheus.watarystack.org
        NEW_TRAEFIK_IP alertmanager.watarystack.org
        NEW_TRAEFIK_IP headlamp.watarystack.org
        NEW_TRAEFIK_IP pihole.watarystack.org
        NEW_TRAEFIK_IP longhorn.watarystack.org
        NEW_TRAEFIK_IP hubble.watarystack.org
        NEW_TRAEFIK_IP xmspotify.watarystack.org
        fallthrough
      }
      forward . 8.8.8.8
    }
EOF

kubectl rollout restart deployment -n kube-system coredns
kubectl rollout status deployment -n kube-system coredns --timeout=60s
```

**Why this works:** CoreDNS has `import /etc/coredns/custom/*.server` and already mounts the `coredns-custom` ConfigMap as optional. The `hosts` plugin intercepts only listed Traefik domains; everything else falls through to `8.8.8.8`, so Cloudflare tunnel domains keep resolving correctly.

**Why NOT Pi-hole for this:** Pi-hole v6 (FTL) ignores `/etc/dnsmasq.d/` files dropped into the PVC mount. Use CoreDNS for cluster-internal DNS.

## Step 4 — Verify DNS

```bash
kubectl exec -n headlamp $(kubectl get pods -n headlamp --no-headers | awk "{print \$1}" | head -1) -- sh -c "nslookup homepage.watarystack.org && nslookup forgejo.watarystack.org"
```

Expected: both resolve to `NEW_TRAEFIK_IP`.

## Step 5 — Fix Pi-hole DNS records (for browser access from LAN devices)

Pi-hole is installed but not set as primary DNS for home devices. To fix browser access:

1. Open `https://pihole.watarystack.org` (works once Step 3 is done)
2. Go to **Local DNS → DNS Records**
3. Add one record per Traefik Ingress domain:
   - Domain: `homepage.watarystack.org` → IP: `NEW_TRAEFIK_IP`
   - Repeat for all domains in Step 3
4. Point your **router** to Pi-hole as the DNS server so all LAN devices benefit automatically

## Step 6 — Update Cloudflare DNS A records (if needed)

If any Traefik Ingress domains have Cloudflare A records pointing to the old IP, update them:
Cloudflare dashboard → `watarystack.org` zone → DNS → find old IP → update to new IP.

## Step 7 — Validate

```bash
kubectl logs -n gatus $(kubectl get pods -n gatus --no-headers | grep "^gatus-" | awk "{print \$1}") --tail=40
```

All services should show `success=true` within 2 check cycles (~2 minutes).

## Known Gotchas

| Issue | Cause | Fix |
|-------|-------|-----|
| Pi-hole dnsmasq.d files ignored | Pi-hole v6 FTL ignores custom dnsmasq.d files | Use CoreDNS `hosts` plugin (Step 3) |
| `coredns-custom` CM missing | k3s ships it as optional, not pre-created | `kubectl apply` it fresh (Step 3) |
| Cloudflare tunnel services broken | Should not happen — tunnels are IP-independent | Check `cloudflared` pod logs |
| Worker nodes NotReady | k3s-agent still pointing to old control-plane IP | Update `K3S_URL` in `/etc/systemd/system/k3s-agent.service.env` on each worker |

## Infrastructure Reference (update after each move)

| Component | Value |
|-----------|-------|
| Control plane | `santi@192.168.68.112` |
| Worker 01 | `192.168.68.111` |
| Worker 02 | `192.168.68.110` |
| Traefik LB | `192.168.68.110,192.168.68.111,192.168.68.112` |
| CoreDNS custom CM | `coredns-custom` in `kube-system` |
| Gatus status page | `https://status.watarystack.org` |
