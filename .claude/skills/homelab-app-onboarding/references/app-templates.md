# Common App Templates for HomeLab

Quick reference templates for deploying popular self-hosted applications. Copy and adapt as needed.

## Stateless Web Apps (No Database)

Apps like **paperless-ngx**, **stirling-pdf**, **homepage**, **dashboards**, etc.

**Key characteristics:**
- Listen on a single HTTP port
- No persistent data (or data stored externally)
- No special security requirements
- Simple env variables for config

**Minimal deployment.yaml:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: image:tag
        ports:
        - containerPort: 8080
        env:
        - name: PORT
          value: "8080"
        envFrom:
        - secretRef:
            name: myapp-env-secret
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

**Secrets needed:**
- Admin username/password
- API keys (if any)
- Configuration values that shouldn't be in ConfigMap

---

## Apps with PostgreSQL Database

Apps like **linkding**, **mealie**, **paperless**, etc.

**Deployment additions:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: image:tag
        ports:
        - containerPort: 8080
        env:
        - name: DB_HOST
          value: "myapp-postgres-rw.myapp.svc.cluster.local"  # CloudNativePG cluster
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          value: "myapp"
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: myapp-db-credentials
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: myapp-db-credentials
              key: password
        envFrom:
        - secretRef:
            name: myapp-env-secret
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
```

**Database Secret (myapp-db-credentials.yaml):**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: myapp-db-credentials
  namespace: myapp
type: Opaque
stringData:
  username: myapp_user
  password: CHANGE_ME_SECURE_PASSWORD
```

Then encrypt with SOPS.

**If using CloudNativePG cluster in this repo:**
The database cluster manifests go in `databases/staging/myapp/`. Reference the PostgreSQL module in the repo for examples.

---

## Apps with Persistent Volume (Data Storage)

Apps like **audiobookshelf** (stores files), **paperless** (documents), **vaultwarden** (vault), etc.

**Additional deployment section:**
```yaml
spec:
  template:
    spec:
      containers:
      - name: myapp
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: myapp-data-pvc
```

**PVC manifest (in base/):**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: myapp-data-pvc
  namespace: myapp
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path  # K3s default
  resources:
    requests:
      storage: 10Gi  # Adjust based on app needs
```

Add to `kustomization.yaml`:
```yaml
resources:
  - namespace.yaml
  - pvc.yaml       # Add this
  - deployment.yaml
  - service.yaml
```

---

## Multi-Replica Stateless App (HA)

For apps that can scale horizontally:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: myapp
spec:
  replicas: 3  # Multiple replicas
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      # Pod disruption budget for rolling updates
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - myapp
              topologyKey: kubernetes.io/hostname
      containers:
      - name: myapp
        image: image:tag
        # ... rest of container spec
```

---

## Apps with Init Container (Wait for Dependency)

For apps that need to wait for a database to be ready:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      initContainers:
      - name: wait-for-db
        image: postgres:16  # Or any image with pg_isready
        command:
          - sh
          - -c
          - |
            until pg_isready -h myapp-postgres-rw -p 5432 -u myapp; do
              echo "Waiting for database..."
              sleep 2
            done
            echo "Database is ready!"
        env:
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: myapp-db-credentials
              key: password
      containers:
      - name: myapp
        # ... rest of container spec
```

---

## Common Environment Variables Reference

### Database Connections
```yaml
DB_HOST: "myapp-postgres-rw.myapp.svc.cluster.local"
DB_PORT: "5432"
DB_NAME: "myapp"
DB_USER: "myapp_user"
DB_PASSWORD: "from-secret"
DATABASE_URL: "postgresql://user:pass@host:5432/db"  # Some apps use this format
```

### Logging
```yaml
LOG_LEVEL: "info"           # debug, info, warn, error
LOG_FORMAT: "json"          # json or text
```

### Admin/Auth
```yaml
ADMIN_USER: "admin"
ADMIN_PASSWORD: "from-secret"
SECRET_KEY: "from-secret"
JWT_SECRET: "from-secret"
```

### Performance/Limits
```yaml
WORKERS: "4"                # Number of worker processes
MAX_CONNECTIONS: "100"      # Database connections
CACHE_SIZE: "1Gi"
```

### URLs and Routing
```yaml
BASE_URL: "https://myapp.watarystack.org"
ALLOWED_HOSTS: "myapp.watarystack.org"
CORS_ORIGIN: "https://myapp.watarystack.org"
```

---

## Debugging Deployments

### Check if image exists
```bash
docker pull image:tag
# Or check Docker Hub/Quay.io registry directly
```

### Test manifest locally
```bash
kustomize build apps/staging/myapp/
kubectl apply -k apps/staging/myapp/ --dry-run=client -o yaml
```

### Inspect pod
```bash
kubectl describe pod -n myapp $(kubectl get pod -n myapp -o name | head -1)
kubectl logs -f deployment/myapp -n myapp
```

### Access app locally (port-forward)
```bash
kubectl port-forward svc/myapp 8080:8080 -n myapp
# Then visit http://localhost:8080
```

### Verify secrets mounted
```bash
kubectl get secret -n myapp
kubectl describe secret myapp-env-secret -n myapp
```

---

## Port Selection Guide

| Service | Port | Use Case |
|---------|------|----------|
| 80 | HTTP | Web apps (preferred for simplicity) |
| 8080 | HTTP (alt) | Java apps, Go microservices |
| 3000 | HTTP | Node.js apps |
| 5000 | HTTP | Python Flask apps |
| 9000 | HTTP | Some media servers, dashboards |
| 9090 | HTTP | Linkding, Grafana |
| 5432 | TCP | PostgreSQL |
| 6379 | TCP | Redis |
| 27017 | TCP | MongoDB |

Use whatever port the app's docs specify. You're routing through Cloudflare Tunnels, so the port doesn't need to be "special" or open.

---

## Internal Access via Traefik Ingress

For apps accessible only on your local network — no Cloudflare tunnel needed.

**ingress.yaml** (goes in `apps/staging/{APP_NAME}/`):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: myapp
spec:
  ingressClassName: traefik
  rules:
    - host: myapp.watarystack.org
      http:
        paths:
          - backend:
              service:
                name: myapp
                port:
                  number: 8080
            path: /
            pathType: Prefix
```

**staging kustomization.yaml** (no cloudflare entries):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: myapp
resources:
  - ../../base/myapp/
  - ingress.yaml
  - myapp-env-secret.yaml
```

**Key points:**
- `ingressClassName: traefik` — picks up K3s's built-in Traefik ingress controller automatically
- The hostname must resolve on your local network (Pi-hole, local DNS, or `/etc/hosts`)
- No `cloudflare.yaml`, no `cloudflare-secret.yaml`, no tunnel pod needed
- See `apps/staging/linkding/ingress.yaml` for a real example in this repo

---

## Common Pitfalls

1. **Image doesn't exist**: Verify image name and tag are correct
2. **Secrets not mounted**: Add `secretRef` to `envFrom`, not just `env`
3. **Database host wrong**: Use `<service-name>.<namespace>.svc.cluster.local` format
4. **Port mismatch**: Container port in `spec.containers[].ports.containerPort` must match app's actual port
5. **Secret not encrypted**: Look for `ENC[AES256_GCM` in the file after running sops
6. **Cloudflare CNAME missing**: Tunnel won't work until DNS record is added in Cloudflare console
7. **PVC not created**: Add PVC to base kustomization.yaml resources list

---

## Resource Requests/Limits Guide

Set realistic requests and limits based on app needs:

| App Type | Memory Request | Memory Limit | CPU Request | CPU Limit |
|----------|---|---|---|---|
| Simple web app | 256Mi | 512Mi | 100m | 500m |
| Medium app (Node, Python) | 512Mi | 1Gi | 250m | 1000m |
| Heavy app (Java, Go) | 1Gi | 2Gi | 500m | 2000m |
| Database | 2Gi | 4Gi | 1000m | 4000m |

**m = millicores (1000m = 1 CPU core)**

Start conservative and increase if pods are getting OOMKilled or throttled.
