# Phase 2: Add Resource Limits — audiobookshelf - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Add Kubernetes resource requests and limits to all app deployments that are currently missing them, so no app can OOM-kill the control-plane node. Audiobookshelf is the primary concern (3 PVCs, media server that can transcode), but homepage, linkding, and mealie are also missing limits and are fixed in the same PR. Audiobookshelf also gets additional content-type volume mounts added in this phase.

</domain>

<decisions>
## Implementation Decisions

### Scope
- **D-01:** Fix all 4 apps missing resource limits in one PR: audiobookshelf, homepage, linkding, mealie.
- **D-02:** filebrowser, n8n, pgadmin, xm-spotify-sync already have limits — do NOT touch them.
- **D-03:** All resource changes go in `apps/base/{app}/deployment.yaml` (matches existing pattern in the repo).

### Audiobookshelf — content type volumes
- **D-04:** Add the following additional volume mounts and corresponding PVCs to audiobookshelf:
  - `/podcasts` — podcast audio files
  - `/ebooks` — ebook files (epub, pdf, etc.)
  - `/comics` — comics and manga
  - `/videos` — video files
  All 4 are new PersistentVolumeClaims using the same `local-path` storage class as the existing 3 PVCs (config, metadata, audiobooks).
- **D-05:** New PVCs go in `apps/base/audiobookshelf/storage.yaml` alongside existing ones.

### Resource values — derived from live `kubectl top pods`
Observed idle usage (no active transcoding):
- audiobookshelf: 1m CPU / 142Mi RAM
- homepage: 1m CPU / 115Mi RAM
- linkding: 1m CPU / 164Mi RAM
- mealie: 3m CPU / 559Mi RAM

- **D-06:** Set requests = observed idle usage (rounded up). Set memory limits generously for apps that can spike:
  - audiobookshelf: requests `10m CPU / 200Mi RAM`, limits `500m CPU / 1.5Gi RAM` — transcoding spikes hard
  - homepage: requests `10m CPU / 128Mi RAM`, limits `200m CPU / 256Mi RAM`
  - linkding: requests `10m CPU / 192Mi RAM`, limits `200m CPU / 384Mi RAM`
  - mealie: requests `50m CPU / 600Mi RAM`, limits `500m CPU / 1.2Gi RAM` — Python app, already high at idle
- **D-07:** CPU limits are set conservatively (not unlimited) to prevent runaway processes from starving the control-plane.

### Image tag pinning (phase 3 dropped)
- **D-08:** Phase 3 (Pin All Image Tags) has been removed. n8n uses `n8nio/n8n:latest` and all cloudflared deployments use `cloudflare/cloudflared:latest`. These are intentionally left as-is — they are working and the user decided not to pin them now.

</decisions>

<specifics>
## Specific Ideas

- audiobookshelf is a transcoding media server — memory limits must be generous enough to avoid OOMKill mid-playback. 1.5Gi headroom is the target.
- mealie was already at 559Mi at idle — its limit needs to be well above 1Gi.
- The user prefers one PR per phase — all 4 apps + audiobookshelf volumes ship together.

</specifics>

<canonical_refs>
## Canonical References

No external specs or ADRs exist for this phase. Requirements are fully captured in decisions above.

### Live cluster data used for sizing
- `kubectl top pods --all-namespaces` — run 2026-04-04, idle cluster, results captured in D-06

### Existing patterns to follow
- `apps/base/filebrowser/deployment.yaml` — reference for resource block format (requests + limits, memory in Mi, cpu in m)
- `apps/base/audiobookshelf/storage.yaml` — reference for PVC format when adding new content-type volumes
- `apps/base/n8n/deployment.yaml` — reference for resource block on a heavier app

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `apps/base/audiobookshelf/deployment.yaml` — target file, no resources block yet; 3 volume mounts already wired
- `apps/base/audiobookshelf/storage.yaml` — existing PVCs (config, metadata, audiobooks) to use as template for new ones
- `apps/base/homepage/deployment.yaml` — target, no resources block
- `apps/base/linkding/deployment.yaml` — target, no resources block (linkding deployment may be separate from its postgres)
- `apps/base/mealie/deployment.yaml` — target, no resources block

### Established Patterns
- Resource blocks go directly in `apps/base/{app}/deployment.yaml` inside the container spec — NOT in staging overlays
- PVC size: existing audiobookshelf PVCs use `5Gi` — new content-type PVCs should follow same sizing unless the planner finds a reason to differ
- StorageClass: `local-path` (the only class currently available)

### Integration Points
- New volume mounts in deployment.yaml must match volume names declared in the `volumes:` section and PVC names in storage.yaml
- Kustomization files (`apps/base/{app}/kustomization.yaml`) reference storage.yaml — verify storage.yaml is already listed before adding PVCs

</code_context>

<deferred>
## Deferred Ideas

- Pinning n8n and cloudflared image tags — dropped (phase 3 removed, working as-is)
- LimitRange objects per namespace — could enforce defaults cluster-wide; not needed now, consider for a future security phase
- VPA (Vertical Pod Autoscaler) to auto-tune limits — out of scope for this milestone

</deferred>

---

*Phase: 02-add-resource-limits-audiobookshelf*
*Context gathered: 2026-04-04*
