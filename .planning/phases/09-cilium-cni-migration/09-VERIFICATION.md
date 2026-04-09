---
phase: 09-cilium-cni-migration
verified: 2026-04-09T08:00:00Z
status: passed
score: 5/5 must-haves verified
re_verification: false
gaps: []
human_verification:
  - test: "Confirm FluxCD adopts the existing Cilium HelmRelease after PR #54 merges"
    expected: "kubectl get helmrelease -n kube-system cilium shows Reconciled=True with no re-install triggered"
    why_human: "FluxCD adoption of an imperatively-installed Helm release cannot be verified without a running cluster"
  - test: "Browse to https://hubble.watarystack.org and confirm Hubble UI loads"
    expected: "Hubble UI renders network flows; cert-manager has issued a valid TLS certificate"
    why_human: "Requires a running cluster with Traefik, cert-manager, and DNS resolving hubble.watarystack.org"
---

# Phase 9: Cilium CNI Migration Verification Report

**Phase Goal:** Migrate the K3s cluster from Flannel to Cilium CNI. Replace the default Flannel CNI with Cilium 1.16.19 for eBPF-based networking, network policy enforcement, and Hubble observability. Bring the installation under GitOps control via FluxCD.
**Verified:** 2026-04-09T08:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

Plans 09-01 and 09-02 were imperative cluster operations (disabling Flannel, bootstrapping Cilium during a maintenance window). Their SUMMARYs confirm completion; no git artifacts exist for them. Verification scope is the git artifacts committed by Plan 09-03, which is the only plan that brings the installation under GitOps control.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | FluxCD HelmRelease for Cilium committed to git | VERIFIED | `infrastructure/controllers/base/cilium/release.yaml` exists; `kind: HelmRelease`, `name: cilium`, `namespace: kube-system`, `version: "1.16.19"` |
| 2 | Hubble UI accessible at hubble.watarystack.org via Traefik Ingress with TLS | VERIFIED (git artifacts) | `infrastructure/controllers/staging/cilium/ingress.yaml` exists; `host: hubble.watarystack.org`, `ingressClassName: traefik`, `cert-manager.io/cluster-issuer: letsencrypt-cloudflare-prod` — runtime accessibility needs human check |
| 3 | Hubble UI appears on the Homepage dashboard | VERIFIED | `apps/base/homepage/homepage-configmap.yaml` lines 57-60 contain `- Hubble:` with `href: https://hubble.watarystack.org` and `icon: cilium.png` |
| 4 | cilium directories exist in infrastructure/controllers/ | VERIFIED | `infrastructure/controllers/base/cilium/` contains repository.yaml, release.yaml, kustomization.yaml; `infrastructure/controllers/staging/cilium/` contains ingress.yaml, kustomization.yaml |
| 5 | base/kustomization.yaml and staging/kustomization.yaml both include cilium | VERIFIED | `infrastructure/controllers/base/kustomization.yaml` line 7: `- cilium`; `infrastructure/controllers/staging/kustomization.yaml` line 8: `- cilium` |

**Score:** 5/5 truths verified (git artifacts)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `infrastructure/controllers/base/cilium/release.yaml` | HelmRelease for Cilium 1.16.19 in kube-system | VERIFIED | Contains `chart: cilium`, `version: "1.16.19"`, `namespace: kube-system`, K3s-specific values (`k8sServiceHost: 127.0.0.1`, `k8sServicePort: 6444`), Hubble enabled with relay, UI, and Prometheus ServiceMonitor |
| `infrastructure/controllers/base/cilium/repository.yaml` | HelmRepository pointing to helm.cilium.io | VERIFIED | `url: https://helm.cilium.io/` in `namespace: flux-system` |
| `infrastructure/controllers/staging/cilium/ingress.yaml` | Traefik Ingress for Hubble UI at hubble.watarystack.org | VERIFIED | `host: hubble.watarystack.org`, `name: hubble-ui`, `port: 80`, `secretName: hubble-ui-tls`, `letsencrypt-cloudflare-prod` annotation present |
| `apps/base/homepage/homepage-configmap.yaml` | Homepage entry for Hubble UI | VERIFIED | Contains `- Hubble:` block with `href: https://hubble.watarystack.org`, `description: Cilium network observability`, `icon: cilium.png` |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `infrastructure/controllers/base/cilium/release.yaml` | `kube-system/helmrelease/cilium` | FluxCD HelmRelease adoption | WIRED | `name: cilium`, `namespace: kube-system` matches the imperatively-installed helm release name; FluxCD will adopt on reconcile |
| `infrastructure/controllers/staging/cilium/ingress.yaml` | `kube-system/service/hubble-ui:80` | Traefik Ingress | WIRED | `service.name: hubble-ui`, `port.number: 80` in kube-system namespace |
| `infrastructure/controllers/base/cilium/kustomization.yaml` | base resources | Kustomize | WIRED | References `repository.yaml` and `release.yaml` |
| `infrastructure/controllers/staging/cilium/kustomization.yaml` | staging resources | Kustomize | WIRED | References `../../base/cilium/` and `ingress.yaml` |
| `infrastructure/controllers/base/kustomization.yaml` | `base/cilium/` | Kustomize resource entry | WIRED | `- cilium` present in resources list |
| `infrastructure/controllers/staging/kustomization.yaml` | `staging/cilium/` | Kustomize resource entry | WIRED | `- cilium` present in resources list |

---

### Data-Flow Trace (Level 4)

Not applicable. This phase produces Kubernetes declarative manifests (HelmRelease, HelmRepository, Ingress, ConfigMap) — not components that render dynamic data from a fetch/state source. The data-flow is: git commit -> FluxCD reconcile -> Kubernetes API apply. Runtime behavior requires human verification.

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — manifests require a live Kubernetes cluster and FluxCD to execute. No runnable entry points available for static spot-checks. Runtime behavior is covered in the Human Verification section.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| SEC-01 | 09-03-PLAN.md | Cilium is installed as the CNI, replacing Flannel | SATISFIED (git) | HelmRelease committed in `base/cilium/release.yaml`; imperative install confirmed by 09-01 and 09-02 SUMMARYs |
| SEC-02 | 09-03-PLAN.md | Hubble observability is enabled in Cilium | SATISFIED (git) | `release.yaml` values include `hubble.enabled: true`, `relay.enabled: true`, `ui.enabled: true`, Prometheus ServiceMonitor configured |

**Traceability discrepancy noted:** REQUIREMENTS.md (line 105-106) maps SEC-01 and SEC-02 to Phase 10, but these requirements were delivered in Phase 9. The plan frontmatter (`09-03-PLAN.md`) and commit message (`37333ee`) explicitly claim SEC-01 and SEC-02. REQUIREMENTS.md traceability table should be updated to reflect Phase 9. This is a documentation inconsistency, not a gap in implementation.

---

### Anti-Patterns Found

No anti-patterns found. Scanned:
- `infrastructure/controllers/base/cilium/` — no TODO, FIXME, placeholder, empty returns
- `infrastructure/controllers/staging/cilium/` — no TODO, FIXME, placeholder, empty returns
- All YAML is substantive declarative configuration with real values

---

### Human Verification Required

#### 1. FluxCD HelmRelease Adoption

**Test:** After PR #54 merges to main, wait for FluxCD reconciliation (up to 1 minute), then run: `kubectl get helmrelease -n kube-system cilium`
**Expected:** `READY=True`, `STATUS=Release reconciliation succeeded`, no pod restarts on cilium-agent or cilium-operator
**Why human:** Cannot verify FluxCD adoption of an imperatively-installed Helm release without a live cluster. The risk is that FluxCD detects value drift between the committed HelmRelease and the bootstrapped install and triggers a re-install, which would cause a brief network outage.

#### 2. Hubble UI Accessibility

**Test:** After PR merges and FluxCD reconciles, run: `kubectl get ingress -n kube-system hubble-ui` and `kubectl get certificate -n kube-system hubble-ui-tls`, then browse to https://hubble.watarystack.org
**Expected:** Ingress created, certificate in Ready state, Hubble UI loads showing network flows
**Why human:** Requires running cluster, Traefik, cert-manager, and DNS routing. TLS issuance via Let's Encrypt DNS-01 challenge takes 1-2 minutes after reconciliation.

#### 3. Network Connectivity Post-Migration

**Test:** After merge, verify existing apps are still functional: `kubectl get pods --all-namespaces | grep -v Running` and check that all previously-working apps respond at their domains
**Expected:** All pods remain Running; no CrashLoopBackOff; apps at their Cloudflare Tunnel URLs continue working
**Why human:** Cilium migration (Plans 09-01/09-02) was imperative; this verification should have been done then, but the GitOps commit (PR #54) is the final gate before marking the phase complete.

---

### Gaps Summary

No gaps in git artifacts. All five observable truths are verified against the actual codebase. The phase goal — bringing Cilium under GitOps control via FluxCD with Hubble UI exposed and on the homepage — is fully achieved at the git/manifest layer.

Three items require human verification after PR #54 merges: FluxCD adoption confirmation, Hubble UI accessibility, and overall cluster health. These are expected post-merge runtime checks, not blockers to the phase's git deliverables.

One administrative item: REQUIREMENTS.md traceability table should be updated to move SEC-01 and SEC-02 from Phase 10 to Phase 9.

---

_Verified: 2026-04-09T08:00:00Z_
_Verifier: Claude (gsd-verifier)_
