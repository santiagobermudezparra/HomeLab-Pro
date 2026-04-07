---
phase: 9
slug: cilium-cni-migration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-07
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | kubectl / cilium CLI / hubble CLI (infrastructure verification) |
| **Config file** | none — cluster-level verification commands |
| **Quick run command** | `cilium status --wait=false` |
| **Full suite command** | `cilium status && kubectl get pods --all-namespaces \| grep -v Running \| grep -v Completed` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cilium status --wait=false`
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 9-01-01 | 01 | 1 | SEC-01 | manual | `cat /etc/rancher/k3s/config.yaml \| grep flannel-backend` | ✅ | ⬜ pending |
| 9-01-02 | 01 | 1 | SEC-01 | manual | `ip link show flannel.1 2>&1 \| grep 'does not exist'` | ✅ | ⬜ pending |
| 9-02-01 | 02 | 2 | SEC-01 | cli | `cilium status --wait=false \| grep 'OK'` | ✅ | ⬜ pending |
| 9-02-02 | 02 | 2 | SEC-01 | cli | `kubectl get pods -n kube-system \| grep cilium \| grep Running` | ✅ | ⬜ pending |
| 9-03-01 | 03 | 3 | SEC-01 | gitops | `kubectl get helmrelease -n kube-system cilium` | ✅ | ⬜ pending |
| 9-03-02 | 03 | 3 | SEC-02 | cli | `hubble status \| grep 'Flows'` | ✅ | ⬜ pending |
| 9-04-01 | 04 | 4 | SEC-02 | manual | `kubectl get ingress -n kube-system hubble-ui` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements — this is a cluster-level migration with CLI-based verification.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| K3s flannel disabled on control plane | SEC-01 | Requires SSH to node | SSH to control node, verify `/etc/rancher/k3s/config.yaml` has `flannel-backend: none` and `disable-network-policy: true` |
| `flannel.1` interface removed | SEC-01 | Requires SSH to each node | SSH to each node, run `ip link show flannel.1` should return error |
| All app pods reach Running after CNI swap | SEC-01 | External tunnel reachability | Open each app URL via Cloudflare Tunnel; verify accessible |
| Hubble flows visible | SEC-02 | CLI tool required | Run `hubble observe --last 20` and verify flow entries appear |
| flux-system NetworkPolicies still function | SEC-01 | FluxCD reconciliation | Run `flux reconcile kustomization apps` and confirm successful sync |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
