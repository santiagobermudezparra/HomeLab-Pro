# HomeLab-Pro 🏠🔧

A production-ready Kubernetes HomeLab built with GitOps principles, featuring automated deployments, monitoring, and secure external access.

### Devpod Instructions
```
.devcontainer
├── kubeconfig  # my K3s config file needed
└── setup.sh
└── .devcontainer.json
```

**After Setting my dotfiles**
- RUN : chmod +x .devcontainer/
- RUN : devpod up .
- RUN : bash .devcontainer/setup.sh

## 📋 Table of Contents

- [About Homelabs](#-about-homelabs)
- [Applications](#-applications)
- [Infrastructure](#️-infrastructure)
- [Architecture](#-architecture-details)
- [Deployment](#-deployment)
- [Security](#-security)
- [Monitoring](#-monitoring)
- [Operational Philosophy](#-operational-philosophy)
- [Maintenance](#-maintenance)

---

## 🏠 About Homelabs

A homelab is a personal infrastructure project that combines learning, privacy, and control. Unlike cloud services, homelabs let you:

- **Learn infrastructure patterns**: Kubernetes, GitOps, DNS, networking, storage, observability, and automation in a real environment
- **Own your data**: Personal photos, documents, and services stay on hardware you control — no cloud vendor lock-in
- **Experiment freely**: Test new tools, architectures, and configurations without affecting production workloads
- **Understand the full stack**: From hardware selection to container orchestration to monitoring

### Homelab Architecture Patterns

Homelabs vary widely by scope and goals:

| Pattern | Approach | Complexity | Best For |
|---------|----------|-----------|----------|
| **Monolithic** | Single powerful machine (NAS, MacBook) + Docker | Low | Small app collections, learning Docker |
| **Kubernetes Cluster** | Multi-node K3s or Talos, FluxCD GitOps | High | Scaling, HA, microservices patterns, production simulation |
| **Hybrid** | Mix of VMs (Proxmox), containers, bare metal | Medium | Diverse workload types, flexible resource allocation |

This project uses **Kubernetes + GitOps** — all cluster state lives in Git, and declarative configs drive deployments. Ideal for:
- Learning enterprise-grade patterns in a personal environment
- Version control and auditability of all changes
- Reproducible, disaster-recoverable infrastructure

### Network Segmentation & Security

Production homelabs separate concerns:
- **External access**: Zero-trust Cloudflare Tunnels (no open ports)
- **Internal access**: TLS via cert-manager and Let's Encrypt
- **DNS**: Network-wide filtering (PiHole) for ad-blocking and privacy
- **Storage tiers**: Fast (distributed like Longhorn) for live data, cold archival for backups

---

### Infrastructure Services

| Service | Description | Access | Status |
|---------|-------------|--------|--------|
| **Grafana** | Monitoring dashboards | `grafana.watarystack.org` | ✅ Active |
| **Prometheus** | Metrics collection | Internal only | ✅ Active |
| **AlertManager** | Alert management | Internal only | ✅ Active |
| **FluxCD** | GitOps controller | Internal only | ✅ Active |
| **Loki** | Log aggregation | Internal (via Grafana) | ✅ Active |
| **Gatus** | Status page | `status.watarystack.org` | ✅ Active |

## 🛠️ Infrastructure

### Core Components

- **Kubernetes Cluster**: K3s container orchestration on 3 nodes (1 control-plane + 2 workers)
- **FluxCD**: GitOps continuous deployment with declarative cluster state in Git
- **Kustomize**: Kubernetes native configuration management (no Helm, pure YAML)
- **SOPS**: Secret encryption and management with age key
- **cert-manager**: Automated TLS certificate generation and renewal
- **Traefik**: Ingress controller and load balancer for internal services
- **Cloudflare Tunnels**: Secure external access without port forwarding
- **Longhorn**: Distributed block storage with replica factor 2 (replaces local-path)

### Monitoring Stack

- **Prometheus**: Metrics collection from all nodes, pods, and services
- **Grafana**: Visualization, dashboards, and alerting
- **AlertManager**: Alert routing, deduplication, and notification
- **Fluent Bit**: DaemonSet log collector on every node
- **Loki**: Log aggregation backend, queryable from Grafana
- **kube-prometheus-stack**: Complete monitoring operator (Prometheus, Grafana, AlertManager, node-exporter)

---

## 🏛️ Architecture Details

### GitOps Workflow

```
📝 Git Commit → 🔄 FluxCD Sync (1min interval) → 🚀 Kubernetes Apply → 📊 Monitor
```

1. **Configuration Changes**: All changes made via Git commits (never direct `kubectl apply`)
2. **Automatic Sync**: FluxCD monitors repository and syncs every minute
3. **Kubernetes Deployment**: Kustomize builds final manifests, kubectl applies them
4. **Monitoring**: Prometheus tracks all metrics; Loki captures all logs; Grafana visualizes both

**Key principle**: If it's not in Git, it doesn't exist. This ensures reproducibility and enables disaster recovery.

### Directory Structure

```
HomeLab-Pro/
├── apps/                     # Application deployments
│   ├── base/                 # Base configurations (reusable across environments)
│   │   ├── audiobookshelf/
│   │   ├── linkding/
│   │   ├── mealie/
│   │   ├── n8n/
│   │   └── ...
│   └── staging/              # Environment-specific overlays
│       ├── audiobookshelf/   # Staging patches, secrets, tunnel config
│       ├── linkding/
│       └── ...
├── clusters/                 # Cluster configurations
│   └── staging/
│       ├── apps.yaml         # Reference to apps/ directory
│       ├── infrastructure.yaml
│       └── monitoring.yaml
├── infrastructure/           # Infrastructure components
│   ├── controllers/          # Operators (FluxCD, cert-manager, Longhorn, Traefik)
│   │   ├── base/
│   │   └── staging/
│   └── configs/              # ConfigMaps and static configs
├── monitoring/               # Monitoring stack
│   ├── controllers/          # kube-prometheus-stack, Loki
│   └── configs/              # PrometheusRules, dashboards, datasources
└── databases/                # Database clusters (CloudNativePG)
    └── staging/              # Backup configs, cluster manifests
```

### Network Architecture

#### External Access (Cloudflare Tunnels)
- **Security**: Zero-trust network — no open ports, no port forwarding
- **Performance**: Global CDN, DDoS protection, caching
- **Reliability**: Redundant tunnel replicas per app
- **Applications**: All user-facing apps (audiobookshelf, mealie, n8n, etc.)

#### Internal Access (Traefik + cert-manager)
- **Security**: TLS certificates from Let's Encrypt (DNS-01 challenge via Cloudflare)
- **Performance**: Direct cluster access, no external hops
- **Flexibility**: Multiple certificate sources (staging and production issuers)
- **Services**: Infrastructure components (Grafana, Prometheus, Longhorn UI, Headlamp)

#### Network-Wide DNS (PiHole)
- **Scope**: All devices on the network (phones, laptops, IoT devices)
- **Function**: Blocks ads and trackers at the DNS level before they load
- **Integration**: Deployed as K3s pod, promoted to network's primary DNS server
- **Benefit**: Privacy and reduced bandwidth for all network clients

---

## Homelab Operations Patterns

### Configuration Management (Base/Overlay)

Keep configurations DRY by separating shared from environment-specific:

- **Base** (`apps/base/app-name/`): Generic configs that work in any environment
  - Pod specs, resource requests/limits, security contexts
  - Service definitions, network policies
  - Kept simple, no secrets or environment-specific values

- **Staging Overlay** (`apps/staging/app-name/`): Environment-specific patches
  - SOPS-encrypted secrets (admin passwords, API keys, tunnel credentials)
  - Replicas, resource sizes, node affinity
  - Ingress/tunnel routing configuration

### Monitoring & Observability

Multi-layered approach ensures visibility without complexity:

- **Metrics**: Prometheus scrapes all components every 15s
- **Logs**: Fluent Bit collects from all nodes/pods → Loki
- **Status**: Gatus continuously probes all services and displays public status page
- **Dashboards**: Grafana shows metrics + logs side-by-side, with alerting rules

### Storage Resilience

- **Fast tier**: Longhorn distributed storage with replication factor 2 (survives 1 node failure)
- **Database tier**: CloudNativePG managed PostgreSQL with automated backups to Cloudflare R2
- **Full backup tier**: Velero scheduled backups of all namespaces + PVCs (future phase)

### Automation & Dependency Management

- **Renovate bot**: Automatically detects new container image versions and creates PRs
- **FluxCD**: Reconciles cluster state every 1 minute
- **cert-manager**: Renews certificates 30 days before expiration
- **Dependency ordering**: Explicit `dependsOn` chains ensure databases start before apps

---

## 🚀 Deployment

### Prerequisites

1. **Kubernetes Cluster**: K3s v1.30.0+ running on 2+ nodes
2. **FluxCD**: Installed in flux-system namespace
3. **SOPS + age**: Secret encryption tools and age key
4. **Cloudflare Account**: For Tunnels and DNS
5. **Domain**: Registered domain (e.g., watarystack.org)
6. **Git Repository**: Fork of this repo with GitHub write access

### Initial Setup

1. **Fork Repository**
   ```bash
   git clone https://github.com/santiagobermudezparra/HomeLab-Pro.git
   cd HomeLab-Pro
   ```

2. **Install FluxCD**
   ```bash
   flux bootstrap github \
     --owner=<your-github-username> \
     --repository=HomeLab-Pro \
     --branch=main \
     --path=./clusters/staging
   ```

3. **Configure SOPS**
   ```bash
   # Generate age key
   age-keygen -o age.agekey
   
   # Create Kubernetes secret
   kubectl create secret generic sops-age \
     --from-file=age.agekey=age.agekey \
     --namespace=flux-system
   ```

4. **Deploy Applications**
   ```bash
   # FluxCD will automatically deploy all components
   # Monitor deployment status
   flux get kustomizations
   ```

### Environment Configuration

#### Staging Environment
- **Purpose**: Testing and development of all features
- **Features**: All applications and monitoring
- **Security**: Staging TLS certificates and SOPS-encrypted secrets
- **Status**: Active

#### Production Environment (Future)
- **Purpose**: Production workloads with stricter SLAs
- **Features**: High availability, automated backups, multi-region support
- **Security**: Production certificates, hardened network policies
- **Status**: Planned

---

## 🔐 Security

### Secret Management

- **SOPS Encryption**: All secrets encrypted at rest in Git with age key
- **Age Encryption**: Modern cryptographic standard (not deprecated like PGP)
- **Git Security**: Only encrypted secrets committed; `*.agekey` in `.gitignore`
- **Kubernetes Secrets**: Decrypted in-cluster by FluxCD, never in plaintext in Git

**Principle**: Never commit unencrypted secrets. Audit all secrets before pushing.

### Certificate Management

- **Automated Renewal**: cert-manager handles all certificate lifecycle
- **Multiple Issuers**: Let's Encrypt staging (for testing) and production (for real TLS)
- **DNS Validation**: Cloudflare DNS-01 challenge for wildcard certificates
- **TLS Everywhere**: All internal services use HTTPS; external apps use Cloudflare Tunnel TLS

### Network Security

- **Zero Trust**: Cloudflare Tunnels require authentication; no public ingress
- **Internal TLS**: Traefik enforces TLS for all internal service-to-service communication
- **No Port Forwarding**: External access via secure tunnels only
- **NetworkPolicies**: Per-namespace isolation — each app can only reach its own database
- **Regular Updates**: Renovate bot automatically creates PRs for security patches

---

## 📊 Monitoring

### Metrics Collection

- **Application Metrics**: Custom metrics from app instrumentation
- **Infrastructure Metrics**: Kubernetes cluster health, node CPU/memory/disk
- **Storage Metrics**: Longhorn volume usage, replication status
- **Certificate Metrics**: Cert expiration tracking, renewal success/failure
- **Network Metrics**: Bandwidth usage, latency, error rates

### Dashboards

- **Grafana**: Central monitoring UI with Prometheus + Loki datasources
- **Cluster Overview**: Kubernetes API server health, node resource usage
- **Application Status**: Per-app memory, CPU, restart count, error rate
- **Storage Health**: Longhorn replica status, available space, I/O latency
- **Certificate Status**: Expiration dates, renewal history
- **Logs**: Fluent Bit → Loki → Grafana Explore (query logs from all pods)

### Alerting

- **PrometheusRules**: Automated alert generation based on thresholds
- **AlertManager**: Deduplicates and groups related alerts
- **Notification Channels**: Slack, email, PagerDuty (configurable)
- **Escalation Policies**: Critical alerts routed immediately; warnings batched hourly

### Status Page

- **Gatus**: Continuously probes all services (HTTP/TCP/DNS/Ping)
- **Public Dashboard**: Status updates posted to `status.watarystack.org`
- **Per-Service Details**: Uptime %, response time, error rate

---

## 🔧 Maintenance

### Regular Tasks

1. **Monitor Deployments**
   ```bash
   flux get kustomizations
   kubectl get pods --all-namespaces
   kubectl top nodes
   ```

2. **Update Dependencies**
   - Renovate bot automatically creates PRs for new image versions
   - Review changes and test in staging
   - Merge PRs to trigger FluxCD deployment

3. **Certificate Renewal**
   - cert-manager automatically renews 30 days before expiration
   - Monitor renewal success in Grafana or via `kubectl describe certificate`
   - Alerts fire if renewal fails

4. **Backup Verification**
   - Check database backups are completing: `kubectl get backup --all-namespaces`
   - Periodically test restore from backup (non-critical namespace first)
   - Monitor backup logs for errors

### Troubleshooting

#### FluxCD Sync Issues
```bash
flux get sources git
flux logs --all-namespaces
flux reconcile source git flux-system  # Force immediate sync
```

#### Certificate Issues
```bash
kubectl get certificates --all-namespaces
kubectl describe certificate <cert-name>
kubectl logs -n cert-manager deployment/cert-manager
```

#### Application Startup Issues
```bash
kubectl logs -f deployment/<app-name> -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl events -n <namespace>  # Show recent events
```

#### Secret Decryption Issues
```bash
kubectl get secret sops-age -n flux-system
flux logs --namespace flux-system | grep -i decrypt
sops -d apps/staging/<app>/*-secret.yaml  # Test decrypt locally
```

#### Longhorn Storage Issues
```bash
kubectl get volumesnapshotcontents  # All snapshots
kubectl describe pvc <pvc-name> -n <namespace>  # PVC details
kubectl logs -n longhorn-system -l app=longhorn-manager  # Manager logs
```

#### Workload Distribution
```bash
kubectl get pods -o wide --all-namespaces  # See which nodes pods are on
kubectl top nodes  # Node resource usage
kubectl describe node <node-name>  # Node details (allocatable resources)
```

### Performance Optimization

- **Resource Limits**: All apps have defined resource requests and limits
- **Horizontal Scaling**: topologySpreadConstraints and nodeAffinity distribute load
- **Storage Optimization**: Longhorn replication + Prometheus compression
- **Network Optimization**: Traefik load balancing and request routing
- **Observability**: Monitoring overhead (Prometheus, Fluent Bit) carefully tuned

---

## 🤝 Contributing

### Development Workflow

1. **Create Feature Branch**
   ```bash
   git checkout main && git pull origin main
   git checkout -b feature/new-feature
   ```

2. **Make Changes**
   - Edit manifests in `apps/`, `infrastructure/`, `monitoring/`, or `databases/`
   - If adding secrets: encrypt with `sops` before committing
   - Follow base/overlay pattern: base configs in `base/`, env-specific in `staging/`

3. **Test Deployment**
   ```bash
   # Validate Kubernetes manifests
   kubectl apply --dry-run=client -k apps/staging/new-app/
   
   # Check Kustomize output
   kustomize build apps/staging/new-app/
   ```

4. **Submit Pull Request**
   - Comprehensive description of changes
   - Link related issues
   - Wait for FluxCD validation (check for sync errors)

### Adding New Applications

**Use the HomeLab App Onboarding skill** (`.claude/skills/homelab-app-onboarding/`) to automate the full process, or follow these manual steps:

1. **Create Base Configuration** (`apps/base/new-app/`)
   - `namespace.yaml` — create app namespace
   - `deployment.yaml` — pod spec with image, resources, security context
   - `service.yaml` — expose port to cluster
   - `kustomization.yaml` — glue the above together

2. **Create Staging Overlay** (`apps/staging/new-app/`)
   - `kustomization.yaml` — patches from base
   - `cloudflare.yaml` (if external) — tunnel routing config
   - `cloudflare-secret.yaml` (if external) — tunnel credentials (SOPS-encrypted)
   - `new-app-secret.yaml` — app secrets (SOPS-encrypted)

3. **Encrypt Secrets with SOPS**
   ```bash
   sops --age $(grep age clusters/staging/.sops.yaml | awk '{print $NF}') \
     --encrypt --encrypted-regex '^(data|stringData)$' \
     --in-place apps/staging/new-app/*-secret.yaml
   ```

4. **Update Main Kustomization**
   ```yaml
   # apps/staging/kustomization.yaml
   resources:
     - audiobookshelf
     - linkding
     - mealie
     - new-app  # Add here
   ```

5. **Open Pull Request**
   ```bash
   git add apps/ databases/
   git commit -m "feat: add new-app to homelab"
   git push origin feature/new-feature
   gh pr create --title "feat: add new-app" --body "Adds new-app with external access via Cloudflare Tunnel."
   ```

---

## 📚 Documentation

### Additional Resources

- [FluxCD Documentation](https://fluxcd.io/docs/)
- [Kustomize Documentation](https://kustomize.io/)
- [SOPS Documentation](https://github.com/mozilla/sops)
- [K3s Documentation](https://docs.k3s.io/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Longhorn Documentation](https://longhorn.io/docs/)
- [Prometheus Operator](https://prometheus-operator.dev/)

### License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Last Updated**: April 12, 2026  
**Current Version**: v1 Hardening & Resilience Milestone  
**Cluster State**: 3 nodes (1 control-plane + 2 workers), Longhorn storage, 13 running services, GitOps-managed
