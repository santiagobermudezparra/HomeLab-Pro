---
plan: 11-01
phase: 11
wave: 1
depends_on: []
autonomous: true
files_modified:
  - infrastructure/controllers/base/velero/namespace.yaml
  - infrastructure/controllers/base/velero/repository.yaml
  - infrastructure/controllers/base/velero/release.yaml
  - infrastructure/controllers/base/velero/network-policy.yaml
  - infrastructure/controllers/base/velero/kustomization.yaml
  - infrastructure/controllers/staging/velero/credentials-secret.yaml
  - infrastructure/controllers/staging/velero/kustomization.yaml
  - infrastructure/controllers/staging/kustomization.yaml
requirements:
  - BACK-03

must_haves:
  truths:
    - "Velero pods are Running in the velero namespace"
    - "Velero can reach Cloudflare R2 (backup storage location shows Available)"
    - "velero backup create --from-schedule or ad-hoc backup succeeds without error"
    - "The velero namespace has NetworkPolicies (default-deny-ingress + allow-monitoring)"
    - "S3 credentials are SOPS-encrypted — no plaintext credentials in git"
  artifacts:
    - path: "infrastructure/controllers/base/velero/release.yaml"
      provides: "Velero HelmRelease wired to vmware-tanzu Helm chart"
      exports: ["HelmRelease/velero"]
    - path: "infrastructure/controllers/base/velero/repository.yaml"
      provides: "HelmRepository pointing to charts.vmware-tanzu.com/community-edition"
      exports: ["HelmRepository/velero"]
    - path: "infrastructure/controllers/staging/velero/credentials-secret.yaml"
      provides: "SOPS-encrypted Secret with Cloudflare R2 access key + secret key"
    - path: "infrastructure/controllers/base/velero/network-policy.yaml"
      provides: "default-deny-ingress + allow-monitoring for velero namespace"
  key_links:
    - from: "infrastructure/controllers/base/velero/release.yaml"
      to: "infrastructure/controllers/staging/velero/credentials-secret.yaml"
      via: "HelmRelease values.configuration.backupStorageLocation.credential.name referencing secret"
      pattern: "credential.*name.*velero-s3-credentials"
    - from: "infrastructure/controllers/staging/velero/kustomization.yaml"
      to: "infrastructure/controllers/base/velero/"
      via: "kustomize resources: ../../base/velero/"
      pattern: "../../base/velero/"
    - from: "infrastructure/controllers/staging/kustomization.yaml"
      to: "infrastructure/controllers/staging/velero/"
      via: "resources: - velero"
      pattern: "- velero"
---

<objective>
Install Velero v1.15 via FluxCD HelmRelease in the `velero` namespace, configured with Cloudflare R2 as the S3-compatible backup storage location. The SOPS-encrypted credentials secret is created in the staging overlay, and the velero namespace receives NetworkPolicies matching the Phase 10 baseline pattern.

Purpose: Establish the backup control plane. Without Velero installed and connected to R2, no backup schedules can run (Plan 02 depends on this).
Output: Running Velero deployment + node-agent DaemonSet, BackupStorageLocation status Available, NetworkPolicies in velero namespace.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md

<!-- Phase 10 established NetworkPolicy baseline pattern — replicate for velero namespace -->
@.planning/phases/10-networkpolicies-per-namespace-isolation/10-01-SUMMARY.md
</context>

<interfaces>
<!-- Key patterns extracted from existing infrastructure controllers. Executor replicates these exactly. -->

From infrastructure/controllers/base/longhorn/namespace.yaml:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: longhorn-system
```

From infrastructure/controllers/base/longhorn/repository.yaml:
```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: longhorn
  namespace: longhorn-system
spec:
  interval: 24h
  url: https://charts.longhorn.io
```

From infrastructure/controllers/base/longhorn/release.yaml (HelmRelease structure):
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: longhorn
  namespace: longhorn-system
spec:
  interval: 30m
  chart:
    spec:
      chart: longhorn
      version: "1.7.3"
      sourceRef:
        kind: HelmRepository
        name: longhorn
        namespace: longhorn-system
      interval: 12h
  install:
    crds: Create
  upgrade:
    crds: CreateReplace
  values: ...
```

From infrastructure/controllers/staging/longhorn/kustomization.yaml:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: longhorn-system
resources:
  - ../../base/longhorn/
  - ingress.yaml
```

From infrastructure/controllers/staging/kustomization.yaml (current):
```yaml
resources:
  - renovate
  - cert-manager
  - cloudnative-pg
  - longhorn
  - cilium
```

From apps/base/xm-spotify-sync/network-policy.yaml (Phase 10 NetworkPolicy baseline for non-CNPG app):
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: xm-spotify-sync
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: xm-spotify-sync
spec:
  podSelector: {}
  ingress:
  - from:
    - podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring-scraping
  namespace: xm-spotify-sync
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
  policyTypes:
  - Ingress
```

Velero Helm chart details:
- Chart: vmware-tanzu/velero
- Version: 8.x (maps to Velero app v1.15.x — verify latest stable at https://github.com/vmware-tanzu/helm-charts/releases)
- Helm repo URL: https://vmware-tanzu.github.io/helm-charts
- Key HelmRelease values for R2 backend:
```yaml
values:
  configuration:
    backupStorageLocation:
      - name: default
        provider: aws        # Velero AWS plugin handles S3-compatible APIs
        bucket: velero       # R2 bucket name (user must create this in Cloudflare dashboard)
        config:
          region: auto       # Cloudflare R2 uses "auto" region
          s3Url: https://<ACCOUNT_ID>.r2.cloudflarestorage.com
          s3ForcePathStyle: "true"
        credential:
          name: velero-s3-credentials
          key: cloud
    volumeSnapshotLocation:
      - name: default
        provider: aws
        config:
          region: auto
  initContainers:
    - name: velero-plugin-for-aws
      image: velero/velero-plugin-for-aws:v1.11.0
      volumeMounts:
        - mountPath: /target
          name: plugins
  # node-agent (restic/kopia) for PVC backup
  nodeAgent:
    podVolumePath: /var/lib/kubelet/pods
    privileged: true
  # Longhorn PVCs: use file system backup (restic/kopia via node-agent)
  # Enable defaultVolumesToFsBackup so schedules back up PVCs automatically
  defaultVolumesToFsBackup: true
  snapshotEnabled: false   # No CSI snapshot support needed with fs backup
```

Secret format that Velero AWS plugin expects (key named "cloud"):
```
[default]
aws_access_key_id=<R2_ACCESS_KEY_ID>
aws_secret_access_key=<R2_SECRET_ACCESS_KEY>
```
This is an AWS credentials file format stored as a Kubernetes Secret with key `cloud`.
</interfaces>

<tasks>

<task type="auto">
  <name>Task 1: Create Velero base manifests (namespace, repository, release, network-policy, kustomization)</name>
  <read_first>
    - infrastructure/controllers/base/longhorn/namespace.yaml (namespace pattern)
    - infrastructure/controllers/base/longhorn/repository.yaml (HelmRepository pattern)
    - infrastructure/controllers/base/longhorn/release.yaml (HelmRelease pattern)
    - infrastructure/controllers/base/longhorn/kustomization.yaml (base kustomization pattern)
    - apps/base/xm-spotify-sync/network-policy.yaml (NetworkPolicy baseline pattern from Phase 10)
  </read_first>
  <files>
    infrastructure/controllers/base/velero/namespace.yaml,
    infrastructure/controllers/base/velero/repository.yaml,
    infrastructure/controllers/base/velero/release.yaml,
    infrastructure/controllers/base/velero/network-policy.yaml,
    infrastructure/controllers/base/velero/kustomization.yaml
  </files>
  <action>
Create `infrastructure/controllers/base/velero/` directory with 5 files:

**namespace.yaml** — namespace `velero` (mirrors longhorn-system pattern):
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: velero
```

**repository.yaml** — HelmRepository for vmware-tanzu charts:
```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: velero
  namespace: velero
spec:
  interval: 24h
  url: https://vmware-tanzu.github.io/helm-charts
```

**release.yaml** — HelmRelease for Velero v1.15 with Cloudflare R2 backend and node-agent for filesystem-based PVC backup. Use version `8.x` (Helm chart) which ships Velero v1.15.x. The `initContainers` adds `velero-plugin-for-aws:v1.11.0` for S3/R2 support. Set `defaultVolumesToFsBackup: true` so backup schedules capture Longhorn PVC data via kopia. Set `snapshotEnabled: false` (no CSI VolumeSnapshot provider needed). The `s3Url` uses a placeholder `https://PLACEHOLDER_ACCOUNT_ID.r2.cloudflarestorage.com` that the staging overlay patches with the real account ID via a strategic merge patch OR simply put the real URL value inline in the base (the account ID is not sensitive — only access keys are). Keep s3Url in the base as a patch target:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: velero
  namespace: velero
spec:
  interval: 30m
  chart:
    spec:
      chart: velero
      version: "8.x"
      sourceRef:
        kind: HelmRepository
        name: velero
        namespace: velero
      interval: 12h
  install:
    crds: Create
  upgrade:
    crds: CreateReplace
  values:
    initContainers:
      - name: velero-plugin-for-aws
        image: velero/velero-plugin-for-aws:v1.11.0
        volumeMounts:
          - mountPath: /target
            name: plugins
    configuration:
      backupStorageLocation:
        - name: default
          provider: aws
          bucket: velero
          config:
            region: auto
            s3Url: https://ACCOUNT_ID_PLACEHOLDER.r2.cloudflarestorage.com
            s3ForcePathStyle: "true"
          credential:
            name: velero-s3-credentials
            key: cloud
      volumeSnapshotLocation:
        - name: default
          provider: aws
          config:
            region: auto
    nodeAgent:
      podVolumePath: /var/lib/kubelet/pods
      privileged: true
    defaultVolumesToFsBackup: true
    snapshotEnabled: false
```

NOTE: The executor must look up the actual Cloudflare R2 account ID from the existing CNPG/SOPS secrets in the cluster OR ask the user. The account ID is in the R2 endpoint URL format. It is NOT sensitive. Check `databases/staging/linkding/` or `databases/staging/n8n/` for existing barmanObjectStore s3 config to find the account ID already in use.

**network-policy.yaml** — Replicate Phase 10 baseline pattern for velero namespace (default-deny-ingress + allow-same-namespace + allow-monitoring-scraping), namespace is `velero`. Velero node-agent pods communicate with the velero server within the same namespace, so allow-same-namespace covers this:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: velero
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: velero
spec:
  podSelector: {}
  ingress:
  - from:
    - podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring-scraping
  namespace: velero
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
  policyTypes:
  - Ingress
```

**kustomization.yaml** — Base kustomization listing all 4 resource files:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - repository.yaml
  - release.yaml
  - network-policy.yaml
```
  </action>
  <verify>
    <automated>kustomize build infrastructure/controllers/base/velero/ 2>&1 | grep -E "kind:|name:" | head -20</automated>
  </verify>
  <acceptance_criteria>
    - `kustomize build infrastructure/controllers/base/velero/` produces 6 resources: Namespace/velero, HelmRepository/velero, HelmRelease/velero, and 3 NetworkPolicy objects
    - HelmRelease references HelmRepository `velero` in namespace `velero`
    - network-policy.yaml has all 3 policies with namespace: velero
    - No plaintext credentials anywhere in these files
  </acceptance_criteria>
  <done>5 files exist in infrastructure/controllers/base/velero/, kustomize build succeeds with no errors, 6 Kubernetes resources output</done>
</task>

<task type="auto">
  <name>Task 2: Create staging overlay with SOPS-encrypted R2 credentials and wire into controller hierarchy</name>
  <read_first>
    - infrastructure/controllers/staging/longhorn/kustomization.yaml (staging overlay pattern)
    - infrastructure/controllers/staging/kustomization.yaml (top-level staging kustomization to update)
    - clusters/staging/.sops.yaml (age public key for encryption)
    - databases/staging/linkding/ or databases/staging/n8n/ (find existing R2 account ID / endpoint already in use)
  </read_first>
  <files>
    infrastructure/controllers/staging/velero/credentials-secret.yaml,
    infrastructure/controllers/staging/velero/kustomization.yaml,
    infrastructure/controllers/staging/kustomization.yaml
  </files>
  <action>
Create `infrastructure/controllers/staging/velero/` directory with 2 files, then update the top-level staging kustomization.

**Step 1 — Look up R2 account ID:**
Check existing barman/R2 config in the CNPG databases staging directory to find the R2 endpoint URL already in use (or ask user if not found). The account ID is the subdomain portion of `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`.

**Step 2 — Create credentials-secret.yaml in PLAINTEXT first:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: velero-s3-credentials
  namespace: velero
stringData:
  cloud: |
    [default]
    aws_access_key_id=PLACEHOLDER_ACCESS_KEY
    aws_secret_access_key=PLACEHOLDER_SECRET_KEY
```
Replace PLACEHOLDER values with actual Cloudflare R2 API token key ID and secret. If the user has not yet created an R2 API token for Velero, pause and note this in the task output — the user must create an R2 API token in the Cloudflare dashboard with "Object Storage: Edit" permission scoped to the `velero` bucket (which must also be created). The token key ID and secret go into the credentials file.

**Step 3 — SOPS-encrypt the credentials-secret.yaml:**
```bash
sops --age=age1spwc8lctzldd0ghkkls8jfvzzra7cx95r2zqq6eya84etq65wfgqy2h99p \
  --encrypt --encrypted-regex '^(data|stringData)$' \
  --in-place infrastructure/controllers/staging/velero/credentials-secret.yaml
```
Verify the file now contains `ENC[AES256_GCM` in the stringData field.

**Step 4 — Create kustomization.yaml for staging overlay:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: velero
resources:
  - ../../base/velero/
  - credentials-secret.yaml
patches:
  - patch: |-
      - op: replace
        path: /spec/values/configuration/backupStorageLocation/0/config/s3Url
        value: https://ACTUAL_ACCOUNT_ID.r2.cloudflarestorage.com
    target:
      kind: HelmRelease
      name: velero
```
Replace ACTUAL_ACCOUNT_ID with the real Cloudflare R2 account ID found in Step 1 or provided by user. The patch is a JSON6902 patch on the HelmRelease to replace the placeholder s3Url with the real endpoint.

**Step 5 — Add velero to top-level staging kustomization:**
Edit `infrastructure/controllers/staging/kustomization.yaml`, append `- velero` to the resources list:
```yaml
resources:
  - renovate
  - cert-manager
  - cloudnative-pg
  - longhorn
  - cilium
  - velero
```

IMPORTANT: The R2 bucket named `velero` must exist in Cloudflare R2 before Velero starts. Note this as a prerequisite in the task output for the user.
  </action>
  <verify>
    <automated>grep -c "ENC\[AES256_GCM" infrastructure/controllers/staging/velero/credentials-secret.yaml && grep "velero" infrastructure/controllers/staging/kustomization.yaml</automated>
  </verify>
  <acceptance_criteria>
    - `infrastructure/controllers/staging/velero/credentials-secret.yaml` contains `ENC[AES256_GCM` (SOPS-encrypted)
    - `infrastructure/controllers/staging/kustomization.yaml` includes `- velero` in resources
    - `infrastructure/controllers/staging/velero/kustomization.yaml` references both `../../base/velero/` and `credentials-secret.yaml`
    - `kustomize build infrastructure/controllers/staging/velero/` succeeds (SOPS decrypt step skipped in dry-run, but build must not fail on structure)
    - No plaintext access keys visible anywhere in git-tracked files
  </acceptance_criteria>
  <done>Staging overlay exists, credentials SOPS-encrypted, velero wired into staging controller kustomization</done>
</task>

</tasks>

<verification>
After both tasks:
1. `kustomize build infrastructure/controllers/base/velero/` — must output 5+ resources with no errors
2. `grep "ENC\[AES256_GCM" infrastructure/controllers/staging/velero/credentials-secret.yaml` — must return a match
3. `grep velero infrastructure/controllers/staging/kustomization.yaml` — must show `- velero`
4. `kustomize build infrastructure/controllers/staging/velero/ 2>&1` — structure valid (SOPS decryption skipped in dry-run is acceptable)
5. `git diff --name-only` shows only the expected new/modified files
</verification>

<success_criteria>
- All 7 new files exist with correct content
- `infrastructure/controllers/staging/kustomization.yaml` includes `velero`
- SOPS encryption confirmed on credentials-secret.yaml
- No plaintext secrets committed
- PR opened on feat/phase-11-velero branch
</success_criteria>

<output>
After completion, create `.planning/phases/11-velero-full-backup/11-01-SUMMARY.md` following the standard summary template.
</output>
