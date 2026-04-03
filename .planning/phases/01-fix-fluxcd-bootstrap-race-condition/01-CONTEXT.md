# Phase 1: Fix FluxCD Bootstrap Race Condition - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning
**Source:** Derived directly from ROADMAP.md — no gray areas (implementation fully specified)

<domain>
## Phase Boundary

Add `dependsOn: [{ name: databases }]` to `clusters/staging/apps.yaml`, completing the dependency chain `infrastructure-controllers → databases → apps`. This eliminates the bootstrap race condition where apps try to connect to databases that don't yet exist.

Creating/modifying databases, adding healthChecks to apps, or other changes are out of scope.

</domain>

<decisions>
## Implementation Decisions

### Dependency change
- **D-01:** Add `dependsOn: - name: databases` to `clusters/staging/apps.yaml`
- **D-02:** Remove the commented-out `dependsOn: infra-configs` block — replace it with the correct target (`databases`)
- **D-03:** No other fields in `apps.yaml` need to change (no `wait: true`, no healthChecks — that's out of scope for this phase)

### Verification
- **D-04:** Test via `flux reconcile kustomization apps --dry-run` before merging
- **D-05:** Confirm with `flux get kustomizations` that the dependency graph shows `apps` → `databases`

### Done criteria
- **D-06:** Change merged to main via PR — FluxCD applies it on sync

### Claude's Discretion
- Exact PR description wording
- Whether to add a comment in apps.yaml explaining the dependency

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### FluxCD Kustomization dependency config
- `clusters/staging/apps.yaml` — The file being modified; has `dependsOn` commented out, needs fixing
- `clusters/staging/databases.yaml` — Shows correct `dependsOn` + `wait: true` pattern already in use
- `clusters/staging/infrastructure.yaml` — Shows `wait: true` + healthChecks pattern for reference

### Project constraints
- `CLAUDE.md` — Branch convention (`feat/phase-N-<slug>` off `feat/homelab-improvement`), PR workflow, no direct commits to main

</canonical_refs>

<code_context>
## Existing Code Insights

### Current state of apps.yaml
- Has `dependsOn` commented out: `# dependsOn:` / `#   - name: infra-configs`
- Has `retryInterval: 1m`, `timeout: 5m`, `interval: 1m0s`
- Has SOPS decryption configured

### databases.yaml pattern (reference)
- `dependsOn: [{ name: infrastructure-controllers }]`
- `wait: true`
- `healthChecks` for cnpg-controller-manager

### Integration point
- Chain after fix: `infrastructure-controllers` → `databases` → `apps`
- `databases.yaml` already correctly depends on `infrastructure-controllers` — no changes needed there

</code_context>

<deferred>
## Deferred Ideas

- Adding `wait: true` + healthChecks to `apps.yaml` — out of scope for this phase, worth considering later
- `infrastructure-controllers` healthChecks expansion — separate concern

</deferred>

---

*Phase: 01-fix-fluxcd-bootstrap-race-condition*
*Context gathered: 2026-04-04 (derived from ROADMAP.md)*
