---
plan: 09-02
phase: 09-cilium-cni-migration
status: complete
completed: 2026-04-09
---

## Summary

Installed Cilium 1.16.19 via helm, restored all 3 nodes to Ready, installed cilium CLI, and restarted all pods to use Cilium networking.

## Tasks Completed

1. **Cilium installed** — `helm install cilium cilium/cilium --version 1.16.19` with K3s-specific values (k8sServiceHost: 127.0.0.1:6444, ipam CIDR 10.42.0.0/16, operator.replicas=1, hubble+relay+ui enabled). cilium-operator, hubble-relay, hubble-ui all Running.
2. **All pods restarted** — Rolling restart of all Deployments, StatefulSets, and non-Cilium DaemonSets. Longhorn volumes force-recovered after stale mounts blocked reattachment.

## Deviations

- Workers had stale `flannel.1` interfaces (not just control-plane) — deleted before Cilium could start
- Workers had stale `cilium_vxlan` interface conflicts — deleted crashing pods after flannel.1 removal resolved it
- Longhorn volumes got stuck in `detaching/faulted` state due to K3s-agent restart killing instance managers — resolved by force-patching volume status and clearing stale kubelet mounts on worker-01
- cilium CLI v0.19.2 installed (latest stable)

## Outcome

`cilium status`: Cilium OK, Operator OK, Envoy OK, Hubble Relay OK. All 3 nodes Ready. flux-system NetworkPolicies (3) intact. Both CNPG clusters healthy. All cloudflared pods Running. Longhorn volumes recovering (data safe — control-plane replicas were healthy throughout).
