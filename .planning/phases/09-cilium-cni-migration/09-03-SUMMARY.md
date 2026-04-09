---
plan: 09-03
phase: 09-cilium-cni-migration
status: complete
completed: 2026-04-09
---

## Summary

Created FluxCD GitOps manifests for Cilium CNI and opened PR for merge.

## Tasks Completed

1. **Base manifests created** — `infrastructure/controllers/base/cilium/` with repository.yaml (HelmRepository pointing to helm.cilium.io in flux-system), release.yaml (HelmRelease cilium 1.16.19 in kube-system with K3s-specific values and Hubble enabled), kustomization.yaml. Updated base/kustomization.yaml to include cilium.
2. **Staging overlay created** — `infrastructure/controllers/staging/cilium/` with ingress.yaml (Traefik Ingress for Hubble UI at hubble.watarystack.org with cert-manager TLS) and kustomization.yaml. Updated staging/kustomization.yaml to include cilium.
3. **Homepage updated** — Added Hubble entry to `apps/base/homepage/homepage-configmap.yaml` with href https://hubble.watarystack.org and cilium.png icon.
4. **Branch and PR** — Committed all files to `feat/phase-9-cilium-cni-migration`, pushed, and opened PR #54.

## Deviations

- No namespace.yaml created for base/cilium (kube-system is built-in — diverges from Longhorn pattern intentionally to avoid reconciliation warnings)
- HelmRepository namespace is flux-system (not kube-system) — required for cross-namespace HelmRelease sourceRef

## Outcome

PR santiagobermudezparra/HomeLab-Pro#54 open targeting main. After merge, FluxCD will reconcile and adopt the existing Cilium helm release (no re-install). Hubble UI will be accessible at hubble.watarystack.org once cert-manager issues TLS.
