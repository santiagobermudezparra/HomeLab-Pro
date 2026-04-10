---
phase: 10-networkpolicies-per-namespace-isolation
plan: "02"
subsystem: skill
tags: [kubernetes, networkpolicy, skill, documentation, pr]

# Dependency graph
requires:
  - 10-01 (NetworkPolicy manifests must exist before skill update and PR)
provides:
  - Updated homelab-app-onboarding SKILL.md with Step 2.6
  - Feature branch feat/phase-10-networkpolicies with all Phase 10 changes
  - PR #58 targeting main for review and FluxCD adoption
affects:
  - All future app onboarding sessions (skill now teaches NetworkPolicy creation)
  - Phase 10 completion (PR must be merged for FluxCD to enforce isolation)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SKILL.md Step 2.6: 3 NetworkPolicy templates codified for skill users"
    - "Checklist-driven verification: network-policy.yaml items added to onboarding checklist"

key-files:
  created:
    - .planning/phases/10-networkpolicies-per-namespace-isolation/10-01-PLAN.md
    - .planning/phases/10-networkpolicies-per-namespace-isolation/10-02-PLAN.md
  modified:
    - .claude/skills/homelab-app-onboarding/SKILL.md

key-decisions:
  - "Branch feat/phase-10-networkpolicies created off fix/prometheus-servicemonitors (not main) because the monitoring fixes and all 8 network-policy.yaml files already live on that branch — bundling everything into one PR"
  - "PR #58 includes both monitoring fixes (d6bc20b) and NetworkPolicy work — clean single review for all Phase 10 hardening"
  - "SKILL.md Step 2.6 uses Template A/B/C naming to clearly distinguish cloudflared-only, CNPG, and Traefik variants without ambiguity"

# Metrics
duration: 2min
completed: 2026-04-10
---

# Phase 10 Plan 02: Skill Update and PR Summary

**Homelab-app-onboarding SKILL.md updated with Step 2.6 (3 NetworkPolicy templates), plan files committed, feature branch feat/phase-10-networkpolicies created and pushed, PR #58 opened targeting main**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-04-10T23:03:50Z
- **Completed:** 2026-04-10T23:05:23Z
- **Tasks:** 2
- **Files modified:** 3 (1 modified, 2 created)

## Accomplishments

- Updated SKILL.md with Step 2.6 inserted between Step 2.5 (CloudNativePG) and Step 3 (Staging Overlay)
- Step 2.6 provides 3 complete templates with working YAML:
  - Template A: Cloudflare Tunnel access / no database (3 policies — the baseline for most apps)
  - Template B: CNPG database in same namespace (adds allow-cnpg-controller)
  - Template C: Traefik Ingress access (adds allow-traefik-ingress with AND semantics)
- Added kustomization.yaml registration instructions and kustomize validation command
- Updated Checklist Summary with 2 new items for network-policy.yaml verification
- Committed plan files (10-01-PLAN.md, 10-02-PLAN.md) alongside SKILL.md in single atomic commit
- Created branch feat/phase-10-networkpolicies off fix/prometheus-servicemonitors (which holds all Phase 10 work)
- Pushed branch and opened PR #58 targeting main

## Task Commits

| Task | Description | Commit |
|------|-------------|--------|
| Task 1 | Update SKILL.md Step 2.6 + commit plan files | `06aa8e8` |
| Task 2 | Create branch feat/phase-10-networkpolicies + push + open PR #58 | (branch creation, no new commits) |

## PR Details

- **PR #58**: https://github.com/santiagobermudezparra/HomeLab-Pro/pull/58
- **Title**: feat(phase-10): NetworkPolicies — per-namespace isolation
- **Base**: main
- **Head**: feat/phase-10-networkpolicies
- **Commits included**: d6bc20b (monitoring fixes) + b934d7c, 7565680, 9ff0a99, ad68191 (Phase 10 Plan 01) + 06aa8e8 (Plan 02 skill update)

## Decisions Made

- Branched off `fix/prometheus-servicemonitors` (not main) since all Phase 10 network-policy.yaml files and monitoring fixes already existed on that branch — creating one clean PR with all related hardening work
- Template naming (A/B/C) chosen over inline conditional text to keep SKILL.md instructions scannable without heavy if/else prose
- Two checklist items added (not one) to separately verify file creation and kustomization registration — distinct failure modes

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all templates in Step 2.6 are complete YAML, not placeholders. The `${APP_NAME}` variables are intentional template variables for skill users to substitute.

## Post-Merge Actions Required

After PR #58 is merged to main:
1. FluxCD will automatically apply the 8 NetworkPolicy manifests within ~1 minute
2. Verify enforcement: `kubectl get networkpolicies --all-namespaces` should show 3-4 policies per app namespace
3. Test isolation: cross-namespace DB access (e.g., mealie → linkding-postgres) should be blocked

---
*Phase: 10-networkpolicies-per-namespace-isolation*
*Completed: 2026-04-10*
