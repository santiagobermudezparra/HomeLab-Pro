# HomeLab App Onboarding - Quick Checklist

Use this checklist when onboarding a new app. Print it out or reference it as you go through the steps.

## Pre-Flight Check
- [ ] App name decided (lowercase, no spaces): `_________________`
- [ ] Image and tag known: `_________________`
- [ ] Port the app listens on: `_________________`
- [ ] Final hostname: `_________________` (e.g., myapp.watarystack.org)
- [ ] **Access type**: Public (Cloudflare Tunnel) / Internal (Traefik Ingress)
- [ ] *If public:* Tunnel name exists: `_________________` (run `cloudflared tunnel list`)
- [ ] *If public:* Tunnel credentials file: `_________________` (usually `~/.cloudflared/[uuid].json`)
- [ ] Secrets the app needs listed: (see below)
- [ ] Database required?: Yes / No (if yes, which type?: `_________________`)

## Secrets Required
List all secrets/env vars the app needs (e.g., admin password, API keys):
```
1. _________________________ = _________________________
2. _________________________ = _________________________
3. _________________________ = _________________________
```

## Step-by-Step

### 1. Create Branch
```bash
git checkout main && git pull origin main
git checkout -b feat/add-{APP_NAME}
```
- [ ] Branch created

### 2. Create Base Configuration
```bash
mkdir -p apps/base/{APP_NAME}
touch apps/base/{APP_NAME}/{namespace,deployment,service,kustomization}.yaml
```

**namespace.yaml**: Create namespace resource
- [ ] Created

**deployment.yaml**: Pod spec with container, ports, env, resources, volumes
- [ ] Image: `_________________`
- [ ] Port: `_________________`
- [ ] Resources set (memory/cpu requests and limits)
- [ ] Env vars for app config
- [ ] Secrets mounted
- [ ] PVC mounted (if stateful): Yes / No

**service.yaml**: ClusterIP service
- [ ] Service port: `_________________`
- [ ] Target port matches container port

**kustomization.yaml**: Resources list
- [ ] References all three files above

### 3. Create Staging Overlay
```bash
mkdir -p apps/staging/{APP_NAME}
```

**kustomization.yaml**: References base + overlays
- [ ] Lists all resources

**If public — cloudflare.yaml**: ConfigMap + cloudflared Deployment
- [ ] Tunnel name: `_________________`
- [ ] Hostname: `_________________`
- [ ] App service name: `_________________`
- [ ] App port: `_________________`

**If public — cloudflare-secret.yaml**: SOPS-encrypted tunnel credentials
```bash
kubectl create secret generic tunnel-credentials \
  --from-file=credentials.json={TUNNEL_JSON} \
  --dry-run=client -o yaml > cloudflare-secret.yaml

sops --age={AGE_KEY} --encrypt --encrypted-regex '^(data|stringData)$' --in-place cloudflare-secret.yaml
```
- [ ] Created
- [ ] Encrypted (check for `ENC[AES256_GCM`)

**If internal — ingress.yaml**: Traefik Ingress resource with cert-manager TLS
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {APP_NAME}
  namespace: {APP_NAME}
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-cloudflare-prod
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - {APP_HOSTNAME}
      secretName: {APP_NAME}-tls
  rules:
    - host: {APP_HOSTNAME}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {APP_NAME}
                port:
                  number: {APP_PORT}
```
- [ ] Created (no encryption needed — no secrets here)
- [ ] cert-manager will auto-provision the TLS cert (`{APP_NAME}-tls` secret)

**{APP_NAME}-env-secret.yaml**: SOPS-encrypted app secrets
```bash
kubectl create secret generic {APP_NAME}-env-secret \
  --from-literal=KEY1=value1 \
  --from-literal=KEY2=value2 \
  --dry-run=client -o yaml > {APP_NAME}-env-secret.yaml

sops --age={AGE_KEY} --encrypt --encrypted-regex '^(data|stringData)$' --in-place {APP_NAME}-env-secret.yaml
```
- [ ] Created
- [ ] All secrets included
- [ ] Encrypted (check for `ENC[AES256_GCM`)

**{APP_NAME}-config ConfigMap** (if needed):
- [ ] Created (if app needs non-secret config)

### 4. Access Setup

**If public — Cloudflare DNS Setup (MANUAL - Do This in Browser):**
1. [ ] Log into Cloudflare dashboard
2. [ ] Select domain: `watarystack.org`
3. [ ] Go to DNS → Records
4. [ ] Click "Add record"
5. [ ] Set:
   - [ ] Type: CNAME
   - [ ] Name: `_________________` (just subdomain, e.g., `myapp`)
   - [ ] Target: `_________________` (get from credentials JSON TunnelID field, add `.cfargotunnel.com`)
   - [ ] Proxy status: Proxied (orange cloud)
6. [ ] Click Save
7. [ ] Verify: Takes a few minutes to propagate

**If internal — Local DNS Setup:**
- [ ] Add hostname `{APP_HOSTNAME}` → cluster IP to Pi-hole / local DNS / `/etc/hosts`
- [ ] No Cloudflare setup required

### 5. Update Main Kustomization
Edit `apps/staging/kustomization.yaml`:
- [ ] Added `{APP_NAME}` to resources list

### 6. Test Manifests
```bash
kubectl apply -k apps/staging/{APP_NAME}/ --dry-run=client -o yaml
kustomize build apps/staging/{APP_NAME}/
```
- [ ] No validation errors

### 7. Commit & Push
```bash
git add apps/
git commit -m "feat: add {APP_NAME} to homelab

- Create base deployment, service, namespace
- Add staging overlay with Cloudflare tunnel config
- SOPS-encrypt tunnel credentials and app secrets"

git push origin feat/add-{APP_NAME}
```
- [ ] Committed with good message
- [ ] Pushed to origin

### 8. Open Pull Request
```bash
gh pr create \
  --base main \
  --head feat/add-{APP_NAME} \
  --title "feat: add {APP_NAME} to homelab" \
  --body "Description of app, port, hostname, tunnel"
```
- [ ] PR opened
- [ ] PR URL: `_________________`

### 9. Review & Merge
- [ ] PR reviewed
- [ ] All checks passed
- [ ] Merged to main
- [ ] Feature branch deleted

### 10. Monitor Deployment
```bash
flux get kustomizations                          # See sync status
kubectl get pods -n {APP_NAME}                   # Check pod status
kubectl logs -f deployment/{APP_NAME} -n {APP_NAME}    # App logs
kubectl logs -f deployment/cloudflared -n {APP_NAME}   # Tunnel logs
```
- [ ] Flux reconciled
- [ ] Pod running (Ready 1/1)
- [ ] No errors in logs
- [ ] Cloudflared tunnel healthy
- [ ] App accessible at `{APP_HOSTNAME}`

## Troubleshooting Checklist

If something doesn't work:

### Pod won't start
```bash
kubectl describe pod -n {APP_NAME} $(kubectl get pod -n {APP_NAME} -o name | head -1)
kubectl logs -n {APP_NAME} $(kubectl get pod -n {APP_NAME} -o name | head -1)
```
- [ ] Image exists and is correct
- [ ] All required secrets are present
- [ ] Resource requests are reasonable
- [ ] No port conflicts

### Can't access app via tunnel
```bash
kubectl logs -f deployment/cloudflared -n {APP_NAME}
kubectl get configmap cloudflared -n {APP_NAME} -o yaml
```
- [ ] CNAME record created in Cloudflare DNS
- [ ] Tunnel name matches credentials
- [ ] Service name matches cloudflare.yaml config
- [ ] Port matches

### Secrets not decrypted
```bash
sops -d apps/staging/{APP_NAME}/{APP_NAME}-secret.yaml
flux logs --namespace flux-system
```
- [ ] Age key in cluster matches .sops.yaml
- [ ] Secret encrypted with correct age key
- [ ] FluxCD has permission to decrypt

### General Debug
```bash
# View all resources in app namespace
kubectl get all -n {APP_NAME}

# View all secrets
kubectl get secrets -n {APP_NAME}

# Inspect specific secret (decrypted)
sops -d apps/staging/{APP_NAME}/{APP_NAME}-env-secret.yaml

# Check FluxCD status
flux get kustomizations
flux logs --all-namespaces

# Port-forward to test app locally
kubectl port-forward svc/{APP_NAME} 8080:{APP_PORT} -n {APP_NAME}
# Then visit http://localhost:8080
```

---

## File Locations Reference

| File | Path | Purpose |
|------|------|---------|
| Base namespace | `apps/base/{APP_NAME}/namespace.yaml` | Create namespace |
| Base deployment | `apps/base/{APP_NAME}/deployment.yaml` | Pod spec |
| Base service | `apps/base/{APP_NAME}/service.yaml` | Cluster service |
| Base kustomization | `apps/base/{APP_NAME}/kustomization.yaml` | Base resources |
| Staging kustomization | `apps/staging/{APP_NAME}/kustomization.yaml` | Overlay resources |
| Tunnel config | `apps/staging/{APP_NAME}/cloudflare.yaml` | Tunnel routing |
| Tunnel secret | `apps/staging/{APP_NAME}/cloudflare-secret.yaml` | Tunnel credentials (encrypted) |
| App secret | `apps/staging/{APP_NAME}/{APP_NAME}-env-secret.yaml` | App env secrets (encrypted) |
| SOPS config | `clusters/staging/.sops.yaml` | Age key for encryption |
| Main kustomization | `apps/staging/kustomization.yaml` | Wire up all apps |

---

## Key Commands Quick Reference

```bash
# Encrypt a secret file
sops --age=$(grep age clusters/staging/.sops.yaml | awk '{print $NF}') \
  --encrypt --encrypted-regex '^(data|stringData)$' --in-place <file>

# Decrypt a secret (view only)
sops -d apps/staging/{APP_NAME}/{APP_NAME}-secret.yaml

# Test Kubernetes manifests
kubectl apply -k apps/staging/{APP_NAME}/ --dry-run=client -o yaml

# Build final manifest
kustomize build apps/staging/{APP_NAME}/

# Check app status
kubectl get pods -n {APP_NAME}
kubectl logs -f deployment/{APP_NAME} -n {APP_NAME}

# Check tunnel status
kubectl logs -f deployment/cloudflared -n {APP_NAME}
kubectl get configmap cloudflared -n {APP_NAME} -o yaml

# Watch FluxCD sync
flux get kustomizations
flux logs --all-namespaces

# Port-forward to test locally
kubectl port-forward svc/{APP_NAME} 8080:{APP_PORT} -n {APP_NAME}

# List tunnels
cloudflared tunnel list

# Check if tunnel credentials exist
ls ~/.cloudflared/*.json
```

---

**Print this out or keep it open while onboarding apps!**
