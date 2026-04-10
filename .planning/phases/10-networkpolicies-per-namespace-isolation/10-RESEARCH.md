# Phase 10: NetworkPolicies — Per-Namespace Isolation - Research

**Researched:** 2026-04-11
**Domain:** Kubernetes NetworkPolicy, Cilium CNI, CloudNativePG isolation
**Confidence:** HIGH

## Summary

Phase 10 adds ingress-only default-deny NetworkPolicies to all 8 active app namespaces (linkding, n8n, mealie, audiobookshelf, pgadmin, homepage, xm-spotify-sync, filebrowser) and explicit allow-rules for every legitimate traffic flow. Cilium 1.16.19 is already installed as CNI and fully enforces standard `networking.k8s.io/v1` NetworkPolicy objects — no CiliumNetworkPolicy CRDs are needed for this scope. flux-system already has 3 NetworkPolicies (`allow-egress`, `allow-scraping`, `allow-webhooks`) that must not be touched (SEC-05).

The scope is **ingress-only default-deny** — egress is not restricted. This preserves n8n's ability to make HTTP calls to external services, apps' DNS resolution, and all outbound traffic without any additional policy. The isolation goal is enforced purely by controlling what can REACH each pod: a rogue pod like mealie cannot initiate a TCP connection to `linkding-postgres-rw.linkding.svc.cluster.local:5432` because the postgres pod's ingress rules only permit traffic from the linkding app pod, the cnpg-system operator, the monitoring Prometheus pod, and the pgadmin admin pod.

CloudNativePG (CNPG) introduces two critical ingress requirements not obvious from the app itself: the CNPG operator (in `cnpg-system` namespace) must reach postgres pods on **port 8000** (status API) and **port 5432** (postgres), and Prometheus must reach postgres pods on **port 9187** (metrics exporter) because a PodMonitor with `namespaceSelector: any: true` currently scrapes CNPG pods across all namespaces.

**Primary recommendation:** Write all NetworkPolicies in `apps/base/{app}/network-policy.yaml` (added to each base kustomization) so they deploy alongside the app in the same kustomize build, except the CNPG-specific allow-operator policy which can also live in `apps/base/linkding/` and `apps/base/n8n/` since those namespaces host both the app and the CNPG cluster.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SEC-03 | Default-deny NetworkPolicy applied in each app namespace | Standard `networking.k8s.io/v1` NetworkPolicy with empty podSelector and policyTypes: [Ingress]; 8 namespaces in scope |
| SEC-04 | Allow-rules per namespace so each app can only reach its own database and required services | Full traffic matrix documented — all legitimate flows identified including CNPG operator access, Prometheus scraping, pgadmin cross-namespace DB admin |
| SEC-05 | flux-system existing NetworkPolicies preserved and verified after Cilium migration | 3 existing policies confirmed in-place: `allow-egress`, `allow-scraping`, `allow-webhooks`; verification is a kubectl check, no changes needed |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| networking.k8s.io/v1 NetworkPolicy | Built into K8s | L3/L4 pod ingress isolation | Native K8s API; Cilium enforces it via eBPF |
| Cilium 1.16.19 | Already installed | CNI that enforces NetworkPolicy | Already deployed in Phase 9; standard eBPF datapath |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `kubectl run test-pod --image=busybox --rm -it --restart=Never -n mealie -- nc -zvw3 linkding-postgres-rw.linkding.svc.cluster.local 5432` | Isolation verification | Phase done-when test |
| Hubble UI (hubble.watarystack.org) | Observe dropped flows in real-time | Debugging when allow-rule is missing |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| networking.k8s.io/v1 | CiliumNetworkPolicy | Cilium CRD offers L7 rules; overkill for this scope; standard K8s policy portable across CNIs |
| ingress-only default-deny | ingress+egress default-deny | Egress deny breaks n8n external webhooks, DNS, backup to R2; phase explicitly scopes to ingress-only |

**Installation:** No new packages. All tooling already in cluster.

## Architecture Patterns

### Recommended File Structure
```
apps/base/{app}/
├── deployment.yaml
├── service.yaml
├── namespace.yaml
├── kustomization.yaml     ← add network-policy.yaml to resources
└── network-policy.yaml    ← NEW: all NetworkPolicies for this namespace
```

One `network-policy.yaml` per app base directory containing multiple NetworkPolicy objects separated by `---`. Added as a `resources:` entry in the existing `apps/base/{app}/kustomization.yaml`.

### Pattern 1: Default-Deny Ingress
**What:** Blocks all ingress to all pods in the namespace unless an explicit allow rule matches.
**When to use:** First policy in every app namespace.
```yaml
# Source: https://kubernetes.io/docs/concepts/services-networking/network-policies/
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

### Pattern 2: Allow Same-Namespace Pod (cloudflared → app)
**What:** Allows a specific labeled pod within the same namespace to reach an app pod.
**When to use:** cloudflared → app service in all Cloudflare Tunnel namespaces.
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-cloudflared
spec:
  podSelector:
    matchLabels:
      app: linkding          # Target: the app pod
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: cloudflared   # Source: cloudflared in same namespace
    ports:
    - port: 9090
      protocol: TCP
```

### Pattern 3: Allow Cross-Namespace (CNPG operator → postgres pods)
**What:** Allows pods from a specific external namespace to reach pods in this namespace.
**When to use:** cnpg-system operator → CNPG postgres pods; monitoring Prometheus → CNPG metrics.
**Source:** https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/docs/src/samples/networkpolicy-example.yaml
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-cnpg-operator
spec:
  podSelector:
    matchLabels:
      cnpg.io/cluster: linkding-postgres   # Target: CNPG pods only
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: cnpg-system
      podSelector:
        matchLabels:
          app.kubernetes.io/name: cloudnative-pg
    ports:
    - port: 8000    # CNPG status API (operator health checks)
    - port: 5432    # PostgreSQL
```

### Pattern 4: Prometheus Scrape Allow (monitoring → CNPG metrics)
**What:** Allows Prometheus pod to scrape metrics from CNPG postgres pods.
**When to use:** Any namespace where Prometheus needs to scrape pods.
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
spec:
  podSelector:
    matchLabels:
      cnpg.io/cluster: linkding-postgres   # Target: CNPG pods
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
      podSelector:
        matchLabels:
          app.kubernetes.io/name: prometheus
    ports:
    - port: 9187    # CNPG metrics exporter (named port: "metrics")
```

### Pattern 5: Allow Traefik Ingress (kube-system → app)
**What:** Allows Traefik (in kube-system) to route HTTP/HTTPS to an app pod.
**When to use:** homepage and xm-spotify-sync (use Traefik Ingress, not Cloudflare Tunnel).
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-traefik
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: homepage
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          app.kubernetes.io/name: traefik
    ports:
    - port: 3000
```

### Anti-Patterns to Avoid
- **`namespaceSelector` alone without `podSelector`:** Allows ALL pods in the namespace, not just the intended ones. Use both together in the same `from` entry for AND semantics.
- **Separate `namespaceSelector` and `podSelector` list entries:** Creates OR logic — allows any pod matching EITHER selector. Use a single object `{namespaceSelector: ..., podSelector: ...}` for AND.
- **Forgetting CNPG port 8000:** The CNPG operator queries postgres pods on port 8000 (status API) — missing this allows app isolation but breaks operator health checks.
- **Omitting CNPG metrics port 9187:** The PodMonitor `cloudnativepg-pods` in the monitoring namespace has `namespaceSelector: any: true` and scrapes port 9187. Missing this silently kills CNPG metrics in Grafana.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Isolation testing | Custom network diagnostic deployment | `kubectl run --image=busybox --rm -it` one-liner | Ephemeral pod; no cleanup overhead |
| Flow visibility | Manual tcpdump | Hubble UI at hubble.watarystack.org | Already deployed; shows AUDIT/DROP verdicts by namespace |
| Policy validation | Manual trace | `cilium connectivity test` or Hubble observe | Cilium provides built-in network flow audit mode |

**Key insight:** Hubble (deployed in Phase 9) is the correct tool for NetworkPolicy debugging. When a policy is too restrictive, Hubble shows dropped flows with source namespace, destination, and port — eliminating guesswork.

## Complete Traffic Matrix

This table is the authoritative source for all allow-rules needed.

### linkding namespace
| Source | Destination Pod | Port | Protocol | Rule Name |
|--------|----------------|------|----------|-----------|
| same-ns `app=cloudflared` | `app=linkding` | 9090 | TCP | allow-cloudflared |
| same-ns `app=linkding` | `cnpg.io/cluster=linkding-postgres` | 5432 | TCP | allow-app-to-postgres |
| `cnpg-system` / `app.kubernetes.io/name=cloudnative-pg` | `cnpg.io/cluster=linkding-postgres` | 8000, 5432 | TCP | allow-cnpg-operator |
| `monitoring` / `app.kubernetes.io/name=prometheus` | `cnpg.io/cluster=linkding-postgres` | 9187 | TCP | allow-prometheus-scrape |
| `pgadmin` ns (any pod) | `cnpg.io/cluster=linkding-postgres` | 5432 | TCP | allow-pgadmin |

### n8n namespace
| Source | Destination Pod | Port | Protocol | Rule Name |
|--------|----------------|------|----------|-----------|
| same-ns `app=cloudflared` | `app=n8n` | 5678 | TCP | allow-cloudflared |
| same-ns `app=n8n` | `cnpg.io/cluster=n8n-postgresql-cluster` | 5432 | TCP | allow-app-to-postgres |
| `cnpg-system` / `app.kubernetes.io/name=cloudnative-pg` | `cnpg.io/cluster=n8n-postgresql-cluster` | 8000, 5432 | TCP | allow-cnpg-operator |
| `monitoring` / `app.kubernetes.io/name=prometheus` | `cnpg.io/cluster=n8n-postgresql-cluster` | 9187 | TCP | allow-prometheus-scrape |
| `pgadmin` ns (any pod) | `cnpg.io/cluster=n8n-postgresql-cluster` | 5432 | TCP | allow-pgadmin |

### mealie namespace
| Source | Destination Pod | Port | Protocol | Rule Name |
|--------|----------------|------|----------|-----------|
| same-ns `app=cloudflared` | `app=mealie` | 9000 | TCP | allow-cloudflared |

### audiobookshelf namespace
| Source | Destination Pod | Port | Protocol | Rule Name |
|--------|----------------|------|----------|-----------|
| same-ns `app=cloudflared` | `app=audiobookshelf` | 3005 | TCP | allow-cloudflared |

### pgadmin namespace
| Source | Destination Pod | Port | Protocol | Rule Name |
|--------|----------------|------|----------|-----------|
| same-ns `app=cloudflared` | `app=pgadmin` | 80 | TCP | allow-cloudflared |

### homepage namespace
| Source | Destination Pod | Port | Protocol | Rule Name |
|--------|----------------|------|----------|-----------|
| `kube-system` / `app.kubernetes.io/name=traefik` | `app.kubernetes.io/name=homepage` | 3000 | TCP | allow-traefik |

### xm-spotify-sync namespace
| Source | Destination Pod | Port | Protocol | Rule Name |
|--------|----------------|------|----------|-----------|
| `kube-system` / `app.kubernetes.io/name=traefik` | `app=xm-spotify-sync` | 22111, 22112 | TCP | allow-traefik |

### filebrowser namespace
| Source | Destination Pod | Port | Protocol | Rule Name |
|--------|----------------|------|----------|-----------|
| same-ns `app=cloudflared` | `app=filebrowser` | 8088 | TCP | allow-cloudflared |

## Key Facts About the Existing Cluster

### Namespace Labels (kubernetes.io/metadata.name is auto-set since K8s 1.21)
| Namespace | Stable Selector Label | Use In |
|-----------|----------------------|--------|
| `monitoring` | `kubernetes.io/metadata.name: monitoring` | Prometheus scrape allow rules |
| `cnpg-system` | `kubernetes.io/metadata.name: cnpg-system` | CNPG operator allow rules |
| `kube-system` | `kubernetes.io/metadata.name: kube-system` | Traefik ingress allow rules |
| `pgadmin` | `kubernetes.io/metadata.name: pgadmin` | pgadmin cross-namespace DB access |

### Pod Labels (verified live)
| Pod | Key Labels | Used In |
|-----|-----------|---------|
| cloudflared | `app=cloudflared` | Source in all Cloudflare Tunnel namespace rules |
| linkding app | `app=linkding` | Source in linkding postgres allow rule |
| n8n app | `app=n8n` | Source in n8n postgres allow rule |
| linkding CNPG | `cnpg.io/cluster=linkding-postgres` | Target in linkding postgres rules |
| n8n CNPG | `cnpg.io/cluster=n8n-postgresql-cluster` | Target in n8n postgres rules |
| Prometheus | `app.kubernetes.io/name=prometheus` | Source in prometheus scrape rules |
| CNPG operator | `app.kubernetes.io/name=cloudnative-pg` | Source in CNPG operator rules |
| Traefik | `app.kubernetes.io/name=traefik` | Source in Traefik ingress rules |

### Existing flux-system NetworkPolicies (DO NOT MODIFY — SEC-05)
| Name | Effect |
|------|--------|
| `allow-egress` | All pods in flux-system can send egress AND receive intra-namespace ingress |
| `allow-scraping` | Any namespace can reach port 8080 on any flux-system pod |
| `allow-webhooks` | Any namespace can reach `app=notification-controller` pods on any port |

### Traffic NOT affected by ingress-only default-deny
- Kubelet liveness/readiness probes (host network, exempt from NetworkPolicy)
- cloudflared outbound tunnel connections to Cloudflare edge (egress — not restricted)
- n8n HTTP calls to external APIs (egress — not restricted)
- R2 backup traffic from CNPG (egress — not restricted)
- DNS resolution by all pods (egress UDP/53 to kube-system coredns — not restricted)
- node-exporter metrics scraping (host network pods bypass NetworkPolicy)

### Out-of-Scope Namespaces (not getting default-deny in this phase)
`monitoring`, `longhorn-system`, `cnpg-system`, `cert-manager`, `kube-system`, `renovate`, `flux-system`

## Common Pitfalls

### Pitfall 1: AND vs OR in `from` selectors
**What goes wrong:** Two separate list items (one `namespaceSelector`, one `podSelector`) create OR logic — allows any pod in the namespace OR any pod with that label anywhere.
**Why it happens:** YAML list syntax; many tutorials show this incorrectly.
**How to avoid:** Put both selectors in the SAME list entry object for AND semantics.
```yaml
# WRONG (OR logic — allows all pods in monitoring namespace):
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: monitoring
  - podSelector:
      matchLabels:
        app.kubernetes.io/name: prometheus

# CORRECT (AND logic — only prometheus pods in monitoring namespace):
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: monitoring
    podSelector:
      matchLabels:
        app.kubernetes.io/name: prometheus
```
**Warning signs:** mealie can reach linkding postgres after policies are applied.

### Pitfall 2: Missing CNPG Port 8000
**What goes wrong:** CNPG operator cannot perform health checks; cluster goes into Unknown state; backup WAL archiving eventually stalls.
**Why it happens:** Port 5432 is obvious; port 8000 (CNPG status API) is CNPG-specific and not documented in standard postgres setup guides.
**How to avoid:** Always include both ports 8000 and 5432 in the allow-cnpg-operator rule.
**Warning signs:** `kubectl get cluster -n linkding` shows status Unknown or unreconciled.

### Pitfall 3: Missing CNPG Metrics Port 9187
**What goes wrong:** Grafana CNPG dashboards show "No data"; PodMonitor `cloudnativepg-pods` stops collecting.
**Why it happens:** PodMonitor uses `namespaceSelector: any: true` to scrape all namespaces — but NetworkPolicy blocks Prometheus ingress to port 9187.
**How to avoid:** Include port 9187 in the allow-prometheus-scrape rule targeting CNPG pods.
**Warning signs:** Prometheus targets page shows postgres pods as DOWN on port 9187.

### Pitfall 4: Forgetting pgadmin Cross-Namespace DB Access
**What goes wrong:** pgadmin UI fails to connect to either postgres cluster; users lose DB admin capability.
**Why it happens:** pgadmin stores server connection configs in its PVC and connects across namespaces — this cross-namespace traffic goes through the ingress of linkding/n8n namespaces.
**How to avoid:** Add a `allow-pgadmin` ingress rule in both linkding and n8n namespaces allowing traffic from the `pgadmin` namespace on port 5432.
**Warning signs:** pgadmin shows "connection refused" or timeout when connecting to registered servers.

### Pitfall 5: Applying Default-Deny Before Allow Rules
**What goes wrong:** Brief outage between default-deny apply and allow rule apply — existing connections (CNPG replication, app→db connections) drop.
**Why it happens:** Kustomize applies resources in order but reconciliation may not be atomic.
**How to avoid:** Include all policies (default-deny + all allow rules) in the same `network-policy.yaml` file. Kustomize builds them as a single batch. FluxCD applies atomically.
**Warning signs:** App pod CrashLoopBackOff immediately after policy apply.

### Pitfall 6: xm-spotify-sync has dual-port Traefik ingress
**What goes wrong:** Only one of the two ports (frontend 22111 or backend 22112) gets the allow rule.
**Why it happens:** Most apps have a single port; xm-spotify-sync is the exception.
**How to avoid:** Allow both ports 22111 and 22112 in the traefik allow rule for xm-spotify-sync.
**Warning signs:** Frontend loads but API calls fail (or vice versa).

## Code Examples

### Verified: linkding complete network-policy.yaml
```yaml
# Source: Official K8s NetworkPolicy API + CNPG networking docs
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-cloudflared
spec:
  podSelector:
    matchLabels:
      app: linkding
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: cloudflared
    ports:
    - port: 9090
      protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app-to-postgres
spec:
  podSelector:
    matchLabels:
      cnpg.io/cluster: linkding-postgres
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: linkding
    ports:
    - port: 5432
      protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-cnpg-operator
spec:
  podSelector:
    matchLabels:
      cnpg.io/cluster: linkding-postgres
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: cnpg-system
      podSelector:
        matchLabels:
          app.kubernetes.io/name: cloudnative-pg
    ports:
    - port: 8000
      protocol: TCP
    - port: 5432
      protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
spec:
  podSelector:
    matchLabels:
      cnpg.io/cluster: linkding-postgres
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
      podSelector:
        matchLabels:
          app.kubernetes.io/name: prometheus
    ports:
    - port: 9187
      protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-pgadmin
spec:
  podSelector:
    matchLabels:
      cnpg.io/cluster: linkding-postgres
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: pgadmin
    ports:
    - port: 5432
      protocol: TCP
```

### Isolation Test Command
```bash
# Expected result: FAILS (connection refused or timeout) — proves isolation works
kubectl run isolation-test --image=busybox --rm -it --restart=Never -n mealie \
  -- nc -zvw3 linkding-postgres-rw.linkding.svc.cluster.local 5432

# Verify legitimate access still works (should SUCCEED):
kubectl run access-test --image=busybox --rm -it --restart=Never -n linkding \
  -- nc -zvw3 linkding-postgres-rw 5432
```

### Verify flux-system Policies Intact (SEC-05)
```bash
kubectl get networkpolicies -n flux-system
# Expected: allow-egress, allow-scraping, allow-webhooks — exactly 3, unchanged
```

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|-----------------|--------|
| Flannel (no NetworkPolicy enforcement) | Cilium 1.16 eBPF | NetworkPolicy now actually enforced |
| No namespace isolation | Default-deny + explicit allows | Zero-trust pod-to-pod posture |

**Key:** Cilium was installed in Phase 9. Without Cilium (or another NetworkPolicy-capable CNI), creating NetworkPolicy objects would have been silently ignored by Flannel. Flannel does not enforce NetworkPolicy.

## Open Questions

1. **Should pgadmin's cross-namespace DB access be tightened to specific pod labels?**
   - What we know: pgadmin is in pgadmin namespace; connects to linkding-postgres and n8n-postgresql-cluster via stored PVC sessions
   - What's unclear: Are there pod labels stable enough on pgadmin to use `podSelector` to restrict which pods in pgadmin ns can reach postgres?
   - Recommendation: Use `namespaceSelector: pgadmin` only (no podSelector) — pgadmin only has one pod anyway, and it simplifies the rule. If pgadmin namespace ever contains untrusted pods, revisit.

2. **Should monitoring namespace get a default-deny policy in this phase?**
   - What we know: The phase scope says "each app namespace" — monitoring is infrastructure
   - What's unclear: Phase scope is ambiguous on whether Grafana/AlertManager/Prometheus need isolation
   - Recommendation: Exclude monitoring from this phase; document as potential Phase 11+ hardening.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Cilium CNI | NetworkPolicy enforcement | Yes | 1.16.19 | — |
| kubectl | Apply/verify policies | Yes | K8s 1.30 API | — |
| busybox image | Isolation test pod | Yes (public registry) | latest | nicolaka/netshoot |
| Hubble UI | Flow debugging | Yes | hubble.watarystack.org | `cilium status` CLI |
| FluxCD | GitOps apply | Yes | v2.5.1 | kubectl apply -k |

**Missing dependencies with no fallback:** None.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | kubectl one-shot test pods (no automated test framework — infrastructure change) |
| Config file | none |
| Quick run command | `kubectl run isolation-test --image=busybox --rm -it --restart=Never -n mealie -- nc -zvw3 linkding-postgres-rw.linkding.svc.cluster.local 5432` |
| Full suite command | See Phase Requirements → Test Map below |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SEC-03 | default-deny-ingress exists in all 8 app namespaces | smoke | `kubectl get networkpolicies --all-namespaces \| grep default-deny-ingress \| wc -l` (expect 8) | n/a — kubectl check |
| SEC-04 | mealie cannot reach linkding postgres | isolation | `kubectl run test --image=busybox --rm --restart=Never -n mealie -- nc -zvw3 linkding-postgres-rw.linkding.svc.cluster.local 5432; [ $? -ne 0 ] && echo PASS || echo FAIL` | n/a — kubectl check |
| SEC-04 | linkding app CAN reach its own postgres | access | `kubectl run test --image=busybox --rm --restart=Never -n linkding -- nc -zvw3 linkding-postgres-rw 5432; [ $? -eq 0 ] && echo PASS || echo FAIL` | n/a — kubectl check |
| SEC-04 | n8n app CAN reach its own postgres | access | `kubectl run test --image=busybox --rm --restart=Never -n n8n -- nc -zvw3 n8n-postgresql-cluster-rw 5432; [ $? -eq 0 ] && echo PASS || echo FAIL` | n/a — kubectl check |
| SEC-04 | All app pods Running after policies apply | smoke | `kubectl get pods --all-namespaces \| grep -v Running \| grep -v Completed` | n/a — kubectl check |
| SEC-05 | flux-system has exactly 3 NetworkPolicies | smoke | `kubectl get networkpolicies -n flux-system \| grep -c "allow-"` (expect 3) | n/a — kubectl check |

### Sampling Rate
- **Per task commit:** `kubectl get pods --all-namespaces | grep -v Running | grep -v Completed` (verify no pods in Error/CrashLoop)
- **Per wave merge:** Full isolation test suite from the table above
- **Phase gate:** All 6 test checks pass before `/gsd:verify-work`

### Wave 0 Gaps
None — existing infrastructure covers all phase requirements. No test framework to install.

## Sources

### Primary (HIGH confidence)
- Kubernetes official docs — NetworkPolicy API, default-deny patterns, AND vs OR selector semantics: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- CloudNativePG official networking docs — port 8000 + 5432 operator requirement, example networkpolicy-example.yaml: https://cloudnative-pg.io/docs/devel/networking/
- CloudNativePG GitHub sample manifest (verified YAML): https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/docs/src/samples/networkpolicy-example.yaml
- Live cluster introspection — namespace labels, pod labels, existing NetworkPolicies, service ports (kubectl output 2026-04-11)

### Secondary (MEDIUM confidence)
- Cilium docs on NetworkPolicy enforcement modes: https://docs.cilium.io/en/stable/network/kubernetes/policy/
- CNCF blog — safe Cilium policy management and Hubble audit mode: https://www.cncf.io/blog/2025/11/06/safely-managing-cilium-network-policies-in-kubernetes-testing-and-simulation-techniques/

### Tertiary (LOW confidence)
- General NetworkPolicy best practices (Azure AKS docs — different platform but same K8s API): https://learn.microsoft.com/en-us/azure/aks/network-policy-best-practices

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Cilium 1.16 installed, standard K8s NetworkPolicy API confirmed working
- Traffic matrix: HIGH — all pod labels, namespace labels, service ports verified live against cluster
- CNPG requirements: HIGH — confirmed against official CNPG networking docs + live port verification
- Architecture (file placement): HIGH — follows established base/overlay convention in this repo
- Pitfalls: HIGH — AND/OR selector behavior is K8s documented; port 8000 confirmed from CNPG docs + live pod spec

**Research date:** 2026-04-11
**Valid until:** 2026-05-11 (stable K8s API; CNPG operator label `app.kubernetes.io/name=cloudnative-pg` stable)

## Project Constraints (from CLAUDE.md)

| Directive | Impact on This Phase |
|-----------|---------------------|
| Follow base/overlay pattern | NetworkPolicy files go in `apps/base/{app}/network-policy.yaml`, referenced in base kustomization |
| Never commit unencrypted secrets | Not applicable — NetworkPolicy objects contain no secrets |
| Branch from main, never commit to main | Create `feat/phase-10-networkpolicies` branch |
| Test with `kubectl apply -k ... --dry-run=client` first | Validate each namespace kustomization before commit |
| All secrets SOPS-encrypted | Not applicable — NetworkPolicy objects are not secrets |
| Add new apps to Homepage dashboard | Not applicable — no new apps in this phase |
