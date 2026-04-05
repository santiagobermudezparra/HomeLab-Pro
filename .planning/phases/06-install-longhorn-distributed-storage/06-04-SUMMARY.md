---
plan: 06-04
phase: 06-install-longhorn-distributed-storage
status: complete
completed: 2026-04-05
---

## Summary

Permanently demoted `local-path` as default StorageClass by updating K3s server config on the control-plane node and restarting K3s.

## StorageClass state — before

```
NAME                   PROVISIONER             RECLAIMPOLICY  VOLUMEBINDINGMODE     ALLOWVOLUMEEXPANSION  AGE
local-path (default)   rancher.io/local-path   Delete         WaitForFirstConsumer  false                 343d
longhorn (default)     driver.longhorn.io      Delete         Immediate             true                  5m
longhorn-static        driver.longhorn.io      Delete         Immediate             true                  5m
```

## StorageClass state — after

```
NAME                 PROVISIONER          RECLAIMPOLICY  VOLUMEBINDINGMODE  ALLOWVOLUMEEXPANSION  AGE
longhorn (default)   driver.longhorn.io   Delete         Immediate          true                  14m
longhorn-static      driver.longhorn.io   Delete         Immediate          true                  14m
```

`local-path` StorageClass removed. `longhorn` is the sole default.

## K3s config changes

**Control-plane** (`santi-standard-pc-i440fx-piix-1996`, `192.168.1.115`):
```yaml
# /etc/rancher/k3s/config.yaml
disable:
  - helm-controller
  - local-storage   # ← added
```

**Worker nodes**: No config change needed — the `disable` flag is a server-only K3s config option. Workers running as k3s-agent do not process this flag. Config.yaml was briefly created on workers with the `disable` flag but was removed immediately after discovering it caused k3s-agent to fail (`flag provided but not defined: -disable`).

## Node restart sequence

1. Worker 1 (homelab-worker-01, 192.168.1.89): k3s-agent restarted — Ready ✓
2. Worker 2 (homelab-worker-02, 192.168.1.67): k3s-agent restarted — Ready ✓
3. Control-plane: `k3s` service restarted — Ready ✓

All 3 nodes Ready after restart.

## HelmRelease status after restarts

```
NAME       AGE   READY   STATUS
longhorn   14m   True    Helm install succeeded for release longhorn-system/longhorn.v1 with chart longhorn@1.7.3
```

## Human verification

- All automated checks passed
- `local-path` StorageClass removed, `longhorn (default)` only
- Existing local-path PVCs (linkding, audiobookshelf, mealie, n8n, pgadmin, filebrowser) remain Bound — unaffected

## Git commit

No Git files changed — this was a node-level SSH/local config change, not a GitOps file change.
The control-plane config at `/etc/rancher/k3s/config.yaml` was modified directly on the host.
