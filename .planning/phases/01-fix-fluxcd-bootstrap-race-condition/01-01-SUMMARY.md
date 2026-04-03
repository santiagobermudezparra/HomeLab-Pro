---
phase: 01-fix-fluxcd-bootstrap-race-condition
plan: 01
subsystem: infra
tags: [fluxcd, kustomization, gitops, bootstrap, dependsOn]

# Dependency graph
requires: []
provides:
  - "FluxCD apps Kustomization with dependsOn: databases, completing the bootstrap dependency chain"
affects:
  - 02-resource-limits-audiobookshelf
  - all future phases (cluster bootstrap ordering now correct)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "FluxCD Kustomization dependsOn pattern: infrastructure-controllers -> databases -> apps"

key-files:
  created: []
  modified:
    - clusters/staging/apps.yaml

key-decisions:
  - "Target dependency is databases (not infra-configs — that name no longer exists)"
  - "No wait: true or healthChecks added to apps.yaml — out of scope for this phase"
  - "PR opened against feat/homelab-improvement per CLAUDE.md branch workflow"

patterns-established:
  - "FluxCD bootstrap chain: infrastructure-controllers -> databases -> apps"

requirements-completed: [CRIT-01]

# Metrics
duration: 1min
completed: 2026-04-04
---

# Phase 01 Plan 01: Fix FluxCD Bootstrap Race Condition Summary

**Active `dependsOn: [{name: databases}]` block added to `clusters/staging/apps.yaml`, completing the bootstrap chain `infrastructure-controllers -> databases -> apps` and eliminating the app-vs-database race condition on cold cluster boot.**

## Performance

- **Duration:** 1 min
- **Started:** 2026-04-03T23:23:27Z
- **Completed:** 2026-04-03T23:24:30Z
- **Tasks:** 1 of 1
- **Files modified:** 1

## Accomplishments
- Removed stale commented-out `# dependsOn: infra-configs` block from `clusters/staging/apps.yaml`
- Added active `dependsOn: [{name: databases}]` entry so apps wait for CloudNativePG clusters before starting
- Validated with `kubectl apply -f clusters/staging/apps.yaml --dry-run=client` (exit 0, confirmed `configured (dry run)`)
- Pushed feature branch `feat/phase-1-fix-fluxcd-bootstrap-race-condition` to remote

## Task Commits

Each task was committed atomically:

1. **Task 1: Add dependsOn: databases to apps Kustomization and open PR** - `0686e8e` (fix)

**Plan metadata:** (pending — docs commit after this summary)

## Files Created/Modified
- `clusters/staging/apps.yaml` - Replaced commented-out `# dependsOn: infra-configs` with active `dependsOn: [{name: databases}]`

## Decisions Made
- **databases as dependency target (not infra-configs):** The stale comment referenced `infra-configs` which no longer exists in the cluster. The correct target is `databases`, which already depends on `infrastructure-controllers` — creating the correct 3-stage chain.
- **No wait: true or healthChecks:** Per D-03, these are out of scope for this phase. The minimal one-line change is sufficient to fix the race condition.
- **PR against feat/homelab-improvement:** Per CLAUDE.md and STATE.md branch convention — never commit directly to main.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

**GitHub CLI not authenticated (auth gate):** `gh pr create` returned exit code 4 (`gh auth login` required). The code change is fully committed and pushed. The PR must be opened manually or after `gh auth login`.

PR details for manual creation:
- Base: `feat/homelab-improvement`
- Head: `feat/phase-1-fix-fluxcd-bootstrap-race-condition`
- Title: `fix: add dependsOn databases to apps Kustomization`
- Body: "Adds `dependsOn: [{name: databases}]` to `clusters/staging/apps.yaml`, completing the bootstrap dependency chain: `infrastructure-controllers` -> `databases` -> `apps`. Prevents app pods from racing database provisioning on cold cluster boot. Removes the stale commented-out `infra-configs` block."

## User Setup Required

**Manual PR creation required** (GitHub CLI not authenticated):

```bash
gh auth login
gh pr create \
  --base feat/homelab-improvement \
  --head feat/phase-1-fix-fluxcd-bootstrap-race-condition \
  --title "fix: add dependsOn databases to apps Kustomization" \
  --body "Adds dependsOn: [{name: databases}] to clusters/staging/apps.yaml, completing the bootstrap dependency chain: infrastructure-controllers -> databases -> apps. Prevents app pods from racing database provisioning on cold cluster boot. Removes the stale commented-out infra-configs block."
```

After PR is merged, verify the live cluster state:
```bash
kubectl get kustomization apps -n flux-system -o jsonpath='{.spec.dependsOn}'
# Expected: [{"name":"databases"}]

flux get kustomizations
# Expected: all kustomizations show READY=True
```

## Next Phase Readiness
- Bootstrap race condition is fixed — apps will no longer crash-loop on fresh cluster boot
- Phase 02 (Resource Limits for audiobookshelf) can proceed independently — no blockers from this phase
- Pending: PR merge + FluxCD reconciliation to fully apply the change to the live cluster

---
*Phase: 01-fix-fluxcd-bootstrap-race-condition*
*Completed: 2026-04-04*
