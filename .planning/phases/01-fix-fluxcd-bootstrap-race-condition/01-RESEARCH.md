# Phase 1: Fix FluxCD Bootstrap Race Condition - Research

**Researched:** 2026-04-04
**Domain:** FluxCD Kustomization dependency ordering
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Add `dependsOn: - name: databases` to `clusters/staging/apps.yaml`
- **D-02:** Remove the commented-out `dependsOn: infra-configs` block — replace it with the correct target (`databases`)
- **D-03:** No other fields in `apps.yaml` need to change (no `wait: true`, no healthChecks — that's out of scope for this phase)
- **D-04:** Test via `flux reconcile kustomization apps --dry-run` before merging
- **D-05:** Confirm with `flux get kustomizations` that the dependency graph shows `apps` → `databases`
- **D-06:** Change merged to main via PR — FluxCD applies it on sync

### Claude's Discretion
- Exact PR description wording
- Whether to add a comment in `apps.yaml` explaining the dependency

### Deferred Ideas (OUT OF SCOPE)
- Adding `wait: true` + healthChecks to `apps.yaml` — out of scope for this phase
- `infrastructure-controllers` healthChecks expansion — separate concern
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CRIT-01 | `apps` Kustomization has `dependsOn: [databases]` so apps never race databases on bootstrap | Verified: FluxCD v1 `dependsOn` field syntax confirmed in live cluster; pattern already used in `databases.yaml`; `kubectl apply --dry-run=client` confirms manifest validity |
</phase_requirements>

---

## Summary

This phase is a single-field YAML change to `clusters/staging/apps.yaml`. The `dependsOn` block is already commented out with an incorrect target (`infra-configs`). The fix replaces it with `databases` as the dependency target, completing the chain `infrastructure-controllers` → `databases` → `apps`.

The identical `dependsOn` pattern is already live and working in `clusters/staging/databases.yaml`, which depends on `infrastructure-controllers`. This gives a verified, in-cluster reference for exact syntax. FluxCD v2.5.1 (confirmed installed) uses the `kustomize.toolkit.fluxcd.io/v1` API with `spec.dependsOn[].name` string field.

One important correction from CONTEXT.md: D-04 references `flux reconcile kustomization apps --dry-run`, but `--dry-run` is **not a valid flag** for `flux reconcile` in v2.5.1. The correct pre-merge validation is `kubectl apply -f clusters/staging/apps.yaml --dry-run=client`, which was tested and returns `kustomization.kustomize.toolkit.fluxcd.io/apps configured (dry run)`. Post-merge verification uses `kubectl get kustomization apps -n flux-system -o jsonpath='{.spec.dependsOn}'`.

**Primary recommendation:** Make the one-line YAML change, validate with `kubectl apply --dry-run=client`, open PR against `feat/homelab-improvement`, merge — done.

---

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| FluxCD kustomize-controller | v1.5.1 (in-cluster) | Applies Kustomization resources with dependency ordering | The GitOps controller managing all cluster state |
| FluxCD CLI | v2.5.1 (confirmed) | Reconcile and inspect kustomizations | Used for post-merge verification |
| kubectl | in-cluster kubeconfig | Apply manifests, dry-run validation, inspect live state | Standard Kubernetes CLI |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| git / gh CLI | system | Branch creation, PR workflow | Branch off `feat/homelab-improvement`, open PR |

No package installation required. This is a pure YAML config change.

---

## Architecture Patterns

### FluxCD `dependsOn` — Exact Syntax (verified from live cluster)

`databases.yaml` in this cluster already uses this pattern. The `apps.yaml` change mirrors it exactly:

```yaml
# Source: clusters/staging/databases.yaml (live in cluster, verified working)
spec:
  dependsOn:
    - name: infrastructure-controllers  # Wait for CloudNativePG operator
```

The `apps.yaml` equivalent:

```yaml
spec:
  dependsOn:
    - name: databases
```

### Full Target State of `apps.yaml`

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 1m0s
  dependsOn:
    - name: databases
  retryInterval: 1m
  timeout: 5m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./apps/staging
  prune: true
  decryption:
      provider: sops
      secretRef:
        name: sops-age
```

Changes from current state:
1. Remove the two commented lines: `# dependsOn:` and `#   - name: infra-configs`
2. Add uncommented `dependsOn:` block with `- name: databases`

### Dependency Chain After Fix

```
infrastructure-controllers  (wait: true, healthChecks: cert-manager)
        ↓
    databases               (wait: true, healthChecks: cnpg-controller-manager, dependsOn: infrastructure-controllers)
        ↓
      apps                  (dependsOn: databases)  ← THIS PHASE
```

### Anti-Patterns to Avoid
- **Keeping the old commented block:** Remove the `# dependsOn: / # - name: infra-configs` lines entirely. Dead commented config is misleading.
- **Adding `wait: true` or healthChecks to `apps`:** Explicitly deferred. The `dependsOn` alone is sufficient for this phase.
- **Depending on `infra-configs` instead of `databases`:** `infra-configs` is a different kustomization (infrastructure configs, not databases). The race condition is with databases.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Dependency ordering | Init containers, custom startup scripts, sleep loops | FluxCD `dependsOn` | Native FluxCD feature; kustomize-controller resolves the graph before applying |
| YAML validation | Manual review | `kubectl apply --dry-run=client` | Catches API field errors, type mismatches |

---

## Common Pitfalls

### Pitfall 1: `flux reconcile --dry-run` Does Not Exist
**What goes wrong:** CONTEXT.md D-04 says to use `flux reconcile kustomization apps --dry-run`. Running this returns `✗ unknown flag: --dry-run`. The plan must NOT include this command.
**Why it happens:** FluxCD's `reconcile` command triggers actual reconciliation; it has no dry-run mode.
**How to avoid:** Use `kubectl apply -f clusters/staging/apps.yaml --dry-run=client` instead. This validates the Kubernetes manifest schema and field names without applying.
**Warning signs:** If a plan step includes `flux reconcile ... --dry-run`, it will fail.

### Pitfall 2: `flux get kustomizations` Does Not Show `dependsOn` Column
**What goes wrong:** CONTEXT.md D-05 says "confirm with `flux get kustomizations` that the dependency graph shows `apps` → `databases`". The `flux get kustomizations` output only shows REVISION, SUSPENDED, READY, MESSAGE — it does not have a dependsOn column.
**Why it happens:** The flux CLI table output does not expose spec fields.
**How to avoid:** Verify with `kubectl get kustomization apps -n flux-system -o jsonpath='{.spec.dependsOn}'`. After the change is applied, this should return `[{"name":"databases"}]`. This is the correct post-merge verification command.
**Confirmed baseline:** Currently returns empty (no dependsOn). After fix it should return `[{"name":"databases"}]`.

### Pitfall 3: Branch Target
**What goes wrong:** Branching off `main` instead of `feat/homelab-improvement`.
**Why it happens:** Default git workflow branches from main.
**How to avoid:** STATE.md and CONTEXT.md both specify: `feat/phase-N-<slug>` off `feat/homelab-improvement`. The correct branch name is `feat/phase-1-fix-fluxcd-bootstrap-race-condition` (or similar slug), created from `feat/homelab-improvement`.

---

## Code Examples

### Pre-merge Validation (correct command)
```bash
# Source: verified locally against live cluster
kubectl apply -f clusters/staging/apps.yaml --dry-run=client
# Expected output: kustomization.kustomize.toolkit.fluxcd.io/apps configured (dry run)
```

### Post-merge Verification (correct command)
```bash
# Source: verified locally — databases.yaml already uses this pattern
kubectl get kustomization apps -n flux-system -o jsonpath='{.spec.dependsOn}'
# Expected output after change applied: [{"name":"databases"}]
# Current output (before change): (empty)
```

### Force Reconcile After Merge (non-dry-run, triggers actual sync)
```bash
flux reconcile kustomization apps --with-source
```

### Check All Kustomizations Are Healthy
```bash
flux get kustomizations
# All kustomizations should show READY=True after dependency change
```

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|---------|
| FluxCD CLI (flux) | Post-merge verification, reconcile trigger | Yes | v2.5.1 | kubectl describe kustomization |
| kubectl | Dry-run validation, post-apply inspection | Yes | in-cluster kubeconfig | — |
| git / gh CLI | Branch creation, PR | Yes | system | — |
| Live cluster access | Verification | Yes | K3s v1.30.0+k3s1 | — |

No missing dependencies. All tools confirmed available.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | kubectl dry-run (no unit test framework — pure YAML change) |
| Config file | none |
| Quick run command | `kubectl apply -f clusters/staging/apps.yaml --dry-run=client` |
| Full suite command | `flux get kustomizations` (all READY=True after merge) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CRIT-01 | `apps` kustomization has `dependsOn: databases` in live cluster | smoke | `kubectl get kustomization apps -n flux-system -o jsonpath='{.spec.dependsOn}'` | N/A — cluster state check |

### Sampling Rate
- **Per task commit:** `kubectl apply -f clusters/staging/apps.yaml --dry-run=client`
- **Phase gate:** `kubectl get kustomization apps -n flux-system -o jsonpath='{.spec.dependsOn}'` returns `[{"name":"databases"}]`

### Wave 0 Gaps
None — no test files to create. Validation is purely cluster state inspection.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Init containers / sleep loops for startup ordering | FluxCD `dependsOn` in Kustomization spec | FluxCD v0.x → v1 | Declarative ordering; controller resolves graph before applying |
| `flux reconcile --dry-run` (never existed) | `kubectl apply --dry-run=client` | N/A | Correct validation path for Kustomization manifests |

---

## Open Questions

1. **Should a comment be added to `apps.yaml` explaining why `databases` is the dependency?**
   - What we know: CONTEXT.md leaves this to Claude's discretion.
   - What's unclear: Whether future maintainers need the context inline.
   - Recommendation: Add a short inline comment `# Wait for CloudNativePG databases to be ready` mirroring the style in `databases.yaml`. Low cost, high clarity.

---

## Sources

### Primary (HIGH confidence)
- Live cluster — `flux version` output: FluxCD v2.5.1, kustomize-controller v1.5.1
- Live cluster — `kubectl get kustomization databases -n flux-system -o jsonpath='{.spec.dependsOn}'` → `[{"name":"infrastructure-controllers"}]` (pattern verified working)
- Live cluster — `kubectl apply -f clusters/staging/apps.yaml --dry-run=client` → `configured (dry run)` (current file is valid)
- Live cluster — `flux reconcile kustomization --help` → confirms `--dry-run` flag does not exist
- `clusters/staging/databases.yaml` — reference YAML for correct `dependsOn` syntax
- `clusters/staging/apps.yaml` — current state of file being modified

### Secondary (MEDIUM confidence)
- FluxCD docs: https://fluxcd.io/docs/components/kustomize/kustomizations/#dependencies — `dependsOn` documented as `[]meta.NamespacedObjectReference`

---

## Project Constraints (from CLAUDE.md)

| Directive | Applies to This Phase |
|-----------|----------------------|
| Never commit directly to main | Yes — use `feat/phase-1-...` branch off `feat/homelab-improvement` |
| All secrets must be SOPS-encrypted | Not applicable — no secrets in this change |
| Test with `kubectl apply -k ... --dry-run=client` first | Adapted: use `kubectl apply -f` (single file, not kustomization dir) |
| Follow base/overlay pattern | Not applicable — modifying cluster-level FluxCD orchestration, not app base/overlay |
| Open PR via `gh pr create` | Yes — PR targets `feat/homelab-improvement` (not main directly) |

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools confirmed in live cluster
- Architecture (dependsOn syntax): HIGH — verified from live working example in same cluster
- Pitfalls (dry-run flag): HIGH — verified empirically against flux v2.5.1
- Pitfalls (flux get output format): HIGH — verified empirically
- Branch target: HIGH — documented in both STATE.md and CONTEXT.md

**Research date:** 2026-04-04
**Valid until:** 2026-05-04 (FluxCD API is stable; low risk of change)
