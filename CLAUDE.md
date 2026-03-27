# HomeLab-Pro: Claude Code Guide

## 📋 Project Context

**HomeLab-Pro** is a production-grade Kubernetes homelab managed with GitOps principles. It runs on K3s with FluxCD for declarative deployments, Cloudflare Tunnels for secure external access, and SOPS/age for encrypted secrets.

**Key Info:**
- **GitHub Repo**: `santiagobermudezparra/HomeLab-Pro`
- **Domain**: watarystack.org
- **Cluster**: Staging (K3s)
- **GitOps Controller**: FluxCD
- **Current Apps**: audiobookshelf, homarr, linkding, mealie, n8n, pgadmin, xm-spotify-sync, homepage

---

## 🏗️ Architecture Overview

### Directory Structure

```
HomeLab-Pro/
├── apps/
│   ├── base/                    # Base Kubernetes manifests (reusable across envs)
│   │   └── {app-name}/
│   │       ├── deployment.yaml  # Pod specs
│   │       ├── service.yaml     # Cluster service definition
│   │       ├── namespace.yaml   # Namespace creation
│   │       └── kustomization.yaml
│   └── staging/                 # Environment overlays (staging-specific patches)
│       └── {app-name}/
│           ├── kustomization.yaml
│           ├── cloudflare.yaml  # Tunnel routing config
│           ├── cloudflare-secret.yaml (SOPS-encrypted)
│           └── {app-name}-*-secret.yaml (SOPS-encrypted)
├── clusters/
│   └── staging/
│       ├── apps.yaml            # Flux Kustomization pointing to ./apps/staging
│       ├── infrastructure.yaml
│       └── monitoring.yaml
├── infrastructure/
│   ├── controllers/             # Infrastructure operators (cert-manager, traefik, etc.)
│   └── configs/                 # Infrastructure configurations
├── monitoring/
│   ├── controllers/             # Prometheus, Grafana, AlertManager operators
│   └── configs/                 # Monitoring dashboards and rules
└── databases/
    └── staging/                 # Database clusters (PostgreSQL via CloudNativePG)
```

### Deployment Flow

```
Git Commit → FluxCD Sync (1min interval) → Kustomize Build → kubectl apply → Running Pods
```

---

## 🔑 Key Technologies & Patterns

### Kubernetes Structure
- **Base/Overlay Pattern**: Base configs in `apps/base/`, environment-specific overlays in `apps/staging/`
- **Kustomize**: Native Kubernetes templating (no Helm)
- **Namespaces**: Each app gets its own namespace for isolation

### Secret Management
- **SOPS + age**: All secrets encrypted at rest in Git
- **Age Key**: Located in `clusters/staging/.sops.yaml` (`age1spwc8lctzldd0ghkkls8jfvzzra7cx95r2zqq6eya84etq65wfgqy2h99p`)
- **Flux Decryption**: FluxCD automatically decrypts using the `sops-age` secret in `flux-system` namespace
- **Encryption Regex**: Only `data` and `stringData` fields are encrypted

### External Access
- **Cloudflare Tunnels**: Zero-trust network access (no port forwarding)
- **Per-App Tunnel Deployment**: Each app gets its own `cloudflared` deployment in the app namespace
- **Tunnel Config**: Specified in `cloudflare.yaml` ConfigMap + `cloudflare-secret.yaml` Secret

### Certificate Management
- **cert-manager**: Automated TLS certificate generation via Let's Encrypt
- **DNS-01 Challenge**: Cloudflare DNS validation
- **Internal Services**: Use internal TLS (infrastructure, monitoring)
- **External Services**: Use Cloudflare Tunnel (no need for ingress)

---

## 🚀 Adding a New App to HomeLab

### The Standard Workflow

Use the **HomeLab App Onboarding** skill to automate this. Trigger it by saying things like:
- "Add X app to my homelab"
- "Deploy X to my Kubernetes cluster"
- "Onboard X service to my homelab"

The skill handles all steps below automatically. If you need to do it manually, follow this process:

### Manual Steps (if not using the skill)

#### 1. Gather App Requirements
- **APP_NAME**: Short identifier (e.g., `vaultwarden`)
- **APP_PORT**: Internal port the app listens on (e.g., `80`, `8080`)
- **APP_HOSTNAME**: Full domain (e.g., `vaultwarden.watarystack.org`)
- **APP_IMAGE**: Container image with tag (e.g., `vaultwarden/server:latest`)
- **TUNNEL_NAME**: Cloudflare tunnel name (must already exist via `cloudflared tunnel create <name>`)
- **TUNNEL_JSON**: Path to tunnel credentials file (e.g., `~/.cloudflared/59c97568-*.json`)
- **SECRETS**: Any app-specific secrets (admin passwords, API keys, etc.)

#### 2. Create Git Branch
```bash
git checkout main && git pull origin main
git checkout -b feat/add-${APP_NAME}
```

#### 3. Create Base Configuration
Create `apps/base/${APP_NAME}/`:
```bash
mkdir -p apps/base/${APP_NAME}
touch apps/base/${APP_NAME}/{namespace,deployment,service,kustomization}.yaml
```

**namespace.yaml**:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ${APP_NAME}
```

**deployment.yaml**: Pod spec with container, env vars, volumes, security context
**service.yaml**: ClusterIP service exposing the app port
**kustomization.yaml**: References the three above

#### 4. Create Staging Overlay
Create `apps/staging/${APP_NAME}/` with:
- **kustomization.yaml**: References base, applies patches
- **cloudflare-secret.yaml**: SOPS-encrypted tunnel credentials
- **cloudflare.yaml**: ConfigMap with tunnel routing config
- **{APP_NAME}-*-secret.yaml**: SOPS-encrypted app secrets (admin user, API keys, etc.)

#### 5. Encrypt Secrets with SOPS
```bash
# Create secret in plaintext first
kubectl create secret generic tunnel-credentials \
  --from-file=credentials.json=${TUNNEL_JSON} \
  --dry-run=client -o yaml > cloudflare-secret.yaml

# Encrypt with age key
sops --age=$(grep age clusters/staging/.sops.yaml | awk '{print $NF}') \
  --encrypt --encrypted-regex '^(data|stringData)$' \
  --in-place cloudflare-secret.yaml
```

#### 6. Update Main Kustomization
Edit `apps/staging/kustomization.yaml` to include the new app:
```yaml
resources:
  - linkding
  - mealie
  - ${APP_NAME}  # Add here
```

#### 7. Commit & Push
```bash
git add apps/
git commit -m "feat: add ${APP_NAME} to homelab"
git push origin feat/add-${APP_NAME}
```

#### 8. Open PR
```bash
gh pr create \
  --base main \
  --head feat/add-${APP_NAME} \
  --title "feat: add ${APP_NAME} to homelab" \
  --body "Adds ${APP_NAME} with Cloudflare tunnel access at ${APP_HOSTNAME}."
```

---

## 📋 Common Tasks

### View Deployment Status
```bash
flux get kustomizations
flux get sources git
kubectl get pods --all-namespaces
```

### Check App Logs
```bash
kubectl logs -f deployment/${APP_NAME} -n ${APP_NAME}
```

### Decrypt a Secret (for inspection)
```bash
sops --age=$(grep age clusters/staging/.sops.yaml | awk '{print $NF}') \
  -d apps/staging/${APP_NAME}/${APP_NAME}-secret.yaml
```

### Restart an App
```bash
kubectl rollout restart deployment/${APP_NAME} -n ${APP_NAME}
```

### Verify Tunnel Configuration
Check that the tunnel is running:
```bash
cloudflared tunnel list
cloudflared tunnel info ${TUNNEL_NAME}
```

---

## 🔐 Security Practices

### Secret Handling
- **Never** commit unencrypted secrets to Git
- **Always** use SOPS to encrypt before committing
- **Verify** encrypted secrets have `data` and `stringData` fields encrypted (check file for `ENC[AES256_GCM`)

### Secret Rotation
To rotate secrets:
1. Decrypt the secret file locally (for inspection)
2. Edit the decrypted values
3. Re-encrypt with SOPS
4. Commit and push

### Cloudflare Tunnel Security
- Each app has its own tunnel deployment (not shared)
- Tunnel credentials are SOPS-encrypted in Git
- CloudFlare handles DDoS protection and TLS

---

## 🧪 Development Workflow

### Testing Manifest Changes
```bash
# Validate Kubernetes manifests
kubectl apply -k apps/staging/${APP_NAME}/ --dry-run=client

# Or build kustomization to see final output
kustomize build apps/staging/${APP_NAME}/
```

### Testing without FluxCD (Manual Apply)
```bash
# For quick testing, manually apply without committing
kubectl apply -k apps/staging/${APP_NAME}/

# Verify it's running
kubectl get pods -n ${APP_NAME}
```

### Reverting Changes
If something breaks after a commit:
```bash
git revert <commit-hash>
git push origin main
# FluxCD will automatically sync the revert
```

---

## 🆘 Troubleshooting

### App Pod Not Starting
```bash
# Check pod status
kubectl describe pod <pod-name> -n ${APP_NAME}

# View logs
kubectl logs <pod-name> -n ${APP_NAME}

# Common issues:
# - Image pull errors: Check image exists and credentials
# - Secret mount errors: Verify secret name in deployment matches kustomization
# - Port conflicts: Check service port vs container port
```

### Cloudflare Tunnel Not Working
```bash
# Check tunnel is running
kubectl get pods -n ${APP_NAME} | grep cloudflared

# View tunnel logs
kubectl logs -f deployment/cloudflared -n ${APP_NAME}

# Verify config
kubectl get configmap cloudflared -n ${APP_NAME} -o yaml

# Check DNS in Cloudflare console:
# - CNAME record exists pointing to <tunnel-uuid>.cfargotunnel.com
# - Orange cloud (proxied) enabled
```

### Secret Decryption Issues
```bash
# Verify age key in cluster
kubectl get secret sops-age -n flux-system -o yaml

# Check FluxCD logs
flux logs --namespace flux-system

# Manually decrypt to test
sops -d apps/staging/${APP_NAME}/${APP_NAME}-secret.yaml
```

### FluxCD Not Syncing
```bash
flux get sources git
flux get kustomizations
flux logs --all-namespaces

# Force sync
flux reconcile source git flux-system
flux reconcile kustomization apps
```

---

## 📚 External Resources

- **FluxCD Docs**: https://fluxcd.io/docs/
- **Kustomize Docs**: https://kustomize.io/
- **SOPS**: https://github.com/mozilla/sops
- **cert-manager**: https://cert-manager.io/docs/
- **Cloudflare Tunnels**: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/
- **Kubernetes Docs**: https://kubernetes.io/docs/

---

## 🎯 Claude Preferences for This Repo

### When Adding New Apps
1. **Always use the HomeLab App Onboarding skill** — it handles all steps and opens a PR automatically
2. **Follow the base/overlay pattern** — keep base configs reusable, environment-specific stuff in overlays
3. **Encrypt all secrets** — don't let unencrypted secrets into the repo
4. **Branch from main** — never commit directly to main

### When Debugging
1. Start with `flux logs --all-namespaces` to see what FluxCD is doing
2. Check pod status with `kubectl describe pod`
3. Decrypt and inspect secrets only when necessary
4. Don't restart services unless needed — let FluxCD manage reconciliation

### When Making Config Changes
1. Test with `--dry-run=client` first
2. Create a feature branch and PR
3. Let FluxCD auto-apply once merged
4. Monitor with `flux get kustomizations`

---

## 📞 Quick Reference

| Task | Command |
|------|---------|
| Deploy new app | Use **HomeLab App Onboarding** skill |
| Check status | `flux get kustomizations` |
| View logs | `kubectl logs -f deployment/{app} -n {app}` |
| Decrypt secret | `sops -d apps/staging/{app}/*-secret.yaml` |
| Restart app | `kubectl rollout restart deployment/{app} -n {app}` |
| Test manifest | `kubectl apply -k apps/staging/{app}/ --dry-run=client` |

---

**Last Updated**: March 28, 2026
**Created for**: Santiago Bermudez (@santiagobermudezparra)
**Audience**: Claude Code users working on this HomeLab project
