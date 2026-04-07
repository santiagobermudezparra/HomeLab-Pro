# Phase 9: Cilium CNI Migration - Research

**Researched:** 2026-04-07
**Domain:** Kubernetes CNI migration (Flannel → Cilium), K3s node configuration, Hubble observability, FluxCD HelmRelease
**Confidence:** HIGH (official Cilium docs + helm chart inspection + live cluster probing)

---

## Summary

Phase 9 is the highest-risk phase in the roadmap: it replaces the cluster's active CNI (Flannel, embedded in K3s) with Cilium, requiring node-level K3s config changes and a full pod restart across all three nodes. The cluster will have no functional CNI — and thus no inter-pod networking — for a brief maintenance window between disabling Flannel and Cilium becoming ready. All apps will experience a restart.

The migration requires only a single config change on the **control-plane** (`/etc/rancher/k3s/config.yaml`). Worker nodes inherit the `flannel-backend` setting from the server automatically; they need no config.yaml change. Kube-proxy is not an explicit pod in K3s — it runs as an embedded iptables manager — and disabling it via `disable-kube-proxy: true` is optional for this phase. The recommendation below keeps kube-proxy initially (omits `disable-kube-proxy`) to reduce blast radius; full kube-proxy replacement can be added in a follow-on phase.

Cilium 1.16.19 is the recommended pinned version. It supports Kubernetes 1.30 (K3s v1.30.0+k3s1) and is stable LTS. The Hubble UI service (`hubble-ui`) exposes port 80 inside the cluster and lives in `kube-system`, allowing a standard Traefik Ingress pointing to port 80 — matching the Longhorn UI ingress pattern exactly.

**Primary recommendation:** One-time maintenance window. Edit control-plane K3s config, restart K3s on all three nodes, install Cilium via `helm install` (bootstrapped manually, then committed to FluxCD for ongoing management), delete the `flannel.1` interface, and bounce all pods.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SEC-01 | Cilium is installed as the CNI, replacing Flannel | Helm install procedure + K3s config changes documented below |
| SEC-02 | Hubble observability is enabled in Cilium | Hubble helm values and Traefik Ingress for UI documented below |
</phase_requirements>

---

## Project Constraints (from CLAUDE.md)

- **FluxCD GitOps**: All changes go through Git → PR → FluxCD sync. Exception: the initial Cilium install must be done via `helm install` before FluxCD can manage it (chicken-and-egg: FluxCD needs a CNI to function). Subsequent upgrades managed by FluxCD HelmRelease.
- **SOPS encryption**: All secrets encrypted before commit. Cilium requires no secrets for basic operation (no tunnel credentials, etc.).
- **Branch workflow**: `feat/phase-9-cilium-cni-migration` off main — never commit directly to main.
- **No breaking changes**: Brief maintenance window is unavoidable; all pods restart once. This is acceptable per phase design.
- **K3s compatibility**: All changes must be compatible with k3s v1.30.0+k3s1.
- **cert-manager annotation**: Traefik Ingresses for internal services must include `cert-manager.io/cluster-issuer: letsencrypt-cloudflare-prod`.
- **Homepage dashboard**: Hubble UI should be added to the homepage configuration after deployment.

---

## Live Cluster Facts (Verified)

| Property | Value |
|----------|-------|
| K3s version | v1.30.0+k3s1 (all 3 nodes) |
| Current CNI | Flannel (vxlan backend, embedded in K3s) |
| Pod CIDR | 10.42.0.0/16 (per-node /24s: .0, .3, .1) |
| Service CIDR | 10.43.0.0/16 (inferred from clusterDNS: 10.43.0.10) |
| Kubernetes service IP | 10.43.0.1 (default K3s) |
| BPF filesystem | Mounted at `/sys/fs/bpf` (required for Cilium eBPF — verified present) |
| Kernel version | 6.17.0-19-generic on control-plane (well above Cilium minimum of 4.19) |
| Existing NetworkPolicies | 3 in `flux-system` namespace (allow-egress, allow-scraping, allow-webhooks) |
| Control-plane IP | 192.168.1.115 |
| Worker-01 IP | 192.168.1.89 |
| Worker-02 IP | 192.168.1.67 |
| K3s API server port | 6443 |
| K3s config path | `/etc/rancher/k3s/config.yaml` (control-plane) |
| Current K3s disabled components | `helm-controller`, `local-storage` |
| HelmRelease count | 4 (cert-manager, cloudnative-pg, kube-prometheus-stack, longhorn) |
| FluxCD version | v2.5.1 |
| Cilium CLI installed | No (needs installation) |
| Hubble CLI installed | No (needs installation) |

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| cilium/cilium (helm) | **1.16.19** | Cilium CNI, NetworkPolicy engine, kube-proxy complement | Supports K8s 1.30; LTS minor version; verified compatible with K3s 1.30 |
| Hubble relay | bundled in 1.16.19 | gRPC flow exporter | Ships with Cilium chart, enabled via values |
| Hubble UI | bundled in 1.16.19 | Web flow visualization | Ships with Cilium chart, enabled via values |
| cilium CLI | latest (v0.19.2+) | `cilium status` / `cilium connectivity test` | Required for verification |

### Helm Repository

```
URL: https://helm.cilium.io/
Chart: cilium/cilium
Pinned version: 1.16.19
```

Version verified via `helm search repo cilium/cilium --versions` on 2026-04-07. Latest 1.16.x is 1.16.19. Latest 1.17.x is 1.17.14 (avoid — less battle-tested on K3s; stick with 1.16 LTS for this migration).

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Cilium 1.16 | Cilium 1.17 | 1.17 is newer but 1.16 is the LTS; 1.16 has more community K3s migration reports |
| Keep kube-proxy (this phase) | Full kube-proxy replacement now | Removing kube-proxy adds another blast radius; do in a follow-on phase |
| Traefik Ingress for Hubble UI | NodePort service | Consistent with Longhorn UI pattern; already established |

**Installation (bootstrap — manual, pre-FluxCD):**
```bash
helm repo add cilium https://helm.cilium.io/
helm repo update
helm install cilium cilium/cilium \
  --version 1.16.19 \
  --namespace kube-system \
  -f /tmp/cilium-values.yaml
```

---

## Architecture Patterns

### Recommended File Structure

Cilium goes in `infrastructure/controllers/` following the exact same pattern as Longhorn:

```
infrastructure/
└── controllers/
    ├── base/
    │   ├── kustomization.yaml          # ADD: cilium entry
    │   └── cilium/
    │       ├── namespace.yaml          # kube-system (already exists; namespace.yaml just declares it)
    │       ├── repository.yaml         # HelmRepository: cilium, https://helm.cilium.io/
    │       ├── release.yaml            # HelmRelease: cilium in kube-system
    │       └── kustomization.yaml      # references above files
    └── staging/
        ├── kustomization.yaml          # ADD: cilium entry
        └── cilium/
            ├── ingress.yaml            # Traefik Ingress for Hubble UI
            └── kustomization.yaml      # references base/cilium/ + ingress.yaml
```

**Note on namespace.yaml**: Cilium installs into `kube-system` (already exists). The `namespace.yaml` can be a minimal document declaring `kube-system` or omitted — the chart handles it. Follow the Longhorn pattern: include it for explicitness.

### Pattern 1: Bootstrap-Then-GitOps

**What:** Cilium cannot be installed via FluxCD on first run — FluxCD itself needs a CNI to operate. Initial install is imperative (`helm install`). After Cilium is up, commit the HelmRelease to git and let FluxCD adopt it.

**How FluxCD adopts existing helm releases:** FluxCD will reconcile an existing Helm release if the HelmRelease name and namespace match what was installed imperatively. No special `--adopt-existing-resources` flag needed for this use case — FluxCD will detect the existing release on its next sync.

**When to use:** Any CNI migration on an existing FluxCD cluster.

### Pattern 2: HelmRepository + HelmRelease in kube-system

```yaml
# infrastructure/controllers/base/cilium/repository.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: cilium
  namespace: flux-system
spec:
  interval: 24h
  url: https://helm.cilium.io/
```

```yaml
# infrastructure/controllers/base/cilium/release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: cilium
  namespace: kube-system
spec:
  interval: 30m
  chart:
    spec:
      chart: cilium
      version: "1.16.19"
      sourceRef:
        kind: HelmRepository
        name: cilium
        namespace: flux-system
      interval: 12h
  install:
    crds: Create
  upgrade:
    crds: CreateReplace
  values:
    # K3s-specific: tell Cilium where the API server is
    # K3s proxies the API server on 127.0.0.1:6444 on all nodes
    k8sServiceHost: "127.0.0.1"
    k8sServicePort: "6444"

    # Match K3s default pod CIDR
    ipam:
      operator:
        clusterPoolIPv4PodCIDRList:
          - "10.42.0.0/16"

    # Operator: default 2 replicas is fine for 3-node cluster
    operator:
      replicas: 1   # Set to 1 for homelab; 2 for HA (optional)

    # Hubble observability
    hubble:
      enabled: true
      relay:
        enabled: true
      ui:
        enabled: true
      metrics:
        enabled:
          - dns:query;ignoreAAAA
          - drop
          - tcp
          - flow
          - icmp
          - http
        serviceMonitor:
          enabled: true
          labels:
            release: kube-prometheus-stack
```

**Note on k8sServiceHost:** K3s runs a local API proxy on `127.0.0.1:6444` on all nodes (including workers). This is K3s-specific and is the recommended value for K3s+Cilium. Alternative: use control-plane IP `192.168.1.115` and port `6443` — both work; 127.0.0.1:6444 is preferred for K3s homelab setups.

### Pattern 3: Hubble UI Traefik Ingress

Hubble UI service is in `kube-system`, named `hubble-ui`, port 80.

```yaml
# infrastructure/controllers/staging/cilium/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hubble-ui
  namespace: kube-system
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-cloudflare-prod
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - hubble.watarystack.org
      secretName: hubble-ui-tls
  rules:
    - host: hubble.watarystack.org
      http:
        paths:
          - backend:
              service:
                name: hubble-ui
                port:
                  number: 80
            path: /
            pathType: Prefix
```

This is the exact same pattern as Longhorn's `ingress.yaml` — just different service name and host. No TLS annotation is needed on the Cilium HelmRelease values because Traefik + cert-manager handles TLS termination externally.

### Anti-Patterns to Avoid

- **Installing Cilium via FluxCD on a cluster with no CNI**: FluxCD pods can't communicate — HelmRelease will never reconcile. Always bootstrap with `helm install` first.
- **Skipping `flannel.1` interface deletion**: Cilium cannot create its vxlan interface if `flannel.1` still exists on any node. Confirmed as a hard failure mode.
- **Setting `flannel-backend: none` on worker node config.yaml**: Flannel backend is a server-side setting propagated to agents. Workers inherit it automatically. No agent-side config change needed.
- **Enabling `disable-kube-proxy` in this phase**: K3s does not run kube-proxy as a pod — it's embedded. Disabling it changes iptables behavior and is best done as a separate change after Cilium is stable.
- **Using `kubeProxyReplacement: true` without `disable-kube-proxy` on K3s**: This combination can cause duplicate service rules and connectivity issues. If kube-proxy replacement is desired later, disable kube-proxy in K3s config first.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CNI networking | Custom iptables rules | Cilium (eBPF) | Kernel-level routing with NetworkPolicy support |
| Flow visibility | Custom packet capture | Hubble (built into Cilium) | Real-time L3-L7 flow export with UI |
| NetworkPolicy engine | Custom admission webhook | Cilium's built-in engine | Full K8s NetworkPolicy API + CiliumNetworkPolicy extension |
| Certificate for Hubble | Manual TLS | cert-manager via existing Traefik Ingress annotation | Already proven pattern for Longhorn |

---

## Migration Procedure

This is the most critical section. The migration requires a **maintenance window** — all pods will lose and regain networking.

### Pre-Migration Checklist

- [ ] Branch created from main: `feat/phase-9-cilium-cni-migration`
- [ ] cilium CLI installed on control-plane
- [ ] All current apps verified Running (snapshot baseline)
- [ ] Longhorn volumes: verify all healthy before starting (Longhorn uses node-level storage; CNI outage should not corrupt volumes but verify)
- [ ] Note current pod-to-pod connectivity (e.g., CNPG replicas reachable)

### Step 1: Update K3s Control-Plane Config (control-plane only)

SSH to control-plane (run locally since it's the dev machine):

```bash
# Edit /etc/rancher/k3s/config.yaml
# ADD these two lines:
flannel-backend: none
disable-network-policy: true
```

Full resulting file:
```yaml
disable:
  - helm-controller
  - local-storage
flannel-backend: none
disable-network-policy: true
```

**Workers do NOT need config changes** — flannel-backend is propagated server-side (verified via K3s GitHub discussion #3498).

### Step 2: Restart K3s on All Nodes (rolling, start with control-plane)

```bash
# Control-plane (local):
sudo systemctl restart k3s

# Worker-01 (via SSH):
ssh homelab-worker1@192.168.1.89 "sudo systemctl restart k3s-agent"

# Worker-02 (via SSH):
ssh homelab-worker2@192.168.1.67 "sudo systemctl restart k3s-agent"
```

**After this step:** Nodes will be in `NotReady` state — no CNI. Pod networking is broken. This is expected.

```bash
kubectl get nodes  # Expect NotReady
```

### Step 3: Remove the Flannel Network Interface (control-plane)

```bash
ip link delete flannel.1
```

**This is mandatory.** If `flannel.1` exists, Cilium cannot create its vxlan interface and will fail to start. Run on the control-plane. Worker nodes' flannel.1 interfaces will be cleaned up when K3s-agent restarts without flannel.

### Step 4: Install Cilium via Helm (bootstrap)

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium \
  --version 1.16.19 \
  --namespace kube-system \
  --set k8sServiceHost=127.0.0.1 \
  --set k8sServicePort=6444 \
  --set ipam.operator.clusterPoolIPv4PodCIDRList="{10.42.0.0/16}" \
  --set operator.replicas=1 \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true
```

Wait for Cilium to be ready:
```bash
kubectl rollout status daemonset/cilium -n kube-system
kubectl rollout status deployment/cilium-operator -n kube-system
```

### Step 5: Verify Nodes Become Ready

```bash
kubectl get nodes  # All 3 should return to Ready within ~2 minutes
cilium status       # (after cilium CLI install) — should show all nodes green
```

### Step 6: Restart All Pods to Use Cilium Networking

Pods created under Flannel have stale network namespaces. They must be restarted:

```bash
# Rolling restart by resource type (preserves uptime where possible):
kubectl get deployments --all-namespaces -o json | \
  jq -r '.items[] | .metadata.namespace + " " + .metadata.name' | \
  xargs -n2 kubectl rollout restart deployment -n

kubectl get statefulsets --all-namespaces -o json | \
  jq -r '.items[] | .metadata.namespace + " " + .metadata.name' | \
  xargs -n2 kubectl rollout restart statefulset -n

kubectl get daemonsets --all-namespaces -o json | \
  jq -r '.items[] | .metadata.namespace + " " + .metadata.name' | \
  xargs -n2 kubectl rollout restart daemonset -n
```

Or, if downtime is acceptable (faster):
```bash
kubectl delete pod --all --all-namespaces
```

### Step 7: Commit HelmRelease to Git (FluxCD adoption)

After Cilium is confirmed working, create the HelmRelease YAML as shown in Architecture Patterns above and commit to git. FluxCD will detect the existing release and adopt it.

---

## Rollback Strategy

**If migration fails during Step 4 (before Cilium is healthy):**

1. Uninstall Cilium: `helm uninstall cilium -n kube-system`
2. Remove Cilium interfaces on each node:
   ```bash
   ip link delete cilium_host 2>/dev/null || true
   ip link delete cilium_net 2>/dev/null || true
   ip link delete cilium_vxlan 2>/dev/null || true
   ```
3. Remove Cilium iptables rules:
   ```bash
   iptables-save | grep -iv cilium | iptables-restore
   ```
4. Edit `/etc/rancher/k3s/config.yaml` — remove `flannel-backend: none` and `disable-network-policy: true`
5. Restart K3s: `sudo systemctl restart k3s` (workers: `sudo systemctl restart k3s-agent`)
6. Wait for Flannel to re-initialize, restart pods

**No official K3s support for CNI migration rollback** — this is a manual procedure. The procedure above is synthesized from Cilium docs cleanup steps and K3s community guides.

---

## Common Pitfalls

### Pitfall 1: `flannel.1` Interface Not Deleted
**What goes wrong:** Cilium DaemonSet pods crash with error about being unable to create vxlan interface.
**Why it happens:** Flannel's vxlan interface persists after K3s restart with `flannel-backend: none`. Cilium tries to create its own vxlan tunnel and collides.
**How to avoid:** Always run `ip link delete flannel.1` on the control-plane before `helm install cilium`. Worker nodes clean up on k3s-agent restart.
**Warning signs:** `kubectl logs -n kube-system -l k8s-app=cilium` shows vxlan creation error.

### Pitfall 2: Nodes Stuck in `NotReady` After K3s Restart
**What goes wrong:** After restarting K3s with `flannel-backend: none`, nodes stay NotReady because no CNI is installed yet.
**Why it happens:** This is expected behavior — it's not a bug. The window between K3s restart and Cilium ready is by design.
**How to avoid:** Proceed immediately to Step 4 after node restarts. Do not wait or try to debug.
**Warning signs:** `kubectl get nodes` shows NotReady — this is correct during migration.

### Pitfall 3: FluxCD Controllers Crash After Cilium Install (Legacy K3s Network Policy Conflict)
**What goes wrong:** FluxCD pods enter CrashloopBackoff. Health/readiness probes fail.
**Why it happens:** K3s's built-in network policy controller (now disabled by `disable-network-policy: true`) previously injected iptables rules. With Cilium running without `disable-network-policy`, the two network policy controllers conflict.
**How to avoid:** The `disable-network-policy: true` flag in K3s config (Step 1) prevents this. This is why the flag is mandatory — confirmed by FluxCD GitHub issue #1450.
**Warning signs:** FluxCD pods CrashloopBackoff after Cilium is installed.

### Pitfall 4: Pods Not Restarted After CNI Swap
**What goes wrong:** Apps appear Running but Cloudflare Tunnels fail — existing pod network namespaces reference the old Flannel veth pairs.
**Why it happens:** Pods created under Flannel have stale network namespace configurations. Cilium takes over new pod creation but existing pods keep their old config.
**How to avoid:** Step 6 — restart all pods after Cilium is confirmed Ready.
**Warning signs:** Old pods show Running but cannot reach other pods; `hubble observe` shows drops.

### Pitfall 5: Worker Nodes Config.yaml Misconfigured
**What goes wrong:** Worker nodes still try to use Flannel after control-plane restart.
**Why it happens:** Misunderstanding that `flannel-backend: none` must be set on workers too.
**How to avoid:** `flannel-backend` is server-side only. Never add it to agent/worker `config.yaml`. Workers inherit it from the server (K3s discussion #3498 confirmed).

### Pitfall 6: Cilium Operator Replicas Too High
**What goes wrong:** Cilium operator pods fail to schedule (AntiAffinity conflict) on a 3-node cluster with replicas=2.
**Why it happens:** Cilium operator has pod AntiAffinity by default (one per node). With replicas=2 and small cluster, this works, but with 1 the taint risks are fewer.
**How to avoid:** Set `operator.replicas=1` for this homelab. Can increase to 2 for HA later.

---

## Code Examples

### Cilium Status Verification
```bash
# Source: cilium CLI — install first
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz
tar xzvf cilium-linux-amd64.tar.gz
sudo mv cilium /usr/local/bin

# Verify all nodes healthy
cilium status

# Run connectivity test (post-migration)
cilium connectivity test

# Observe flows via Hubble
kubectl port-forward -n kube-system deploy/hubble-relay 4245:grpc &
hubble observe --follow
```

### Flux-System NetworkPolicy Compatibility Check
```bash
# These 3 policies should still work after Cilium install
# Cilium is fully compatible with standard Kubernetes NetworkPolicy (confirmed via Kubernetes.io docs)
kubectl get networkpolicies -n flux-system
# Expect: allow-egress, allow-scraping, allow-webhooks — all unchanged
```

### Verify Apps Reachable After Migration
```bash
# Check all pods Running
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

# Check Cloudflare Tunnel pods specifically
kubectl get pods -A -l app=cloudflared

# Verify CNPG clusters healthy
kubectl get clusters.postgresql.cnpg.io -A
```

### Hubble UI Access
```bash
# After Traefik Ingress and DNS:
# Browser: https://hubble.watarystack.org

# Or local port-forward for testing:
kubectl port-forward -n kube-system svc/hubble-ui 8080:80
# Browser: http://localhost:8080
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Flannel (vxlan, iptables) | Cilium (eBPF, vxlan or native routing) | K8s 1.21+ | eBPF eliminates iptables chain traversal; Hubble adds L3-L7 visibility |
| Manual NetworkPolicy testing | `hubble observe` + Hubble UI flow graph | Cilium 1.8+ | Real-time flow visualization replaces guesswork |
| kube-proxy (iptables) | Cilium kube-proxy replacement (eBPF) | Cilium 1.6+ | O(1) service lookup vs O(n) iptables chains; deferred to follow-on phase |

**Deprecated/outdated:**
- Cilium 1.15.x: Still supported but 1.16.19 is the current LTS patch release — use 1.16.x
- `flannel-backend: wireguard` K3s config: Not relevant here; we're going to `none`
- `cilium install` CLI command for production: Use `helm install` for GitOps compatibility; `cilium install` wraps helm but obscures the values

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| helm | Cilium install | Yes | v3.17.2 | — |
| kubectl | All cluster ops | Yes | client v1.33.0 / server v1.30.0 | — |
| cilium CLI | Verification | No | — | Manual `kubectl` checks |
| hubble CLI | Flow observation | No | — | Port-forward + browser |
| SSH to workers | K3s-agent restart | Yes (password auth) | — | — |
| BPF filesystem `/sys/fs/bpf` | Cilium eBPF | Yes (mounted) | — | — |
| Linux kernel >= 4.19 | Cilium minimum | Yes (6.17.0-19) | 6.17.x | — |
| sshpass | Script SSH auth | No | — | Manual SSH with password |
| jq | Pod restart script | Check needed | — | Manual rollout restart |

**Missing dependencies with no fallback:**
- cilium CLI — must be installed before verification steps can run (install procedure in Code Examples above)

**Missing dependencies with fallback:**
- hubble CLI — port-forward to hubble-ui service works for browser-based flow observation without CLI
- sshpass — use manual SSH with typed password; or add SSH key to worker nodes first

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | kubectl + cilium CLI (no automated test framework — operational validation) |
| Config file | none |
| Quick run command | `kubectl get nodes && kubectl get pods -n kube-system \| grep cilium` |
| Full suite command | `cilium status && cilium connectivity test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SEC-01 | Cilium is the active CNI (Flannel removed) | smoke | `kubectl describe node \| grep flannel` returns nothing; `cilium status` shows OK | ❌ Wave 0 — operational |
| SEC-01 | All 3 nodes Ready with Cilium | smoke | `kubectl get nodes` all Ready | ❌ Wave 0 — operational |
| SEC-01 | All existing apps Running and reachable | smoke | `kubectl get pods -A \| grep -v Running \| grep -v Completed` returns empty | ❌ Wave 0 — operational |
| SEC-02 | Hubble enabled and showing flows | smoke | `hubble observe --follow` or Hubble UI at hubble.watarystack.org | ❌ Wave 0 — operational |
| SEC-02 | flux-system NetworkPolicies intact | verification | `kubectl get networkpolicies -n flux-system` shows 3 policies | ❌ Wave 0 — operational |

### Sampling Rate
- **Per task commit:** `kubectl get pods -n kube-system | grep cilium`
- **Per wave merge:** `cilium status` + `kubectl get pods --all-namespaces | grep -v Running`
- **Phase gate:** `cilium connectivity test` green + Hubble UI accessible before `/gsd:verify-work`

### Wave 0 Gaps
- All tests are operational (require live cluster state) — no test files to create
- Install cilium CLI: see Code Examples section for install script

---

## Open Questions

1. **Hostname for Hubble UI**
   - What we know: Ingress pattern is established (`*.watarystack.org`); Longhorn uses `longhorn.watarystack.org`
   - What's unclear: Whether `hubble.watarystack.org` needs a Cloudflare DNS CNAME or if it's internal-only (Traefik handles it via LAN)
   - Recommendation: Use `hubble.watarystack.org` with Traefik LAN routing (same as Longhorn) — internal access only, no Cloudflare tunnel needed. Add to `/etc/hosts` on workstation pointing to `192.168.1.115`.

2. **kube-proxy replacement timing**
   - What we know: K3s does not run kube-proxy as an explicit pod; disabling it requires `disable-kube-proxy: true` in K3s config and `kubeProxyReplacement: true` in Cilium
   - What's unclear: Whether to do this in Phase 9 or defer
   - Recommendation: Defer to a follow-on phase. Phase 9's goal (SEC-01, SEC-02) doesn't require it. Adding it doubles the blast radius of an already high-risk migration.

3. **operator.replicas: 1 vs 2**
   - What we know: 3-node cluster; Cilium operator default is 2 replicas; operator has AntiAffinity (max 1 per node)
   - What's unclear: Whether 1 replica is sufficient for homelab HA
   - Recommendation: Set to 1 for simplicity in homelab. If a node is lost and takes the operator down, Cilium keeps forwarding (data plane is separate from control plane).

---

## Sources

### Primary (HIGH confidence)
- `helm show values cilium/cilium --version 1.16.19` — Cilium helm chart values structure, Hubble UI service name/port, operator defaults
- `helm template cilium cilium/cilium --namespace kube-system --set hubble.ui.enabled=true` — confirmed Hubble UI service is named `hubble-ui` in `kube-system`, port 80→8081
- Live cluster: `kubectl describe node` — confirmed Flannel vxlan backend, pod CIDRs, kernel version, BPF mount
- `mount | grep bpf` — confirmed BPF filesystem present on control-plane
- K3s GitHub discussion #3498 — confirmed `flannel-backend` is server-side only; workers inherit automatically

### Secondary (MEDIUM confidence)
- [oneuptime.com: Installing Cilium on K3s (2026-03-14)](https://oneuptime.com/blog/post/2026-03-14-install-cilium-on-k3s/view) — K3s-specific helm values including k8sServiceHost=127.0.0.1:6444
- [bennesp.github.io: Migrate K3s to Cilium](https://bennesp.github.io/posts/004-k3s-cilium/) — `flannel.1` deletion requirement, config.yaml approach, pod restart strategies
- [picluster.ricsanfre.com: Cilium CNI](https://picluster.ricsanfre.com/docs/cilium/) — K3s server flags, helm values for ipam.operator.clusterPoolIPv4PodCIDRList
- [oneuptime.com: Deploy Cilium with Flux CD (2026-03-06)](https://oneuptime.com/blog/post/2026-03-06-deploy-cilium-flux-cd/view) — FluxCD HelmRepository + HelmRelease YAML structure

### Tertiary (LOW confidence — needs validation)
- [fluxcd/flux2 issue #1450](https://github.com/fluxcd/flux2/issues/1450) — FluxCD CrashloopBackoff with K3s+Cilium CNI; `--disable-network-policy` is the fix (this fix is already included in our procedure)
- [docs.k3s.io/networking/basic-network-options](https://docs.k3s.io/networking/basic-network-options) — general CNI options (official, but vague on in-place migration)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — version verified via helm repo, Cilium 1.16.19 confirmed available
- Architecture: HIGH — file structure matches established Longhorn pattern exactly; HelmRelease YAML from chart inspection
- Migration procedure: MEDIUM-HIGH — procedure synthesized from multiple 2026 community guides + official K3s discussion; not an officially documented K3s migration path
- Pitfalls: MEDIUM — most verified by GitHub issues and community guides; flannel.1 pitfall confirmed mandatory by bennesp guide
- Rollback: MEDIUM — community-documented, not officially K3s-supported

**Research date:** 2026-04-07
**Valid until:** 2026-05-07 (stable chart; re-verify Cilium version if >30 days before executing)
