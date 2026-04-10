---
name: homelab-app-onboarding
description: Automate deploying new apps to a Kubernetes homelab. Supports both public access via Cloudflare Tunnels and internal/local access via Traefik Ingress. Use this skill whenever the user wants to add a new service to their homelab — phrases like "deploy X to homelab", "add X app to my cluster", "set up X in kubernetes", "onboard X to my homelab", or even just "I want to run X at home". This handles everything: creating Kubernetes manifests, encrypting secrets with SOPS, configuring access (Cloudflare tunnel or Traefik ingress), and opening a PR.
compatibility: git, kubectl, sops, age, cloudflared
---

# HomeLab App Onboarding Skill

Automate the full deployment of a new application to your Kubernetes homelab. This skill creates base and overlay configurations, encrypts secrets, sets up Cloudflare tunnel routing, and opens a pull request.

## Prerequisites Check

Before starting, verify your environment is set up:

- [ ] `cloudflared` installed and authenticated (`~/.cloudflared/cert.pem` exists)
- [ ] `sops` and `age` installed
- [ ] `AGE_PUBLIC` exported in shell or .sops.yaml contains the key
- [ ] Git repository cloned locally
- [ ] `gh` (GitHub CLI) available for PR creation
- [ ] Kubectl configured and can access cluster

If any prerequisite is missing, pause and ask the user to fix it before continuing.

## Step 0 — Gather Information

Ask the user for these details. If they've already provided some in the conversation, extract and confirm rather than re-asking:

| Variable | Example | Purpose |
|----------|---------|---------|
| `APP_NAME` | `vaultwarden`, `paperless`, `stirling-pdf` | App identifier (lowercase, no spaces) |
| `APP_PORT` | `8080`, `3000` | Internal port the app listens on — check existing apps and pick one not already in use |
| `APP_IMAGE` | `docker.io/user/image:latest` | Full container image with tag |
| `APP_HOSTNAME` | `myapp.watarystack.org` | Full domain for access |
| `ACCESS_TYPE` | `public` or `internal` | **public** = Cloudflare Tunnel (internet-accessible); **internal** = Traefik Ingress (local network only) |
| `DB_REQUIRED` | `yes`/`no` | Does the app need a database? |
| `DB_TYPE` | `postgres`, `sqlite` | If yes, which database system |
| `USE_CNPG` | `yes`/`no` | **Only ask if `DB_TYPE=postgres`** — do you want CloudNativePG to manage the PostgreSQL cluster? If the user hasn't said, use your knowledge of the app to decide if it supports PostgreSQL (e.g., Vaultwarden, Gitea, Outline → yes; apps that only use SQLite or have no DB option → don't ask at all). If unsure, ask the user. |
| `SECRETS` | `ADMIN_USER=admin`, `API_KEY=xyz` | Key=value pairs for env secrets |

**When to use each access type:**
- **`public`** — app needs to be reachable from the internet (Cloudflare Tunnel handles routing + DDoS protection)
- **`internal`** — app is only for home network / LAN access (Traefik Ingress is simpler, no tunnel required)

**CloudNativePG decision logic:**
- If `DB_TYPE` is NOT `postgres` (e.g., sqlite, no DB): skip `USE_CNPG` entirely — don't even mention it
- If `DB_TYPE=postgres` AND you know the app supports it: ask "Do you want CloudNativePG to manage the PostgreSQL cluster? (Recommended — matches linkding/n8n setup)"
- If `USE_CNPG=yes`: also gather:
  - `DB_NAME` — database name (default: `${APP_NAME}`)
  - `DB_USER` — database owner username (default: `${APP_NAME}`)
  - `R2_ACCESS_KEY_ID` and `R2_ACCESS_KEY_SECRET` — Cloudflare R2 credentials for backups (tell user: "Same R2 bucket as linkding/n8n — just need a new access key pair for this app, or reuse existing if already shared")
  - `R2_BUCKET_PATH` — S3 destination (default: `s3://homelab-postgres-backup/${APP_NAME}`)
  - `R2_ENDPOINT_URL` — R2 endpoint (default: existing one from linkding: `https://cf504e28de7836d9611b6774cdcb303e.r2.cloudflarestorage.com`)

**Port conflict check — always run this before picking a port:**
```bash
grep -r "containerPort\|port:" apps/base/*/service.yaml apps/base/*/deployment.yaml 2>/dev/null | grep -oP '\d+' | sort -u
```

Do NOT ask the user for `TUNNEL_JSON` — it will be created automatically in Step 1.5 (public mode only).

Confirm all details before proceeding.

## Step 1 — Create Git Branch

Always branch from main. Never commit directly to main.

```bash
cd /path/to/HomeLab-Pro
git checkout main
git pull origin main
git checkout -b feat/add-${APP_NAME}
```

## Step 1.5 — Create Cloudflare Tunnel *(public access only — skip if internal)*

**Always create a new tunnel for each app.** Do not reuse tunnels across apps.

```bash
cloudflared tunnel create ${APP_NAME}
```

This outputs:
- A tunnel UUID
- The credentials file path: `~/.cloudflared/<UUID>.json`

Capture both — you'll need them for the secret and DNS steps.

```bash
# Confirm tunnel was created
cloudflared tunnel list | grep ${APP_NAME}

# Find the credentials JSON path
TUNNEL_JSON=$(ls ~/.cloudflared/*.json | xargs grep -l "\"TunnelName\":\"${APP_NAME}\"" 2>/dev/null)
echo "Tunnel credentials: $TUNNEL_JSON"
```

> Tell the user the tunnel ID so they can add the CNAME DNS record in Cloudflare:
> `CNAME ${APP_HOSTNAME} → <TUNNEL_UUID>.cfargotunnel.com` (proxied/orange cloud)

## Step 2 — Create Base Configuration

Create the base Kubernetes manifests in `apps/base/${APP_NAME}/`. These are reusable across environments.

### Create Directory
```bash
mkdir -p apps/base/${APP_NAME}
```

### namespace.yaml
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ${APP_NAME}
```

### deployment.yaml

Use this template, adjusting for the app's specific needs:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: node-role.kubernetes.io/control-plane
                operator: DoesNotExist
      containers:
      - name: ${APP_NAME}
        image: ${APP_IMAGE}
        ports:
        - containerPort: ${APP_PORT}
        env:
        - name: PORT
          value: "${APP_PORT}"
        # Add database connection env vars here if needed
        # If USE_CNPG=yes, add these (pointing to the CNPG cluster service):
        # - name: DB_HOST
        #   value: "${APP_NAME}-postgres-rw.${APP_NAME}.svc.cluster.local"
        # - name: DB_PORT
        #   value: "5432"
        # - name: DB_NAME
        #   value: "${DB_NAME}"
        # - name: DB_USER
        #   valueFrom:
        #     secretKeyRef:
        #       name: ${APP_NAME}-db-credentials
        #       key: username
        # - name: DB_PASSWORD
        #   valueFrom:
        #     secretKeyRef:
        #       name: ${APP_NAME}-db-credentials
        #       key: password
        # Note: exact env var names vary by app — check the app's docs
        envFrom:
        - configMapRef:
            name: ${APP_NAME}-config
        - secretRef:
            name: ${APP_NAME}-env-secret
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          readOnlyRootFilesystem: false
```

**Notes:**
- If the app is stateless, you're done
- If it stores data, add a `volumeMounts` section and corresponding `volumes` with PVC — always use `storageClassName: longhorn` (see storage.yaml below)
- If it needs database access, add `LD_DB_HOST`, `LD_DB_PASSWORD` env vars (examples for Postgres)

### storage.yaml *(apps with persistent data only)*

Create a separate `storage.yaml` for PVCs (keeps deployment.yaml clean). Always use `storageClassName: longhorn` — Longhorn is the cluster's default distributed StorageClass (replicated across nodes, not tied to a single host):

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${APP_NAME}-data
  namespace: ${APP_NAME}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
```

If the app needs multiple PVCs (e.g., a DB file + a data directory), define them all in the same `storage.yaml`. When migrating or recreating, always scale to 0 and handle all PVCs atomically — scaling up between PVC operations risks data inconsistency.

Add `storage.yaml` to the base `kustomization.yaml` resources list.

### service.yaml
```yaml
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NAME}
spec:
  type: ClusterIP
  selector:
    app: ${APP_NAME}
  ports:
  - port: ${APP_PORT}
    targetPort: ${APP_PORT}
    protocol: TCP
```

### kustomization.yaml
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${APP_NAME}
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
```

## Step 2.5 — CloudNativePG Database Setup *(only if `USE_CNPG=yes` — skip otherwise)*

Create a managed PostgreSQL cluster for the app, following the exact same pattern as linkding and n8n. This lives in `databases/staging/${APP_NAME}/` (not in `apps/`).

```bash
mkdir -p databases/staging/${APP_NAME}
```

### postgresql-cluster.yaml

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${APP_NAME}-postgres
  namespace: ${APP_NAME}
spec:
  description: "PostgreSQL cluster for ${APP_NAME} application"
  instances: 1

  monitoring:
    enabled: true
    podMonitorEnabled: true

  postgresql:
    parameters:
      max_connections: "100"
      shared_buffers: "128MB"
      effective_cache_size: "512MB"

  storage:
    size: 2Gi
    pvcTemplate:
      storageClassName: longhorn
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 2Gi

  superuserSecret:
    name: ${APP_NAME}-superuser

  bootstrap:
    initdb:
      database: ${DB_NAME}
      owner: ${DB_USER}
      secret:
        name: ${APP_NAME}-db-credentials

  backup:
    barmanObjectStore:
      destinationPath: "${R2_BUCKET_PATH}"
      endpointURL: "${R2_ENDPOINT_URL}"
      s3Credentials:
        accessKeyId:
          name: ${APP_NAME}-backup-s3-secret
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: ${APP_NAME}-backup-s3-secret
          key: ACCESS_KEY_SECRET
      wal:
        compression: gzip
      data:
        compression: gzip
    retentionPolicy: "7d"
```

### backup-config.yaml

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: ${APP_NAME}-backup
  namespace: ${APP_NAME}
spec:
  # Schedule: Daily at 3 AM
  schedule: "0 3 * * *"

  # Backup immediately on creation
  #immediate: true

  # Reference to the cluster
  cluster:
    name: ${APP_NAME}-postgres

  # Retention policy
  backupOwnerReference: cluster
```

### r2-backup-configmap.yaml

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: r2-backup-config
  namespace: ${APP_NAME}
data:
  endpointURL: "${R2_ENDPOINT_URL}"
  destinationPath: "${R2_BUCKET_PATH}"
```

### secrets.yaml

Create SOPS-encrypted DB credentials and superuser secrets:

```bash
# Create db-credentials secret (plaintext first)
kubectl create secret generic ${APP_NAME}-db-credentials \
  --type=kubernetes.io/basic-auth \
  --from-literal=username=${DB_USER} \
  --from-literal=password=$(openssl rand -base64 24) \
  --dry-run=client -o yaml > /tmp/${APP_NAME}-db-creds.yaml

# Create superuser secret
kubectl create secret generic ${APP_NAME}-superuser \
  --from-literal=username=postgres \
  --from-literal=password=$(openssl rand -base64 24) \
  --dry-run=client -o yaml >> /tmp/${APP_NAME}-db-creds.yaml

# Review passwords before encrypting (save them somewhere safe)
cat /tmp/${APP_NAME}-db-creds.yaml

# Move to databases directory
cp /tmp/${APP_NAME}-db-creds.yaml databases/staging/${APP_NAME}/secrets.yaml

# Encrypt
AGE_KEY=$(grep -A 2 "creation_rules:" clusters/staging/.sops.yaml | grep "age:" | awk '{print $NF}')
sops --age=${AGE_KEY} \
  --encrypt --encrypted-regex '^(data|stringData)$' \
  --in-place databases/staging/${APP_NAME}/secrets.yaml
```

### ${APP_NAME}-backup-s3-secret.yaml

```bash
# Create R2 backup credentials (plaintext)
kubectl create secret generic ${APP_NAME}-backup-s3-secret \
  --from-literal=ACCESS_KEY_ID=${R2_ACCESS_KEY_ID} \
  --from-literal=ACCESS_KEY_SECRET=${R2_ACCESS_KEY_SECRET} \
  --dry-run=client -o yaml > databases/staging/${APP_NAME}/${APP_NAME}-backup-s3-secret.yaml

# Encrypt
sops --age=${AGE_KEY} \
  --encrypt --encrypted-regex '^(data|stringData)$' \
  --in-place databases/staging/${APP_NAME}/${APP_NAME}-backup-s3-secret.yaml
```

### kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${APP_NAME}
resources:
  - secrets.yaml
  - postgresql-cluster.yaml
  - backup-config.yaml
  - ${APP_NAME}-backup-s3-secret.yaml
  - r2-backup-configmap.yaml

replacements:
  - source:
      kind: ConfigMap
      name: r2-backup-config
      fieldPath: data.endpointURL
    targets:
      - select:
          kind: Cluster
          name: ${APP_NAME}-postgres
        fieldPaths:
          - spec.backup.barmanObjectStore.endpointURL
  - source:
      kind: ConfigMap
      name: r2-backup-config
      fieldPath: data.destinationPath
    targets:
      - select:
          kind: Cluster
          name: ${APP_NAME}-postgres
        fieldPaths:
          - spec.backup.barmanObjectStore.destinationPath
```

### Register in databases/staging/kustomization.yaml

Add the new app to `databases/staging/kustomization.yaml`:

```yaml
resources:
  - linkding
  - n8n
  - ${APP_NAME}  # Add here
```

> **Note:** The CNPG cluster is deployed in the app's own namespace (`${APP_NAME}`), so the app's deployment can reach PostgreSQL at `${APP_NAME}-postgres-rw.${APP_NAME}.svc.cluster.local:5432`. Make sure to add the DB env vars in `apps/base/${APP_NAME}/deployment.yaml` (the commented template is in Step 2).

---

## Step 2.6 — Add NetworkPolicy for Namespace Isolation

Every new app namespace must include a `network-policy.yaml` in `apps/base/${APP_NAME}/`. This implements the cluster's default-deny security posture — established in Phase 10 — ensuring new apps don't create unintended cross-namespace communication paths.

Create `apps/base/${APP_NAME}/network-policy.yaml` using the appropriate template based on the app's access type and database requirements.

### Template A: Cloudflare Tunnel access, no database (most apps)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: ${APP_NAME}
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: ${APP_NAME}
spec:
  podSelector: {}
  ingress:
  - from:
    - podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring-scraping
  namespace: ${APP_NAME}
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
  policyTypes:
  - Ingress
```

### Template B: Add this policy if `USE_CNPG=yes` (database in same namespace)

Add this policy to the file after the 3 policies above:

```yaml
---
# Allow CNPG controller to manage the PostgreSQL cluster pods
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-cnpg-controller
  namespace: ${APP_NAME}
spec:
  podSelector:
    matchLabels:
      cnpg.io/podRole: instance
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: cnpg-system
  policyTypes:
  - Ingress
```

### Template C: Add this policy if `ACCESS_TYPE=internal` (Traefik Ingress)

Add this policy to the file after the 3 policies above:

```yaml
---
# Allow Traefik (kube-system) to forward requests to the app
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-traefik-ingress
  namespace: ${APP_NAME}
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          app.kubernetes.io/name: traefik
  policyTypes:
  - Ingress
```

### Register in kustomization.yaml

Add `network-policy.yaml` to the resources list in `apps/base/${APP_NAME}/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
  - network-policy.yaml  # ← add this
```

### Validate

```bash
kustomize build apps/base/${APP_NAME}/ | grep -c "NetworkPolicy"
# Expected: 3 (cloudflared), 4 (cloudflared+CNPG or Traefik), 5 (Traefik+CNPG — rare)
```

---

## Step 3 — Create Staging Overlay

Create environment-specific config in `apps/staging/${APP_NAME}/`. The contents depend on the access type chosen in Step 0.

```bash
mkdir -p apps/staging/${APP_NAME}
```

---

### Option A: Public access via Cloudflare Tunnel

#### kustomization.yaml
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${APP_NAME}
resources:
  - ../../base/${APP_NAME}/
  - cloudflare.yaml
  - cloudflare-secret.yaml
  - ${APP_NAME}-env-secret.yaml
# Add any ConfigMap or additional secrets here
```

### cloudflare.yaml (ConfigMap)

This ConfigMap contains the tunnel routing configuration:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloudflared
  namespace: ${APP_NAME}
data:
  config.yaml: |
    tunnel: ${TUNNEL_NAME}
    credentials-file: /etc/cloudflared/creds/credentials.json
    metrics: 0.0.0.0:2000
    no-autoupdate: true

    ingress:
    - hostname: ${APP_HOSTNAME}
      service: http://${APP_NAME}:${APP_PORT}
    - service: http_status:404
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: ${APP_NAME}
spec:
  selector:
    matchLabels:
      app: cloudflared
  replicas: 2
  template:
    metadata:
      labels:
        app: cloudflared
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: cloudflared
      containers:
      - name: cloudflared
        image: cloudflare/cloudflared:latest
        args:
        - tunnel
        - --config
        - /etc/cloudflared/config/config.yaml
        - run
        livenessProbe:
          httpGet:
            path: /ready
            port: 2000
          failureThreshold: 1
          initialDelaySeconds: 10
          periodSeconds: 10
        volumeMounts:
        - name: config
          mountPath: /etc/cloudflared/config
          readOnly: true
        - name: creds
          mountPath: /etc/cloudflared/creds
          readOnly: true
      volumes:
      - name: creds
        secret:
          secretName: tunnel-credentials
      - name: config
        configMap:
          name: cloudflared
          items:
          - key: config.yaml
            path: config.yaml
```

### cloudflare-secret.yaml (SOPS-encrypted)

Create the tunnel credentials secret. First, generate it in plaintext, then encrypt:

```bash
# Generate plaintext secret
kubectl create secret generic tunnel-credentials \
  --from-file=credentials.json=${TUNNEL_JSON} \
  --dry-run=client -o yaml > apps/staging/${APP_NAME}/cloudflare-secret.yaml
```

Then encrypt it with SOPS:

```bash
# Get the age public key from .sops.yaml
AGE_KEY=$(grep -A 2 "creation_rules:" clusters/staging/.sops.yaml | grep "age:" | awk '{print $NF}')

# Encrypt
sops --age=${AGE_KEY} \
  --encrypt --encrypted-regex '^(data|stringData)$' \
  --in-place apps/staging/${APP_NAME}/cloudflare-secret.yaml
```

**Verify the file is encrypted:** Open it and look for `ENC[AES256_GCM` in the data section.

### ${APP_NAME}-env-secret.yaml (SOPS-encrypted)

Create a secret for environment variables the app needs (admin credentials, API keys, etc.).

```bash
# First, create the secret in plaintext
kubectl create secret generic ${APP_NAME}-env-secret \
  --from-literal=ADMIN_USER=admin \
  --from-literal=ADMIN_PASSWORD=changeme \
  --dry-run=client -o yaml > apps/staging/${APP_NAME}/${APP_NAME}-env-secret.yaml
```

Replace the example with actual secrets the app needs. Then encrypt:

```bash
sops --age=${AGE_KEY} \
  --encrypt --encrypted-regex '^(data|stringData)$' \
  --in-place apps/staging/${APP_NAME}/${APP_NAME}-env-secret.yaml
```

### (Optional) ${APP_NAME}-config ConfigMap

If the app needs non-secret configuration (feature flags, log levels, etc.):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${APP_NAME}-config
  namespace: ${APP_NAME}
data:
  LOG_LEVEL: "info"
  FEATURE_X: "enabled"
```

Add this to the kustomization.yaml resources list.

---

### Option B: Internal access via Traefik Ingress *(skip if public)*

For apps only accessible on your local network. Much simpler — no tunnel, no Cloudflare credentials.

**⚠️ Important:** Always use cert-manager for TLS on Traefik Ingress. Include the annotation `cert-manager.io/cluster-issuer: letsencrypt-cloudflare-prod` in your Ingress manifest (shown below). This is the only way to provision TLS certificates for internal apps.

#### kustomization.yaml
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${APP_NAME}
resources:
  - ../../base/${APP_NAME}/
  - ingress.yaml
  - ${APP_NAME}-env-secret.yaml
# Add any ConfigMap or additional secrets here
```

#### ingress.yaml

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NAME}
  annotations:
    # cert-manager will automatically provision a TLS certificate
    cert-manager.io/cluster-issuer: letsencrypt-cloudflare-prod
    # Optional: Homepage dashboard integration
    # gethomepage.dev/enabled: "true"
    # gethomepage.dev/name: "${APP_DISPLAY_NAME}"
    # gethomepage.dev/description: "Short description"
    # gethomepage.dev/group: "HomeLab Services"
    # gethomepage.dev/icon: "icon-name.png"
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - ${APP_HOSTNAME}
      secretName: ${APP_NAME}-tls
  rules:
    - host: ${APP_HOSTNAME}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${APP_NAME}
                port:
                  number: ${APP_PORT}
```

> **Note:** cert-manager (`letsencrypt-cloudflare-prod` cluster issuer) is already deployed in this cluster — it will automatically provision and renew the TLS certificate. `${APP_HOSTNAME}` must resolve via local DNS / Pi-hole / `/etc/hosts`. No Cloudflare record or tunnel needed.

#### ${APP_NAME}-env-secret.yaml (SOPS-encrypted)

Same as the public path — create and encrypt any app secrets:

```bash
kubectl create secret generic ${APP_NAME}-env-secret \
  --from-literal=ADMIN_USER=admin \
  --from-literal=ADMIN_PASSWORD=changeme \
  --dry-run=client -o yaml > apps/staging/${APP_NAME}/${APP_NAME}-env-secret.yaml

sops --age=${AGE_KEY} \
  --encrypt --encrypted-regex '^(data|stringData)$' \
  --in-place apps/staging/${APP_NAME}/${APP_NAME}-env-secret.yaml
```

---

## Step 4 — Configure Cloudflare DNS (Manual, public access only — skip if internal)

The tunnel credentials must be paired with a DNS record in Cloudflare. This step is manual because it requires access to the Cloudflare console.

**Steps:**
1. Log in to Cloudflare dashboard
2. Navigate to your domain (watarystack.org)
3. Go to DNS → Records
4. Click "Add record"
5. Set:
   - **Type**: CNAME
   - **Name**: `${APP_HOSTNAME}` (just the subdomain, e.g., `myapp` for `myapp.watarystack.org`)
   - **Target**: `<TUNNEL_UUID>.cfargotunnel.com` (find TUNNEL_UUID in the tunnel credentials JSON file under `TunnelID`)
   - **Proxy status**: Proxied (orange cloud)
6. Click Save

The user must do this manually. Verify it's set up before deploying.

## Step 5 — Update Main Staging Kustomization

Edit `apps/staging/kustomization.yaml` to include the new app:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - linkding
  - mealie
  - audiobookshelf
  - homarr
  - ${APP_NAME}  # Add here
  - monitoring
  - infrastructure
```

Maintain alphabetical order if possible, for consistency.

## Step 6 — Test Manifests (Optional but Recommended)

Before committing, test the Kubernetes manifests:

```bash
# Validate without applying
kubectl apply -k apps/staging/${APP_NAME}/ --dry-run=client -o yaml

# Or build to see final output
kustomize build apps/staging/${APP_NAME}/

# Check for issues
kustomize build apps/staging/${APP_NAME}/ | kubectl apply --dry-run=client -f -
```

If there are validation errors, fix them before proceeding.

## Step 7 — Commit & Push

```bash
git add apps/
git add clusters/staging/kustomization.yaml  # if you modified it
git commit -m "feat: add ${APP_NAME} to homelab

- Create base deployment, service, namespace
- Add staging overlay with Cloudflare tunnel config
- SOPS-encrypt tunnel credentials and app secrets
- Wire into main staging kustomization"

git push origin feat/add-${APP_NAME}
```

## Step 8 — Open Pull Request

Use the GitHub CLI to open a PR:

```bash
gh pr create \
  --base main \
  --head feat/add-${APP_NAME} \
  --title "feat: add ${APP_NAME} to homelab" \
  --body "Adds ${APP_NAME} with the following:

- Image: ${APP_IMAGE}
- Port: ${APP_PORT}
- Hostname: ${APP_HOSTNAME}
- Tunnel: ${TUNNEL_NAME}
- Secrets: SOPS-encrypted and safe in Git

## Pre-merge checklist
- [ ] DNS CNAME record created in Cloudflare
- [ ] Manifests validated with dry-run
- [ ] Secrets are encrypted (check for ENC[AES256_GCM in files)
- [ ] Tunnel credentials JSON is in .gitignore (not committed)

Once merged, FluxCD will automatically deploy within 1 minute."
```

If `gh` is not available, print the PR URL:
```
https://github.com/santiagobermudezparra/HomeLab-Pro/compare/main...feat/add-${APP_NAME}
```

Tell the user to review and merge via the web UI.

## Step 9 — Monitor Deployment

Once the PR is merged, FluxCD will sync automatically (within 1 minute by default). The user can monitor:

```bash
# Watch FluxCD sync
flux get kustomizations

# View the new app's pods
kubectl get pods -n ${APP_NAME}

# Check logs
kubectl logs -f deployment/${APP_NAME} -n ${APP_NAME}

# Verify tunnel is running (public access only)
kubectl logs -f deployment/cloudflared -n ${APP_NAME}
```

If the pod doesn't start, check pod events and logs for errors (image pull failures, missing secrets, port conflicts).

## Step 10 — Add App to Homepage Dashboard (Optional but Recommended)

Once the app is running and stable, add it to the **Homepage** dashboard for quick access. This step is optional but recommended for visibility.

### Option A: Via Ingress Annotations (Internal/Traefik apps)

If your app uses Traefik Ingress (internal access), uncomment and update the annotations in your `apps/staging/${APP_NAME}/ingress.yaml`:

```yaml
annotations:
  cert-manager.io/cluster-issuer: letsencrypt-cloudflare-prod
  # Uncomment to add to Homepage dashboard
  gethomepage.dev/enabled: "true"
  gethomepage.dev/name: "${APP_DISPLAY_NAME}"
  gethomepage.dev/description: "Short description"
  gethomepage.dev/group: "HomeLab Services"
  gethomepage.dev/icon: "icon-name.png"  # e.g., "mdiApps", "mdiDatabase", etc.
```

Then re-apply the updated manifest:
```bash
git add apps/staging/${APP_NAME}/ingress.yaml
git commit -m "feat: add ${APP_NAME} to Homepage dashboard"
git push origin feat/add-${APP_NAME}
```

### Option B: Manual Homepage Configuration (Cloudflare Tunnel apps)

For apps with Cloudflare Tunnels (public access), add an entry to the **Homepage** app's configuration. Update `apps/base/homepage/config/services.yaml`:

```yaml
- HomeLab Services:
  - ${APP_DISPLAY_NAME}:
      href: https://${APP_HOSTNAME}
      description: "Short description"
      icon: "icon-name.png"
      widget:
        type: "iframe"  # or any Homepage widget type
```

Then commit and push:
```bash
git add apps/base/homepage/config/services.yaml
git commit -m "feat: add ${APP_NAME} link to Homepage"
git push origin feat/add-${APP_NAME}
```

**Note:** The exact step depends on your Homepage app setup. Check the deployed Homepage app's configuration files under `apps/base/homepage/` for the current structure.

---

## Checklist Summary

- [ ] User provided all required info (app name, port, image, hostname, **access type**)
- [ ] Created `apps/base/${APP_NAME}/` with namespace, deployment, service, kustomization
- [ ] Added `network-policy.yaml` to `apps/base/${APP_NAME}/` with appropriate policies (Template A + B if CNPG + C if Traefik)
- [ ] `kustomization.yaml` includes `network-policy.yaml` in resources list
- [ ] **Public:** Created `apps/staging/${APP_NAME}/` with cloudflare.yaml + encrypted secrets
- [ ] **Internal:** Created `apps/staging/${APP_NAME}/` with ingress.yaml + encrypted secrets
- [ ] **CloudNativePG (if `USE_CNPG=yes`):** Created `databases/staging/${APP_NAME}/` with cluster, backup, r2-configmap, encrypted secrets
- [ ] **CloudNativePG (if `USE_CNPG=yes`):** Updated `databases/staging/kustomization.yaml` with new app
- [ ] **CloudNativePG (if `USE_CNPG=yes`):** Added DB env vars to `apps/base/${APP_NAME}/deployment.yaml`
- [ ] Verified secrets are encrypted with SOPS (look for `ENC[AES256_GCM`)
- [ ] Updated `apps/staging/kustomization.yaml` with new app
- [ ] Tested manifests with `--dry-run=client`
- [ ] Committed to feature branch
- [ ] Pushed to origin
- [ ] Opened PR with `gh pr create`
- [ ] **Public only:** Reminded user to add DNS CNAME in Cloudflare before merging
- [ ] Monitor post-merge with `kubectl get pods -n ${APP_NAME}`

---

## Troubleshooting

### "Secret is not encrypted"
Check the file content. It should start with `ENC[AES256_GCM` in the `data` field. If it's readable, run:
```bash
sops --age=${AGE_KEY} --encrypt --encrypted-regex '^(data|stringData)$' --in-place <file>
```

### "kubectl: command not found"
Ensure kubectl is installed and kubeconfig is set up.

### "cloudflared: command not found"
Install cloudflared: `brew install cloudflare/cloudflare/cloudflared`

### "initContainer credentials never applied / login fails after deploy"

Two common causes:

**1. Wrong binary path in initContainer.**
The binary is not always at `/<appname>` — verify first:
```bash
kubectl exec deployment/${APP_NAME} -n ${APP_NAME} -- find / -name "${APP_NAME}" -type f 2>/dev/null
```
Use the real path (e.g. `/bin/filebrowser`, `/usr/local/bin/app`) in the initContainer command.

**2. Env vars leaking into the main container via Viper / env prefix.**
Some apps (e.g. filebrowser with `FB_` prefix, n8n with `N8N_`) use `AutomaticEnv` and pick up any env var matching their prefix as a config override. If you put credentials in `envFrom` on the main container, the app may interpret them as config values and corrupt or override auth.

**Rule:** only mount credential secrets in the initContainer. Remove `envFrom` / `env` referencing those secrets from the main container unless the app explicitly documents support for them.

**Recovery if this happens:**
```bash
# Scale down, delete the bad DB, scale back up to let initContainer re-run
kubectl scale deployment/${APP_NAME} -n ${APP_NAME} --replicas=0
kubectl delete pvc ${APP_NAME}-db -n ${APP_NAME}
kubectl scale deployment/${APP_NAME} -n ${APP_NAME} --replicas=1
kubectl logs deployment/${APP_NAME} -n ${APP_NAME} --all-containers
```

### "Pod won't start"
```bash
kubectl describe pod <pod-name> -n ${APP_NAME}  # See events
kubectl logs <pod-name> -n ${APP_NAME}          # See logs
```

Common issues: image doesn't exist, secret not found, port conflict, insufficient resources.

### "Tunnel not reaching the app"
- Verify CNAME record in Cloudflare DNS (should point to `<UUID>.cfargotunnel.com`)
- Check `cloudflared` pod logs: `kubectl logs -f deployment/cloudflared -n ${APP_NAME}`
- Verify service name matches in cloudflare.yaml: `service: http://${APP_NAME}:${APP_PORT}`
- Check app is actually listening on the port: `kubectl port-forward svc/${APP_NAME} ${APP_PORT}:${APP_PORT} -n ${APP_NAME}` then `curl localhost:${APP_PORT}`

### "FluxCD won't decrypt secret"
- Check age key in cluster: `kubectl get secret sops-age -n flux-system`
- Check FluxCD logs: `flux logs --namespace flux-system`
- Ensure secret was encrypted with the correct age key from `.sops.yaml`

---

## Architecture Notes

### Why Separate Tunnel Deployments?
Each app gets its own `cloudflared` deployment for:
- **Isolation**: If one tunnel config has issues, others aren't affected
- **Scaling**: Each app can scale independently
- **Monitoring**: Pod logs clearly show which tunnel is having issues

### Why SOPS Instead of Sealed Secrets?
- SOPS is simpler to set up and maintain
- Works well with GitOps (secrets stay in Git, encrypted)
- Age key is stored in `sops-age` secret in cluster (Flux can access it)
- No extra controllers needed

### Cloudflare Tunnel vs. Traefik Ingress

| | Cloudflare Tunnel (public) | Traefik Ingress (internal) |
|---|---|---|
| **Access** | Internet-accessible | LAN only |
| **DNS** | Cloudflare CNAME required | Local DNS / Pi-hole / hosts file |
| **Complexity** | Higher (tunnel + cloudflared pod) | Lower (just an Ingress resource) |
| **Security** | DDoS protection, zero-trust | Depends on your network |
| **Use when** | Sharing with others, remote access | Personal tools, admin UIs, dev tools |

**Rule of thumb:** if you need it outside your home network, use Cloudflare Tunnel. If it's only for you on your LAN, Traefik Ingress is simpler and keeps traffic off the internet entirely.

---

**Version**: 1.3
**Last Updated**: April 11, 2026
**Changelog:**
- v1.3: Enabled CNPG monitoring by default (`monitoring.enabled: true`, `podMonitorEnabled: true`) — Prometheus is active and scrapes CNPG clusters — Phase 09
- v1.2: Added CloudNativePG PostgreSQL support (Step 2.5) — full cluster + R2 backup matching linkding/n8n pattern
- v1.2: Added DB env vars template to deployment.yaml (commented, for CloudNativePG connection)
- v1.2: Skill now auto-detects whether to offer CloudNativePG based on app's PostgreSQL support
- v1.1: Added `nodeAffinity` (prefer worker nodes) to deployment template — Phase 08
- v1.1: Added `topologySpreadConstraints` to cloudflared deployment template — Phase 08
- v1.1: Added Longhorn `storage.yaml` section with `storageClassName: longhorn` — Phase 07
