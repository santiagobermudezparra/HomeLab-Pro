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

- [Applications](#-applications)
- [Infrastructure](#️-infrastructure)
- [Architecture](#-architecture-details)
- [Deployment](#-deployment)
- [Security](#-security)
- [Monitoring](#-monitoring)
- [Access Methods](#-access-methods)
- [Maintenance](#-maintenance)




### Infrastructure Services

| Service | Description | Access | Status |
|---------|-------------|--------|--------|
| **Grafana** | Monitoring dashboards | `grafana.watarystack.org` | ✅ Active |
| **Prometheus** | Metrics collection | Internal only | ✅ Active |
| **AlertManager** | Alert management | Internal only | ✅ Active |
| **FluxCD** | GitOps controller | Internal only | ✅ Active |

## 🛠️ Infrastructure

### Core Components

- **Kubernetes Cluster**: Container orchestration platform
- **FluxCD**: GitOps continuous deployment
- **Kustomize**: Kubernetes native configuration management
- **SOPS**: Secret encryption and management
- **cert-manager**: Automated certificate management
- **Traefik**: Ingress controller and load balancer
- **Cloudflare Tunnels**: Secure external access

### Monitoring Stack

- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **AlertManager**: Alert routing and management
- **kube-prometheus-stack**: Complete monitoring solution

## 🏛️ Architecture Details

### GitOps Workflow

```
📝 Git Commit → 🔄 FluxCD Sync → 🚀 Kubernetes Apply → 📊 Monitor
```

1. **Configuration Changes**: All changes made via Git commits
2. **Automatic Sync**: FluxCD monitors repository every minute
3. **Kubernetes Deployment**: Resources automatically applied to cluster
4. **Monitoring**: Prometheus tracks all deployments and health

### Directory Structure

```
HomeLab-Pro/
├── apps/                     # Application deployments
│   ├── base/                 # Base configurations
│   │   ├── audiobookshelf/
│   │   ├── homarr/
│   │   ├── linkding/
│   │   └── mealie/
│   └── staging/              # Environment-specific overlays
│       ├── audiobookshelf/
│       ├── homarr/
│       ├── linkding/
│       └── mealie/
├── clusters/                 # Cluster configurations
│   └── staging/
│       ├── apps.yaml
│       ├── infrastructure.yaml
│       └── monitoring.yaml
├── infrastructure/           # Infrastructure components
│   ├── controllers/
│   │   ├── base/
│   │   └── staging/
│   └── configs/
└── monitoring/               # Monitoring stack
    ├── controllers/
    └── configs/
```

### Network Architecture

#### External Access (Cloudflare Tunnels)
- **Security**: Zero-trust network access
- **Performance**: Global CDN and DDoS protection
- **Reliability**: No port forwarding required
- **Applications**: All user-facing applications

#### Internal Access (Traefik + cert-manager)
- **Security**: TLS certificates from Let's Encrypt
- **Performance**: Direct cluster access
- **Flexibility**: Multiple certificate sources
- **Services**: Infrastructure and monitoring components

## 🚀 Deployment

### Prerequisites

1. **Kubernetes Cluster**: Running Kubernetes cluster
2. **FluxCD**: Installed and configured
3. **SOPS**: Age key for secret decryption
4. **Cloudflare**: Account with tunnels configured
5. **Domain**: Registered domain (watarystack.org)

### Initial Setup

1. **Fork Repository**
   ```bash
   git clone https://github.com/santiagobermudezparra/HomeLab-Pro.git
   cd HomeLab-Pro
   ```

2. **Install FluxCD**
   ```bash
   flux bootstrap github \
     --owner=santiagobermudezparra \
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
- **Purpose**: Testing and development
- **Features**: All applications and monitoring
- **Security**: Staging certificates and secrets

#### Production Environment (Future)
- **Purpose**: Production workloads
- **Features**: High availability and backup
- **Security**: Production certificates and hardened security

## 🔐 Security

### Secret Management

- **SOPS Encryption**: All secrets encrypted at rest
- **Age Encryption**: Modern cryptographic standard
- **Git Security**: Encrypted secrets in Git repository
- **Kubernetes Secrets**: Decrypted only in cluster

### Certificate Management

- **Automated Renewal**: cert-manager handles all certificates
- **Multiple Issuers**: Let's Encrypt staging and production
- **DNS Validation**: Cloudflare DNS-01 challenge
- **TLS Everywhere**: All services use HTTPS

### Network Security

- **Zero Trust**: Cloudflare tunnels require authentication
- **Internal TLS**: All inter-service communication encrypted
- **No Port Forwarding**: External access via secure tunnels only
- **Regular Updates**: Renovate bot manages dependency updates

## 📊 Monitoring

### Metrics Collection

- **Application Metrics**: Custom application metrics
- **Infrastructure Metrics**: Kubernetes cluster metrics
- **Security Metrics**: Certificate and security events
- **Performance Metrics**: Resource usage and performance

### Dashboards

- **Grafana**: Central monitoring dashboard
- **Cluster Overview**: Kubernetes cluster health
- **Application Status**: Application-specific metrics
- **Security Dashboard**: Certificate and security status

### Alerting

- **PrometheusRules**: Automated alert generation
- **AlertManager**: Alert routing and deduplication
- **Notification Channels**: Multiple alert channels
- **Escalation Policies**: Tiered alert escalation

### Administrative Access

```bash
# Kubernetes dashboard
kubectl proxy

# FluxCD UI
flux get all

## 🔧 Maintenance

### Regular Tasks

1. **Monitor Deployments**
   ```bash
   flux get kustomizations
   kubectl get pods --all-namespaces
   ```

2. **Update Dependencies**
   - Renovate bot automatically creates PRs
   - Review and merge dependency updates
   - Monitor deployment status

3. **Certificate Renewal**
   - cert-manager handles automatic renewal
   - Monitor certificate status in Grafana
   - Verify certificate expiration alerts

4. **Backup Management**
   ```bash
   # Application data backup
   kubectl get pvc --all-namespaces
   
   # Configuration backup (Git repository)
   git pull origin main
   ```

### Troubleshooting

#### Common Issues

1. **FluxCD Sync Issues**
   ```bash
   flux get sources git
   flux logs --all-namespaces
   ```

2. **Certificate Issues**
   ```bash
   kubectl get certificates --all-namespaces
   kubectl describe certificate <cert-name>
   ```

3. **Application Startup Issues**
   ```bash
   kubectl logs -f deployment/<app-name> -n <namespace>
   kubectl describe pod <pod-name> -n <namespace>
   ```

4. **Secret Decryption Issues**
   ```bash
   kubectl get secret sops-age -n flux-system
   flux logs --namespace flux-system
   ```

### Performance Optimization

- **Resource Limits**: All applications have defined resource limits
- **Horizontal Scaling**: Ready for horizontal pod autoscaling
- **Storage Optimization**: Persistent volumes for stateful applications
- **Network Optimization**: Traefik load balancing and routing

## 🤝 Contributing

### Development Workflow

1. **Create Feature Branch**
   ```bash
   git checkout -b feature/new-application
   ```

2. **Add Application Configuration**
   - Create base configuration in `apps/base/`
   - Add environment overlay in `apps/staging/`
   - Update kustomization files

3. **Test Deployment**
   ```bash
   # Validate Kubernetes manifests
   kubectl apply --dry-run=client -k apps/staging/new-app/
   
   # Test with FluxCD
   flux create kustomization test-app \
     --source=flux-system \
     --path="./apps/staging/new-app" \
     --prune=true
   ```

4. **Submit Pull Request**
   - Comprehensive description
   - Test results and screenshots
   - Documentation updates

### Adding New Applications

1. **Base Configuration** (`apps/base/new-app/`)
   - `namespace.yaml`
   - `deployment.yaml`
   - `service.yaml`
   - `kustomization.yaml`

2. **Environment Overlay** (`apps/staging/new-app/`)
   - Environment-specific configuration
   - Secrets and ConfigMaps
   - Ingress/tunnel configuration
   - `kustomization.yaml`

3. **Update Main Kustomization**
   ```yaml
   # apps/staging/kustomization.yaml
   resources:
     - linkding
     - mealie
     - audiobookshelf
     - homarr
     - new-app  # Add here
   ```

## 📚 Documentation

### Additional Resources

- [FluxCD Documentation](https://fluxcd.io/docs/)
- [Kustomize Documentation](https://kustomize.io/)
- [SOPS Documentation](https://github.com/mozilla/sops)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Cloudflare Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)

### License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---
