# PRD: Deploy Filebrowser to HomeLab Kubernetes Cluster

## Introduction

Deploy [filebrowser](https://github.com/filebrowser/filebrowser) — a lightweight web-based file manager — to the HomeLab Kubernetes cluster. The primary use case is uploading and downloading files between computers over the internet without needing shared drives or cloud storage. It will be publicly accessible at `filebrowser.watarystack.org` via a Cloudflare Tunnel, protected by secure credentials.

## Goals

- Run filebrowser at `filebrowser.watarystack.org` accessible from any device
- Store uploaded files in a dedicated PVC (`filebrowser-files`, 20Gi) so they persist across pod restarts
- Store the filebrowser database (users, settings) in a separate PVC (`filebrowser-db`, 1Gi)
- Configure filebrowser via a ConfigMap (settings.json) for reproducibility and GitOps compliance
- Protect access with SOPS-encrypted admin credentials (non-guessable username + password)
- Follow the existing base/overlay pattern used by all other apps in this repo
- All secrets SOPS-encrypted before committing; PR opened — never commit to main directly

## User Stories

### US-001: Create Git branch
**Description:** As a developer, I need a feature branch so changes never land directly on main.

**Acceptance Criteria:**
- [ ] Branch `feat/add-filebrowser` created from latest `main`
- [ ] All subsequent commits land on this branch

---

### US-002: Create base Kubernetes manifests
**Description:** As a developer, I need the base manifests so the app can deploy consistently across environments.

**Acceptance Criteria:**
- [ ] `apps/base/filebrowser/namespace.yaml` creates the `filebrowser` namespace
- [ ] `apps/base/filebrowser/storage.yaml` defines two PVCs:
  - `filebrowser-db` — 1Gi, ReadWriteOnce (for filebrowser.db)
  - `filebrowser-files` — 20Gi, ReadWriteOnce (for user-uploaded files)
- [ ] `apps/base/filebrowser/deployment.yaml` deploys `filebrowser/filebrowser:latest` with:
  - Container port 80
  - Volume mounts: `/database` (db PVC) and `/srv` (files PVC)
  - `envFrom` referencing `filebrowser-env-secret` (for admin credentials)
  - Volume mounting ConfigMap as `/config/.filebrowser.json`
  - initContainer that sets correct ownership on `/database` and `/srv`
- [ ] `apps/base/filebrowser/service.yaml` exposes a ClusterIP service on port 8088 → targetPort 80
- [ ] `apps/base/filebrowser/kustomization.yaml` references all base files
- [ ] `kustomize build apps/base/filebrowser/` passes with no errors

---

### US-003: Create staging overlay with ConfigMap
**Description:** As a developer, I need a staging overlay so environment-specific config (tunnel, secrets) is separate from the base.

**Acceptance Criteria:**
- [ ] `apps/staging/filebrowser/filebrowser-config.yaml` ConfigMap contains `settings.json` with:
  - `"port": 80`
  - `"address": "0.0.0.0"`
  - `"root": "/srv"`
  - `"database": "/database/filebrowser.db"`
  - `"log": "stdout"`
  - `"noauth": false`
- [ ] ConfigMap mounted into the deployment at `/config/.filebrowser.json`
- [ ] `apps/staging/filebrowser/kustomization.yaml` references base + all staging resources

---

### US-004: Create and encrypt Cloudflare tunnel secret
**Description:** As a developer, I need the tunnel credentials encrypted so they're safe in Git.

**Acceptance Criteria:**
- [ ] Tunnel `filebrowser` already exists (UUID: `352eee72-576c-4669-9377-a17499aac4ea`)
- [ ] `cloudflare-secret.yaml` created from `~/.cloudflared/352eee72-576c-4669-9377-a17499aac4ea.json`
- [ ] File encrypted with SOPS age key — `data` field shows `ENC[AES256_GCM`
- [ ] Cloudflare ConfigMap + cloudflared Deployment written to `cloudflare.yaml`:
  - Tunnel name: `filebrowser`
  - Ingress: `filebrowser.watarystack.org` → `http://filebrowser:8088`
  - 2 replicas for HA

---

### US-005: Create and encrypt admin credentials secret
**Description:** As a developer, I need the admin username and password encrypted so they're never exposed in Git.

**Acceptance Criteria:**
- [ ] Secret `filebrowser-env-secret` created with:
  - `FB_USERNAME`: non-guessable value (not `admin`)
  - `FB_PASSWORD`: random 28-character alphanumeric string
- [ ] File encrypted with SOPS — `data` field shows `ENC[AES256_GCM`
- [ ] Secret referenced in deployment via `envFrom`

---

### US-006: Wire filebrowser into staging kustomization
**Description:** As a developer, I need the app registered so FluxCD picks it up after merge.

**Acceptance Criteria:**
- [ ] `apps/staging/kustomization.yaml` includes `- filebrowser` in resources list
- [ ] `kustomize build apps/staging/filebrowser/` passes with no errors
- [ ] `kubectl apply -k apps/staging/filebrowser/ --dry-run=client` passes

---

### US-007: Open pull request
**Description:** As a developer, I need a PR so changes are reviewed before hitting the cluster.

**Acceptance Criteria:**
- [ ] All files committed to `feat/add-filebrowser`
- [ ] PR opened against `main` with `gh pr create`
- [ ] PR body includes: image, port, hostname, tunnel name, pre-merge DNS checklist
- [ ] No unencrypted secrets in any committed file (verified by grepping for plaintext passwords)

---

## Functional Requirements

- FR-1: filebrowser runs at container port 80; service exposes it on cluster port 8088
- FR-2: All user-uploaded files stored in `filebrowser-files` PVC mounted at `/srv`
- FR-3: filebrowser database stored in `filebrowser-db` PVC mounted at `/database`
- FR-4: App config delivered via ConfigMap mounted as `/config/.filebrowser.json`
- FR-5: Admin credentials injected via env vars from SOPS-encrypted Kubernetes secret
- FR-6: Cloudflare Tunnel (`filebrowser`, UUID `352eee72-576c-4669-9377-a17499aac4ea`) routes external traffic to `http://filebrowser:8088`
- FR-7: cloudflared deployment runs 2 replicas in the `filebrowser` namespace
- FR-8: All secrets use SOPS encryption with age key `age1spwc8lctzldd0ghkkls8jfvzzra7cx95r2zqq6eya84etq65wfgqy2h99p`
- FR-9: Feature branch `feat/add-filebrowser` and PR opened — no direct commits to `main`

## Non-Goals

- No multi-user setup (single admin account only for now)
- No SSO/OAuth integration
- No custom branding or theming
- No backup automation for PVC data
- No resource quota configuration beyond basic requests/limits
- No Ingress/cert-manager (access is via Cloudflare Tunnel only)

## Technical Considerations

- **Storage pattern**: matches existing apps — two separate PVCs in `storage.yaml`, no storageClassName set (uses cluster default)
- **initContainer**: needed to `chown` the PVC mount points before filebrowser starts (matches n8n pattern)
- **Service port**: 8088 on the service → 80 on the container (so the port doesn't collide with pgadmin's port 80)
- **Config file path**: filebrowser looks for `.filebrowser.json` in the working directory; mount ConfigMap at `/config/.filebrowser.json` and pass `--config /config/.filebrowser.json` as a container arg
- **Credentials**: `FB_USERNAME` and `FB_PASSWORD` env vars set the admin on first run; stored in SOPS secret
- **Tunnel credentials JSON**: `/home/santi/.cloudflared/352eee72-576c-4669-9377-a17499aac4ea.json` — must NOT be committed

## Secure Credentials (SOPS-encrypted, never in plaintext in Git)

| Key | Value |
|-----|-------|
| `FB_USERNAME` | `fa020124_admin` |
| `FB_PASSWORD` | `Adla7fhRkTWQ932oqJBk9dIy4pKG` |

> These values are written here for PRD reference only. In the actual secret file they will be SOPS-encrypted before any `git add`.

## DNS Step (Manual — must be done before testing)

In the Cloudflare dashboard for `watarystack.org`:
- **Type**: CNAME
- **Name**: `filebrowser`
- **Target**: `352eee72-576c-4669-9377-a17499aac4ea.cfargotunnel.com`
- **Proxy**: Proxied (orange cloud)

## Success Metrics

- `filebrowser.watarystack.org` loads the login page from any device on the internet
- Admin can log in with the generated credentials
- Uploading a file from one computer and downloading it from another works end-to-end
- All committed secret files contain only `ENC[AES256_GCM` — no plaintext values
- FluxCD reconciles successfully after PR merge (no errors in `flux get kustomizations`)

## Open Questions

- What size should `filebrowser-files` PVC be? Set to **20Gi** as default for file transfer use case — can be resized later if the StorageClass supports it.
- Should the `filebrowser-files` PVC be `ReadWriteMany` (multi-node access)? Using `ReadWriteOnce` to match all other apps; upgrade to RWX only if pod scheduling becomes an issue.
