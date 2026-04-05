# Phase 6: Install Longhorn Distributed Storage - Research

**Researched:** 2026-04-05
**Domain:** Longhorn distributed block storage on K3s via FluxCD GitOps
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| STOR-01 | Longhorn installed via FluxCD HelmRelease | Helm chart URL, version, HelmRepository, HelmRelease YAML patterns documented |
| STOR-02 | Longhorn is the default StorageClass (local-path demoted) | `persistence.defaultClass: true` + K3s `--disable=local-storage` mechanism documented |
| STOR-03 | Replication factor set to 2 | `persistence.defaultClassReplicaCount: 2` (StorageClass) + `defaultSettings.defaultReplicaCount: 2` (UI default) documented |
| STOR-06 | Longhorn UI accessible via Traefik Ingress (internal) | `longhorn-frontend` service port 80, Traefik ingress pattern confirmed |
| OBS-02 | Longhorn metrics scraped by Prometheus | `metrics.serviceMonitor.enabled: true` + `additionalLabels.release: kube-prometheus-stack` documented |
</phase_requirements>

---

## Summary

Longhorn 1.7.3 is the current stable release compatible with K3s v1.30.0. Installation via FluxCD follows the same `infrastructure/controllers/base/{app}/` pattern used by cert-manager and cloudnative-pg, with a HelmRepository, Namespace, and HelmRelease. Longhorn ships 22 CRDs so the HelmRelease must include `install.crds: Create` and `upgrade.crds: CreateReplace`.

**Critical pre-install dependency:** None of the three cluster nodes have `open-iscsi` or `nfs-common` installed. Longhorn requires `iscsid` running on every node. Longhorn provides an official iscsi-installer DaemonSet (`longhorn-iscsi-installation.yaml`) that installs and enables `open-iscsi` automatically on Ubuntu nodes — this must be applied before the HelmRelease reconciles.

**Storage availability constraint:** Worker-01 (`homelab-worker-01`) has only 16.7% disk available (39G/233G), which is below Longhorn's default 25% `storageMinimalAvailablePercentage` threshold. Longhorn will automatically mark worker-01 as unschedulable for storage. Replication factor 2 will run across **control-plane + worker-02** only, which is sufficient. No special override is needed for Phase 6.

**Primary recommendation:** Use Longhorn 1.7.3 with the infrastructure/controllers pattern. Deploy the iscsi-installer DaemonSet as a prerequisite. Demote `local-path` by adding `--disable=local-storage` to the K3s server config. Set `persistence.defaultClassReplicaCount: 2` and `defaultSettings.defaultReplicaCount: "2"` in HelmRelease values. Expose UI via Helm-managed ingress (`ingress.enabled: true`) targeting `longhorn-frontend:80`.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| longhorn/longhorn (Helm chart) | 1.7.3 | Distributed block storage | Current stable; K3s 1.30 compatible (`kubeVersion: >=1.21.0-0`) |
| HelmRepository URL | `https://charts.longhorn.io` | Helm chart source | Official Longhorn chart repository |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| longhorn-iscsi-installation DaemonSet | v1.7.3 tag | Pre-install open-iscsi on all nodes | Required — no nodes have open-iscsi |
| Traefik 2.10.7 (already installed) | 2.10.7 (kube-system) | Ingress for UI | Already running in cluster |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Helm ingress values | Separate `ingress.yaml` overlay | Helm-managed ingress is simpler for this pattern; separate file is more consistent with app pattern but adds a file |
| `--disable=local-storage` K3s flag | Kustomize patch on StorageClass | K3s re-applies local-path annotation on restart; flag is the only durable solution |

**Installation:**

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm show values longhorn/longhorn --version 1.7.3
```

**Version verification (confirmed 2026-04-05):**
```
longhorn/longhorn  1.7.3  v1.7.3
```

---

## Architecture Patterns

### Recommended Project Structure

```
infrastructure/controllers/
├── base/
│   └── longhorn/
│       ├── namespace.yaml          # longhorn-system namespace
│       ├── repository.yaml         # HelmRepository: charts.longhorn.io
│       ├── release.yaml            # HelmRelease with values
│       ├── iscsi-installer.yaml    # DaemonSet: open-iscsi prereq
│       └── kustomization.yaml      # references all above
└── staging/
    └── longhorn/
        └── kustomization.yaml      # references ../../base/longhorn/
```

Plus K3s config change:
```
/etc/rancher/k3s/config.yaml        # add: disable: [local-storage]
```

### Pattern 1: HelmRepository

```yaml
# infrastructure/controllers/base/longhorn/repository.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: longhorn
  namespace: longhorn-system
spec:
  interval: 24h
  url: https://charts.longhorn.io
```

### Pattern 2: HelmRelease with Critical Values

```yaml
# infrastructure/controllers/base/longhorn/release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: longhorn
  namespace: longhorn-system
spec:
  interval: 30m
  chart:
    spec:
      chart: longhorn
      version: "1.7.3"
      sourceRef:
        kind: HelmRepository
        name: longhorn
        namespace: longhorn-system
      interval: 12h
  install:
    crds: Create
  upgrade:
    crds: CreateReplace
  values:
    persistence:
      defaultClass: true            # Longhorn becomes default StorageClass
      defaultClassReplicaCount: 2   # StorageClass gets numberOfReplicas=2

    defaultSettings:
      defaultReplicaCount: "2"      # Longhorn UI default for new volumes

    ingress:
      enabled: true
      ingressClassName: traefik
      host: longhorn.watarystack.org

    metrics:
      serviceMonitor:
        enabled: true
        additionalLabels:
          release: kube-prometheus-stack  # matches Prometheus serviceMonitorSelector
```

**Why two replica settings:** `persistence.defaultClassReplicaCount` sets `numberOfReplicas` in the `longhorn` StorageClass (used by Kubernetes PVC provisioning). `defaultSettings.defaultReplicaCount` sets the default for volumes created directly through the Longhorn UI. Both must be set to ensure all paths create 2-replica volumes.

### Pattern 3: iscsi-Installer DaemonSet

```yaml
# infrastructure/controllers/base/longhorn/iscsi-installer.yaml
# Source: https://raw.githubusercontent.com/longhorn/longhorn/v1.7.3/deploy/prerequisite/longhorn-iscsi-installation.yaml
# Deploy BEFORE HelmRelease reconciles. DaemonSet installs open-iscsi and enables iscsid.
# Detects Ubuntu/Debian and runs: apt-get install -y open-iscsi && systemctl enable --now iscsid
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: longhorn-iscsi-installation
  namespace: longhorn-system
  annotations:
    command: &cmd apt-get install -y open-iscsi && systemctl enable iscsid && systemctl start iscsid && modprobe iscsi_tcp
spec:
  selector:
    matchLabels:
      app: longhorn-iscsi-installation
  template:
    metadata:
      labels:
        app: longhorn-iscsi-installation
    spec:
      hostNetwork: true
      hostPID: true
      initContainers:
        - name: iscsi-installation
          command:
            - nsenter
            - "--mount=/proc/1/ns/mnt"
            - "--"
            - bash
            - -c
            - *cmd
          image: alpine:3.17
          securityContext:
            privileged: true
      containers:
        - name: longhorn-iscsi-installation
          image: alpine:3.17
          command: ["/bin/sh", "-c", "while true; do sleep 86400; done"]
          securityContext:
            privileged: true
  updateStrategy:
    type: RollingUpdate
```

> Use the exact upstream YAML. Fetch from:
> `https://raw.githubusercontent.com/longhorn/longhorn/v1.7.3/deploy/prerequisite/longhorn-iscsi-installation.yaml`

### Pattern 4: Staging Overlay Kustomization

```yaml
# infrastructure/controllers/staging/longhorn/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: longhorn-system
resources:
  - ../../base/longhorn/
```

```yaml
# infrastructure/controllers/staging/kustomization.yaml  (UPDATED)
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - renovate
  - cert-manager
  - cloudnative-pg
  - longhorn          # add this line
```

### Pattern 5: K3s Config for local-path Demotion

```yaml
# /etc/rancher/k3s/config.yaml  (on control-plane node)
disable:
  - helm-controller
  - local-storage     # ADD THIS — prevents K3s from re-applying local-path as default
```

After editing, restart K3s:
```bash
sudo systemctl restart k3s
```

K3s will remove the local-path StorageClass on next startup. FluxCD then reconciles with Longhorn as the only default StorageClass.

**Why not kubectl patch:** K3s re-applies the `storageclass.kubernetes.io/is-default-class: "true"` annotation on local-path every time the k3s server starts. The only durable solution is `--disable=local-storage`. This is confirmed by K3s maintainer Brad Davidson in GitHub issue k3s-io/k3s#4083.

### Pattern 6: Traefik Ingress for Longhorn UI

The Longhorn UI is served by the `longhorn-frontend` service on port 80 in the `longhorn-system` namespace. Two options:

**Option A: Helm-managed ingress (recommended — simpler)**

Set in HelmRelease values (shown in Pattern 2 above):
```yaml
ingress:
  enabled: true
  ingressClassName: traefik
  host: longhorn.watarystack.org
```

This produces:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: longhorn-ingress
  namespace: longhorn-system
spec:
  ingressClassName: traefik
  rules:
  - host: longhorn.watarystack.org
    http:
      paths:
        - path: /
          pathType: ImplementationSpecific
          backend:
            service:
              name: longhorn-frontend
              port:
                number: 80
```

**Option B: Standalone ingress.yaml (consistent with linkding pattern)**

```yaml
# infrastructure/controllers/base/longhorn/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: longhorn-ui
  namespace: longhorn-system
spec:
  ingressClassName: traefik
  rules:
    - host: longhorn.watarystack.org
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: longhorn-frontend
                port:
                  number: 80
```

Option A is recommended for this phase since it reduces file count and keeps UI config co-located with the HelmRelease.

### Anti-Patterns to Avoid

- **Setting `defaultSettings.defaultReplicaCount` without `persistence.defaultClassReplicaCount`:** The UI default applies only to volumes created through the Longhorn UI. Kubernetes PVC provisioning uses the StorageClass `numberOfReplicas` parameter. Both must be set.
- **Using only `kubectl patch` to demote local-path:** K3s re-applies the default annotation on restart. Only `--disable=local-storage` in K3s config is durable.
- **Deploying HelmRelease before iscsi is installed:** Longhorn manager pods will start but volumes will fail to attach if `iscsid` is not running. Install iscsi-installer DaemonSet first, wait for it to complete on all nodes.
- **Enabling `v2DataEngine` on K3s without hugepages:** Longhorn v2 data engine requires hugepages. Not relevant for Phase 6 (v1 engine is the default).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| iscsi package installation on nodes | Custom init scripts | Longhorn iscsi-installer DaemonSet | Official upstream; handles Ubuntu/RHEL/SUSE detection, enables iscsid systemd service, loads kernel module |
| StorageClass replication config | Patch StorageClass object | `persistence.defaultClassReplicaCount: 2` in HelmRelease | Helm manages the StorageClass; patching separately creates drift |
| Prometheus scraping | Manual scrape config | `metrics.serviceMonitor.enabled: true` + `additionalLabels.release: kube-prometheus-stack` | ServiceMonitor is first-class supported; manual config is brittle |

**Key insight:** Longhorn provides all required integration points as Helm values. Hand-rolling iscsi installation or Prometheus config duplicates work the upstream chart already handles correctly.

---

## Runtime State Inventory

> Skipped — this is a greenfield installation phase. No rename/refactor/migration involved.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| K3s cluster | All | ✓ | v1.30.0+k3s1 | — |
| FluxCD | STOR-01 | ✓ | v2.5.1 | — |
| Traefik | STOR-06 | ✓ | 2.10.7 (kube-system) | — |
| kube-prometheus-stack | OBS-02 | ✓ | 66.2.2 | — |
| open-iscsi on nodes | STOR-01 | ✗ (none of 3 nodes) | — | Longhorn iscsi-installer DaemonSet |
| nfs-common on nodes | RWX volumes (not needed Phase 6) | ✗ | — | Not required for Phase 6 (no RWX) |
| Disk space (≥25% free) | STOR-03 (replication) | Partial | CP: 76%, W02: 88%, W01: 16.7% | Worker-01 excluded automatically by Longhorn |

**Missing dependencies with no fallback:**
- None that block Phase 6 execution.

**Missing dependencies with fallback:**
- `open-iscsi`: Required on all nodes. Longhorn iscsi-installer DaemonSet is the automated fallback — apply it as Wave 0 before HelmRelease.

---

## Common Pitfalls

### Pitfall 1: Worker-01 Disk Space (CRITICAL)

**What goes wrong:** Worker-01 has only 39G free (16.7% of 233G). Longhorn's default `storageMinimalAvailablePercentage` is 25%. Longhorn will automatically mark Worker-01's disk as `Schedulable: false` and exclude it from replica placement.

**Why it happens:** Worker-01 is at 83% capacity. The Longhorn threshold protects against disk exhaustion. This is correct behavior.

**How to avoid:** Accept the constraint for Phase 6. Replication factor 2 works fine across control-plane (76% free) + worker-02 (88% free). Worker-01 remains a compute node but stores no Longhorn replicas. Address disk usage on worker-01 in a separate task.

**Warning signs:** After installation, check Longhorn UI → Nodes. Worker-01 should show `Schedulable: false` (disk condition). This is expected, not an error.

### Pitfall 2: local-path StorageClass Re-Appearing as Default

**What goes wrong:** After `kubectl patch storageclass local-path` removes the default annotation, K3s re-applies `storageclass.kubernetes.io/is-default-class: "true"` on the next k3s server restart, leaving two default StorageClasses.

**Why it happens:** K3s bundles local-path as a built-in addon that it reconciles on every startup.

**How to avoid:** Add `local-storage` to the `disable:` list in `/etc/rancher/k3s/config.yaml` on the control-plane node and restart K3s. The StorageClass is then permanently removed.

**Warning signs:** After a node reboot, `kubectl get storageclass` shows `local-path (default)` alongside `longhorn (default)`.

### Pitfall 3: defaultSettings Not Applying via Helm

**What goes wrong:** `defaultSettings.defaultReplicaCount` set in HelmRelease values may not update the live Longhorn `settings` CR if the CR already exists from a previous install. (GitHub issue longhorn/longhorn#2562, reported 2021 — not definitively fixed).

**Why it happens:** Helm applies `defaultSettings` to the `longhorn-default-setting` ConfigMap. Longhorn Manager syncs ConfigMap → Settings CR only if the CR does not already exist. On a fresh install (Phase 6), this is not a concern.

**How to avoid:** For Phase 6 (fresh install), this pitfall does not apply. If ever reinstalling, delete Longhorn CRDs before redeploying.

**Warning signs:** Longhorn UI → Settings shows `Default Replica Count: 3` after deployment with `defaultSettings.defaultReplicaCount: "2"` set.

### Pitfall 4: Prometheus Not Scraping Longhorn Metrics

**What goes wrong:** ServiceMonitor is created but Prometheus does not pick up Longhorn targets.

**Why it happens:** Prometheus in this cluster uses `serviceMonitorSelector: {matchLabels: {release: kube-prometheus-stack}}`. The Longhorn ServiceMonitor must carry this label.

**How to avoid:** Set in HelmRelease values:
```yaml
metrics:
  serviceMonitor:
    enabled: true
    additionalLabels:
      release: kube-prometheus-stack
```
Confirmed via live cluster: `kubectl get prometheus kube-prometheus-stack-prometheus -n monitoring -o jsonpath='{.spec.serviceMonitorSelector}'` returns `{"matchLabels":{"release":"kube-prometheus-stack"}}`.

**Warning signs:** `kubectl get servicemonitor -n longhorn-system` shows the resource exists but Prometheus Targets UI shows no `longhorn` entries.

### Pitfall 5: multipathd Interfering with Longhorn Volumes

**What goes wrong:** If `multipathd` is running on nodes, it may claim iSCSI devices used by Longhorn, causing mount failures with `"already mounted or mount point busy"`.

**Why it happens:** `multipathd` creates multipath devices for any `/dev/sd*` device it discovers, including those managed by Longhorn.

**How to avoid:** Check `systemctl is-active multipathd` on all nodes. Currently **inactive** on Worker-01 (verified). If ever enabled, add to `/etc/multipath.conf`:
```
blacklist {
    devnode "^sd[a-z0-9]+"
}
```
Then `systemctl restart multipathd`.

**Warning signs:** Longhorn volumes stuck in `Attaching` state; pod events show `already mounted or mount point busy`.

---

## Code Examples

### Verified: ServiceMonitor label requirement

```bash
# Confirmed live on this cluster:
kubectl get prometheus kube-prometheus-stack-prometheus -n monitoring \
  -o jsonpath='{.spec.serviceMonitorSelector}'
# Output: {"matchLabels":{"release":"kube-prometheus-stack"}}

kubectl get prometheus kube-prometheus-stack-prometheus -n monitoring \
  -o jsonpath='{.spec.serviceMonitorNamespaceSelector}'
# Output: {}  (all namespaces, including longhorn-system)
```

Conclusion: ServiceMonitor in `longhorn-system` with label `release: kube-prometheus-stack` will be scraped. No additional namespace label required.

### Verified: StorageClass output from `helm template`

```bash
helm template longhorn longhorn/longhorn --version 1.7.3 \
  --set persistence.defaultClass=true \
  --set persistence.defaultClassReplicaCount=2 \
  --namespace longhorn-system | grep -A10 "kind: StorageClass"
```

Produces:
```yaml
kind: StorageClass
metadata:
  name: longhorn
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
parameters:
  numberOfReplicas: "2"
  staleReplicaTimeout: "2880"
  fromBackup: ""
provisioner: driver.longhorn.io
```

### Verified: Ingress template from Helm

```bash
helm template longhorn longhorn/longhorn --version 1.7.3 \
  --set ingress.enabled=true \
  --set ingress.ingressClassName=traefik \
  --set ingress.host=longhorn.watarystack.org \
  --namespace longhorn-system | grep -A20 "kind: Ingress"
```

Produces valid `networking.k8s.io/v1 Ingress` with `longhorn-frontend:80` backend.

### Verified: CRD count

```bash
helm template longhorn longhorn/longhorn --version 1.7.3 --namespace longhorn-system \
  | grep -c "kind: CustomResourceDefinition"
# Output: 22
```

Confirms `install.crds: Create` and `upgrade.crds: CreateReplace` are required.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual `helm install` | FluxCD HelmRelease with CRD handling | Longhorn 1.5+ | Declarative, GitOps-native |
| `helm.fluxcd.io/v1` HelmRelease | `helm.toolkit.fluxcd.io/v2` HelmRelease | FluxCD v2 | This cluster uses v2; pattern matches cert-manager |
| Separate ServiceMonitor YAML | `metrics.serviceMonitor.enabled: true` in Helm values | Longhorn 1.6.0 (issue #7041 closed) | No manual ServiceMonitor required |
| `defaultSettings` only for replica count | Both `persistence.defaultClassReplicaCount` AND `defaultSettings.defaultReplicaCount` | Always required | Missing one leaves either PVC or UI-created volumes at replica=3 |

**Deprecated/outdated:**
- `helm.fluxcd.io/v1` HelmRelease: Removed in FluxCD v2. This cluster uses `helm.toolkit.fluxcd.io/v2`.
- `enablePSP: true`: Only needed for Kubernetes < 1.25. Our cluster is 1.30 — omit entirely.
- KUBELET_ROOT_DIR override: Only needed for K3s < v0.10.0. Our K3s is v1.30.0 — omit.

---

## Open Questions

1. **Should the iscsi-installer DaemonSet remain permanent or be deleted after install?**
   - What we know: The DaemonSet is a "one-shot" installer. After open-iscsi is installed on all nodes, the DaemonSet serves no further purpose. It keeps a pause container running on every node.
   - What's unclear: Whether Longhorn documentation recommends keeping it for node additions or removing it.
   - Recommendation: Keep it in the Kustomization permanently. If new nodes are added to the cluster, the DaemonSet will automatically install open-iscsi on them. The resource cost (one tiny Alpine container per node) is negligible.

2. **Should Worker-01's storage be excluded explicitly or left to Longhorn's auto-exclusion?**
   - What we know: Longhorn will auto-mark Worker-01 as `Schedulable: false` due to <25% disk available.
   - What's unclear: Whether the planner should add a Wave for confirming this or just document it.
   - Recommendation: Document as an expected post-install verification step. No Helm value changes needed for Phase 6.

3. **Longhorn UI hostname: use `longhorn.watarystack.org` or LAN IP?**
   - What we know: The requirement says "internal access only via Traefik Ingress." Traefik ingress requires a hostname in its rules (not an IP). The pattern from linkding uses a subdomain of `watarystack.org`.
   - Recommendation: Use `longhorn.watarystack.org`. Requires a local DNS entry pointing to the Traefik LAN IP, or editing `/etc/hosts` on workstations that need access. No Cloudflare tunnel needed.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | kubectl + flux CLI (infrastructure validation — no unit test framework in this repo) |
| Config file | none |
| Quick run command | `kubectl get helmrelease longhorn -n longhorn-system` |
| Full suite command | See Phase Requirements → Test Map below |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| STOR-01 | HelmRelease reconciled successfully | smoke | `kubectl get helmrelease longhorn -n longhorn-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` → `True` | ❌ Wave 0 |
| STOR-01 | Longhorn pods running in longhorn-system | smoke | `kubectl get pods -n longhorn-system --field-selector=status.phase=Running --no-headers | wc -l` (expect ≥10) | ❌ Wave 0 |
| STOR-02 | Longhorn StorageClass is default | smoke | `kubectl get sc longhorn -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}'` → `true` | ❌ Wave 0 |
| STOR-02 | local-path is NOT default | smoke | `kubectl get sc local-path 2>/dev/null` → not found OR annotation is `false` | ❌ Wave 0 |
| STOR-03 | StorageClass has replicaCount=2 | smoke | `kubectl get sc longhorn -o jsonpath='{.parameters.numberOfReplicas}'` → `2` | ❌ Wave 0 |
| STOR-03 | Volume provisioned with 2 replicas | integration | Create test PVC, check Longhorn volume replica count in UI or via `kubectl get lhv -n longhorn-system` | ❌ Wave 0 |
| STOR-06 | Longhorn UI reachable via Traefik | smoke | `curl -s -o /dev/null -w "%{http_code}" http://longhorn.watarystack.org/` → `200` | ❌ Wave 0 |
| OBS-02 | ServiceMonitor exists with correct label | smoke | `kubectl get servicemonitor -n longhorn-system -o jsonpath='{.items[0].metadata.labels.release}'` → `kube-prometheus-stack` | ❌ Wave 0 |
| OBS-02 | Prometheus scrapes Longhorn targets | integration | Check Prometheus UI or `kubectl exec -n monitoring ... curl http://localhost:9090/api/v1/targets` for longhorn entries | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `kubectl get helmrelease longhorn -n longhorn-system`
- **Per wave merge:** All smoke tests in the table above
- **Phase gate:** All smoke + integration tests green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] No automated test scripts exist — all tests are manual `kubectl` commands documented in PLAN.md verify steps
- [ ] No test framework — this is infrastructure validation; `kubectl` commands are the appropriate "tests"

*(Existing infrastructure in this repo uses kubectl/flux verification commands, not unit test frameworks. This is intentional — Kubernetes manifests are validated by the API server and observed via operator status conditions.)*

---

## Project Constraints (from CLAUDE.md)

| Directive | Impact on Phase 6 |
|-----------|------------------|
| Use `infrastructure/controllers/base/{app}/` pattern | Longhorn base files go in `infrastructure/controllers/base/longhorn/` |
| Use `infrastructure/controllers/staging/{app}/` overlays | Staging kustomization references base |
| All secrets SOPS-encrypted | No secrets needed for Phase 6 (no backup target, no auth) |
| Never commit directly to main | Work on feature branch |
| Test with `kubectl apply -k ... --dry-run=client` before committing | Validate kustomization builds cleanly |
| FluxCD manages reconciliation | Do not manually apply HelmRelease in production |
| `helm.toolkit.fluxcd.io/v2` HelmRelease API | Matches existing cert-manager and cloudnative-pg pattern |

---

## Sources

### Primary (HIGH confidence)

- `helm show values longhorn/longhorn --version 1.7.3` — all Helm values documented here are verified from the chart directly
- `helm template longhorn longhorn/longhorn --version 1.7.3 ...` — ingress, StorageClass, ServiceMonitor, CRD count all verified from template output
- `kubectl get prometheus kube-prometheus-stack-prometheus -n monitoring -o jsonpath=...` — live cluster confirms `serviceMonitorSelector` and `serviceMonitorNamespaceSelector`
- `kubectl debug node/...` — live cluster confirms no open-iscsi on any node; disk usage verified per node
- `kubectl get storageclass` — live cluster: only `local-path (default)` exists pre-installation
- `/etc/rancher/k3s/config.yaml` — live cluster confirms `disable: [helm-controller]`; pattern for adding `local-storage`

### Secondary (MEDIUM confidence)

- [Longhorn Quick Install Docs](https://longhorn.io/docs/1.11.1/deploy/install/) — prerequisites list verified against chart template
- [Longhorn Helm Values Reference](https://longhorn.io/docs/1.7.2/references/helm-values/) — confirms `persistence.defaultClass`, `defaultSettings.defaultReplicaCount`, `metrics.serviceMonitor` structure
- [Longhorn CSI on K3s](https://longhorn.io/docs/1.10.1/advanced-resources/os-distro-specific/csi-on-k3s/) — confirms K3s 1.30 uses `/var/lib/kubelet` (no KUBELET_ROOT_DIR override needed)
- [Longhorn multipathd KB](https://longhorn.io/kb/troubleshooting-volume-with-multipath/) — exact `blacklist { devnode "^sd[a-z0-9]+" }` config

### Tertiary (LOW confidence — informational only)

- [K3s issue #4083](https://github.com/k3s-io/k3s/issues/4083) — K3s maintainer recommendation to use `--disable=local-storage`; consistent with observed K3s config.yaml pattern in this cluster
- [Longhorn GitHub issue #2562](https://github.com/longhorn/longhorn/issues/2562) — defaultSettings via Helm may not update existing Settings CR; fresh install is unaffected
- [Pi Cluster Longhorn docs](https://picluster.ricsanfre.com/docs/longhorn/) — community verification of FluxCD HelmRelease pattern

---

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — chart version verified from `helm search repo`, all values verified from `helm show values` and `helm template`
- Architecture: HIGH — patterns directly derived from existing repo patterns (cert-manager, cloudnative-pg, linkding ingress) with live cluster verification
- Pitfalls: HIGH (disk space, multipathd, local-path re-registration) / MEDIUM (defaultSettings Helm bug — affects reinstall not fresh install)
- Prerequisites: HIGH — live `kubectl debug node` confirms zero iscsi packages on all three nodes

**Research date:** 2026-04-05
**Valid until:** 2026-05-05 (Longhorn releases frequently; re-verify version before executing if >30 days)
