---
phase: 03-grafana-admin-password-as-sops-secret
plan: 01
subsystem: infra
tags: [sops, age, grafana, kube-prometheus-stack, secrets, security]

# Dependency graph
requires: []
provides:
  - SOPS-encrypted Kubernetes Secret containing Grafana admin credentials (admin-user, admin-password)
  - HelmRelease updated to reference existingSecret instead of hardcoded adminPassword
  - Kustomization updated to include grafana-admin-secret.yaml
affects: [monitoring, kube-prometheus-stack]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SOPS age encryption for Kubernetes Secrets: kubectl dry-run to generate, sops --encrypt --in-place to seal"
    - "HelmRelease existingSecret pattern for externalizing Grafana credentials"

key-files:
  created:
    - monitoring/configs/staging/kube-prometheus-stack/grafana-admin-secret.yaml
  modified:
    - monitoring/configs/staging/kube-prometheus-stack/kustomization.yaml
    - monitoring/controllers/base/kube-prometheus-stack/release.yaml

key-decisions:
  - "Use grafana.admin.existingSecret (not adminPassword) so HelmRelease contains no credentials"
  - "Secret keys match kube-prometheus-stack chart convention: admin-user and admin-password"
  - "Encrypt with encrypted_regex ^(data|stringData)$ — only data fields sealed, metadata readable"

patterns-established:
  - "SOPS secret pattern: kubectl create secret --dry-run -o yaml | sops --encrypt --in-place"

requirements-completed: [CRIT-04]

# Metrics
duration: 3min
completed: 2026-04-04
---

# Phase 3 Plan 01: Grafana Admin Password as SOPS Secret Summary

**Grafana adminPassword moved from plaintext HelmRelease to SOPS age-encrypted Kubernetes Secret, satisfying CRIT-04 with zero plaintext credentials in git**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-04T10:43:34Z
- **Completed:** 2026-04-04T10:46:30Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created grafana-admin-secret.yaml with admin-user and admin-password keys, SOPS-encrypted via age public key
- Removed `adminPassword: watary` from release.yaml and replaced with `admin.existingSecret: grafana-admin-secret`
- Added grafana-admin-secret.yaml to the monitoring configs kustomization resources list
- Validated kustomize build produces valid YAML output including the encrypted Secret

## Task Commits

Each task was committed atomically:

1. **Task 1: Create and encrypt grafana-admin-secret.yaml, add to kustomization** - `088e0ee` (feat)
2. **Task 2: Update HelmRelease to use existingSecret, remove hardcoded adminPassword** - `b69553d` (feat)

**Plan metadata:** (docs commit follows this summary)

## Files Created/Modified
- `monitoring/configs/staging/kube-prometheus-stack/grafana-admin-secret.yaml` - SOPS-encrypted Secret with admin-user and admin-password keys, namespace: monitoring
- `monitoring/configs/staging/kube-prometheus-stack/kustomization.yaml` - Added grafana-admin-secret.yaml to resources list
- `monitoring/controllers/base/kube-prometheus-stack/release.yaml` - Replaced adminPassword with admin.existingSecret: grafana-admin-secret

## Decisions Made
- Used `grafana.admin.existingSecret` HelmRelease pattern — chart convention for externalizing credentials
- Secret keys `admin-user` and `admin-password` match kube-prometheus-stack Helm chart's expected key names
- Kept the same password value (`watary`) inside the encrypted secret to avoid breaking the running Grafana instance

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

SOPS encryption command used absolute file paths due to worktree setup — `--in-place` requires absolute path when cwd differs from file location. Resolved immediately without code changes.

## User Setup Required

None - no external service configuration required. FluxCD will decrypt the secret automatically at deploy time using the existing `sops-age` secret in `flux-system` namespace.

## Next Phase Readiness
- Phase 03 complete: no plaintext credentials remain in `monitoring/` directory
- Ready for PR merge — FluxCD will apply the HelmRelease change and reference the new SOPS secret
- Grafana will restart on HelmRelease reconciliation and authenticate using the decrypted Secret

## Self-Check: PASSED

- FOUND: monitoring/configs/staging/kube-prometheus-stack/grafana-admin-secret.yaml
- FOUND: monitoring/configs/staging/kube-prometheus-stack/kustomization.yaml
- FOUND: monitoring/controllers/base/kube-prometheus-stack/release.yaml
- FOUND: .planning/phases/03-grafana-admin-password-as-sops-secret/03-01-SUMMARY.md
- FOUND commit: 088e0ee (Task 1)
- FOUND commit: b69553d (Task 2)

---
*Phase: 03-grafana-admin-password-as-sops-secret*
*Completed: 2026-04-04*
