---
phase: 10-networkpolicies-per-namespace-isolation
verified: 2026-04-11T00:00:00Z
status: human_needed
score: 4/4 must-haves verified
human_verification:
  - test: "Run: kubectl get networkpolicies --all-namespaces — confirm 3-4 policies appear in each of the 8 app namespaces"
    expected: "Each of audiobookshelf, filebrowser, homepage, linkding, mealie, n8n, pgadmin, xm-spotify-sync shows NetworkPolicy entries; linkding and n8n show 4 policies each; homepage and xm-spotify-sync show 4 policies each; others show 3 each"
    why_human: "Requires cluster access to verify FluxCD has applied the manifests after the PR is merged to main"
  - test: "Run a test pod in mealie namespace attempting to connect to linkding-postgres: kubectl run test-isolation --rm -it --restart=Never -n mealie --image=postgres:17 -- pg_isready -h linkding-postgres-rw.linkding.svc.cluster.local -p 5432"
    expected: "Connection refused or timeout — NOT 'accepting connections'"
    why_human: "Requires live cluster with Cilium CNI enforcing policies; can only verify after PR #58 is merged and FluxCD applies the NetworkPolicies"
---

# Phase 10: NetworkPolicies — Per-Namespace Isolation Verification Report

**Phase Goal:** Each app namespace has a default-deny NetworkPolicy plus explicit allow-rules for its required connections, so no app can reach another app's database.
**Verified:** 2026-04-11T00:00:00Z
**Status:** human_needed (all automated checks passed; live cluster enforcement requires human verification after PR #58 merge)
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | default-deny-ingress NetworkPolicy exists in each of the 8 app namespaces | VERIFIED | All 8 `apps/base/*/network-policy.yaml` files confirmed present; each contains `name: default-deny-ingress` with correct namespace field |
| 2 | Allow-rules configured per namespace — linkding/n8n have allow-cnpg-controller; homepage/xm-spotify-sync have allow-traefik-ingress; all have allow-same-namespace and allow-monitoring-scraping | VERIFIED | Files inspected: linkding and n8n each have 4 NetworkPolicy objects including `allow-cnpg-controller`; homepage and xm-spotify-sync each have 4 including `allow-traefik-ingress`; all 8 have `allow-same-namespace` and `allow-monitoring-scraping` |
| 3 | flux-system existing NetworkPolicies are preserved (git manifests don't touch flux-system at all) | VERIFIED | No `flux-system` directory or flux-system NetworkPolicy manifest in `apps/base/` or `apps/staging/`; confirmed by PLAN context: "These are NOT in git — leave them alone" |
| 4 | homelab-app-onboarding SKILL.md has Step 2.6 with NetworkPolicy templates | VERIFIED | `Step 2.6 — Add NetworkPolicy for Namespace Isolation` found at line 448 of SKILL.md, before Step 3 (line 570); all 3 templates (A/B/C) present; checklist updated at lines 987-988 |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `apps/base/audiobookshelf/network-policy.yaml` | 3 NetworkPolicies: default-deny-ingress, allow-same-namespace, allow-monitoring-scraping | VERIFIED | File exists, 3 NetworkPolicy objects, correct namespace field, correct labels |
| `apps/base/filebrowser/network-policy.yaml` | 3 NetworkPolicies baseline | VERIFIED | File exists, 3 NetworkPolicy objects confirmed via `grep -c` |
| `apps/base/mealie/network-policy.yaml` | 3 NetworkPolicies baseline | VERIFIED | File exists, 3 NetworkPolicy objects confirmed |
| `apps/base/pgadmin/network-policy.yaml` | 3 NetworkPolicies baseline | VERIFIED | File exists, 3 NetworkPolicy objects confirmed |
| `apps/base/linkding/network-policy.yaml` | 4 NetworkPolicies including allow-cnpg-controller | VERIFIED | File exists, 4 NetworkPolicy objects; `allow-cnpg-controller` with `cnpg.io/podRole: instance` selector targeting `cnpg-system` namespace confirmed |
| `apps/base/n8n/network-policy.yaml` | 4 NetworkPolicies including allow-cnpg-controller | VERIFIED | File exists, 4 NetworkPolicy objects; `allow-cnpg-controller` confirmed |
| `apps/base/homepage/network-policy.yaml` | 4 NetworkPolicies including allow-traefik-ingress | VERIFIED | File exists, 4 NetworkPolicy objects; `allow-traefik-ingress` with combined `namespaceSelector+podSelector` (AND semantics) targeting kube-system/traefik confirmed |
| `apps/base/xm-spotify-sync/network-policy.yaml` | 4 NetworkPolicies including allow-traefik-ingress | VERIFIED | File exists, 4 NetworkPolicy objects; `allow-traefik-ingress` confirmed |
| `.claude/skills/homelab-app-onboarding/SKILL.md` | Updated with Step 2.6 covering all 3 NetworkPolicy templates and checklist | VERIFIED | Step 2.6 at line 448; Template A (cloudflared), B (CNPG), C (Traefik) all present; checklist items at lines 987-988 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `apps/base/audiobookshelf/network-policy.yaml` | `apps/base/audiobookshelf/kustomization.yaml` | kustomize resources list | WIRED | `- network-policy.yaml` present in kustomization.yaml resources |
| `apps/base/filebrowser/network-policy.yaml` | `apps/base/filebrowser/kustomization.yaml` | kustomize resources list | WIRED | `- network-policy.yaml` present |
| `apps/base/mealie/network-policy.yaml` | `apps/base/mealie/kustomization.yaml` | kustomize resources list | WIRED | `- network-policy.yaml` present |
| `apps/base/pgadmin/network-policy.yaml` | `apps/base/pgadmin/kustomization.yaml` | kustomize resources list | WIRED | `- network-policy.yaml` present |
| `apps/base/linkding/network-policy.yaml` | `apps/base/linkding/kustomization.yaml` | kustomize resources list | WIRED | `- network-policy.yaml` present |
| `apps/base/n8n/network-policy.yaml` | `apps/base/n8n/kustomization.yaml` | kustomize resources list | WIRED | `- network-policy.yaml` present |
| `apps/base/homepage/network-policy.yaml` | `apps/base/homepage/kustomization.yaml` | kustomize resources list | WIRED | `- network-policy.yaml` present |
| `apps/base/xm-spotify-sync/network-policy.yaml` | `apps/base/xm-spotify-sync/kustomization.yaml` | kustomize resources list | WIRED | `- network-policy.yaml` present |

### Data-Flow Trace (Level 4)

Not applicable. NetworkPolicy manifests are declarative Kubernetes objects — they have no application data flow. Enforcement is by the Cilium CNI (cluster-side), which requires live cluster verification (see Human Verification section).

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| audiobookshelf kustomize build succeeds | `kubectl kustomize apps/base/audiobookshelf/` | Exit 0 | PASS |
| filebrowser kustomize build succeeds | `kubectl kustomize apps/base/filebrowser/` | Exit 0 | PASS |
| mealie kustomize build succeeds | `kubectl kustomize apps/base/mealie/` | Exit 0 | PASS |
| pgadmin kustomize build succeeds | `kubectl kustomize apps/base/pgadmin/` | Exit 0 | PASS |
| linkding kustomize build succeeds | `kubectl kustomize apps/base/linkding/` | Exit 0 | PASS |
| n8n kustomize build succeeds | `kubectl kustomize apps/base/n8n/` | Exit 0 | PASS |
| homepage kustomize build succeeds | `kubectl kustomize apps/base/homepage/` | Exit 0 | PASS |
| xm-spotify-sync kustomize build succeeds | `kubectl kustomize apps/base/xm-spotify-sync/` | Exit 0 | PASS |

All 8 kustomize builds pass successfully.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SEC-03 | 10-01-PLAN.md | A default-deny NetworkPolicy is applied in each app namespace | SATISFIED | `default-deny-ingress` NetworkPolicy confirmed in all 8 `apps/base/*/network-policy.yaml` files |
| SEC-04 | 10-01-PLAN.md | Allow-rules configured per namespace so each app can reach only its own database and required services | SATISFIED | Targeted allow rules verified: `allow-same-namespace` (all 8), `allow-monitoring-scraping` (all 8), `allow-cnpg-controller` (linkding, n8n), `allow-traefik-ingress` (homepage, xm-spotify-sync) |
| SEC-05 | 10-01-PLAN.md | flux-system existing NetworkPolicies are preserved | SATISFIED | No flux-system manifests exist in git; existing cluster-side imperative policies remain untouched |

**Documentation note:** REQUIREMENTS.md tracking table (lines 107-109) lists SEC-03/04/05 under "Phase 11" — this is a stale entry from when the roadmap had a different phase numbering. ROADMAP.md correctly assigns all three requirements to Phase 10. The `[x]` checkmarks on the requirement definitions (lines 43-45) are accurate.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | — | — | — | — |

No anti-patterns found. All network-policy.yaml files contain complete, non-placeholder Kubernetes manifests. No TODOs, stubs, or empty implementations detected.

### Human Verification Required

#### 1. NetworkPolicies Applied by FluxCD

**Test:** After PR #58 is merged to main, run:
```
kubectl get networkpolicies --all-namespaces
```
**Expected:** 3-4 policies visible per app namespace:
- audiobookshelf, filebrowser, mealie, pgadmin: 3 policies each (default-deny-ingress, allow-same-namespace, allow-monitoring-scraping)
- linkding, n8n: 4 policies each (+ allow-cnpg-controller)
- homepage, xm-spotify-sync: 4 policies each (+ allow-traefik-ingress)
**Why human:** Requires live cluster access; FluxCD must merge and reconcile before policies are enforced.

#### 2. Cross-Namespace DB Isolation Enforced

**Test:** After FluxCD applies, run a test pod in mealie namespace:
```
kubectl run test-isolation --rm -it --restart=Never -n mealie \
  --image=postgres:17 -- pg_isready -h linkding-postgres-rw.linkding.svc.cluster.local -p 5432
```
**Expected:** Connection refused or timeout — result must NOT be "accepting connections"
**Why human:** Network enforcement is a live cluster behavior. The NetworkPolicy objects declare intent; Cilium's data-plane enforcement is what actually blocks traffic. This cannot be simulated from the git tree alone.

### PR Status

PR #58 (`feat(phase-10): NetworkPolicies — per-namespace isolation`) is open targeting `main`. Branch: `feat/phase-10-networkpolicies`. All Phase 10 work (6 commits: b934d7c, 7565680, 9ff0a99, ad68191, 06aa8e8, b3f07e1) is bundled in this PR. FluxCD will apply the NetworkPolicies within ~1 minute of merge.

### Gaps Summary

No gaps found. All automated verifiable must-haves are confirmed:

- All 8 `network-policy.yaml` files exist with correct content and policy counts
- All 8 `kustomization.yaml` files include `network-policy.yaml` in resources
- All 8 `kubectl kustomize` builds pass
- `SKILL.md` Step 2.6 is present with all 3 templates and checklist items
- PR #58 is open targeting main

The only remaining items are live cluster verifications that require FluxCD to apply the manifests after PR merge.

---

_Verified: 2026-04-11T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
