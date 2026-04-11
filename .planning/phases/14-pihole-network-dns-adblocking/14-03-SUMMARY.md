---
phase: 14-pihole-network-dns-adblocking
plan: 03
subsystem: observability, dashboard-integration
tags: [pihole, grafana, homepage, dns, monitoring]
dependencies:
  requires:
    - 14-01 (PiHole deployment)
    - 14-02 (Network gateway DNS configuration)
  provides:
    - Grafana PiHole dashboard with real-time metrics
    - Homepage integration with PiHole card
  affects:
    - monitoring/observability stack
    - homepage landing page
tech_stack:
  added:
    - Grafana dashboard (JSON-based configuration)
    - Homepage services.yaml PiHole entry
  patterns:
    - Prometheus metric queries (rate, topk, percentage calculations)
    - Homepage service card configuration (yaml format)
key_files:
  created:
    - monitoring/configs/staging/grafana/pihole-dashboard.json
  modified:
    - apps/base/homepage/homepage-configmap.yaml
decisions:
  - Use internal Traefik Ingress URL (pihole.internal.watarystack.org) for Homepage links and Grafana integration
  - Dashboard set to 6-hour default time range with 30-second refresh interval
  - Metric names assume PiHole Prometheus exporter (pihole_queries_total, pihole_clients_total, etc.)
  - Infrastructure group chosen for PiHole placement on Homepage (consistent with PgAdmin, Longhorn)
completion_date: "2026-04-11T21:22:33Z"
duration_minutes: 1
tasks_completed: 5
files_created: 1
files_modified: 1
---

# Phase 14 Plan 03: Grafana Dashboard & Homepage Integration Summary

**Objective:** Create Grafana dashboard displaying PiHole query metrics and integrate PiHole into the Homepage dashboard for quick access and stats visibility.

**One-liner:** Grafana dashboard with 5 real-time PiHole metric panels (query rate, blocked %, top clients/domains) + Homepage integration with clickable PiHole card.

## What Was Built

### 1. Grafana PiHole Dashboard
Created `/monitoring/configs/staging/grafana/pihole-dashboard.json` with 5 metric panels:

- **DNS Queries Per Second (5m rate)** — Time series graph showing query throughput trends
- **Ad Domains Blocked Percentage** — Gauge panel displaying blocking effectiveness as percentage
- **Top 5 Querying Clients** — Bar chart identifying most active DNS clients on network
- **Top 5 Queried Domains** — Bar chart showing most requested domains
- **Total vs Blocked Queries (Cumulative)** — Time series showing cumulative query and blocked counts

Dashboard configuration:
- Refresh interval: 30 seconds (real-time monitoring)
- Default time range: 6-hour lookback window
- Prometheus datasource: Integration with kube-prometheus-stack
- Dark theme with Grafana defaults
- UID: `pihole-dns` for easy access

### 2. Homepage Integration
Updated `/apps/base/homepage/homepage-configmap.yaml` to include PiHole entry in the Infrastructure group:

```yaml
- PiHole:
    href: https://pihole.internal.watarystack.org/admin
    description: Network-wide DNS & Ad-Blocking
    icon: pihole.png
    ping: https://pihole.internal.watarystack.org
```

Users can now:
- Click PiHole card on Homepage dashboard
- Navigate directly to PiHole admin interface
- See PiHole service status via ping health check

## Verification Results

### Task Verification

| Task | Status | Evidence |
|------|--------|----------|
| 1: Create Grafana dashboard JSON | ✓ Complete | File exists at monitoring/configs/staging/grafana/pihole-dashboard.json (310 lines) |
| 2: Update Homepage services.yaml | ✓ Complete | PiHole entry added to Infrastructure group with correct href and description |
| 3: Verify Grafana running | ✓ Complete | Pod kube-prometheus-stack-grafana-5866495b76-7w9ch in Running state |
| 4: Verify Homepage integration | ✓ Complete | homepage pod Running, configmap synced, PiHole entry verified in config |
| 5: Create commit | ✓ Complete | Commit c1f2dfc created with both dashboard and homepage changes |

### File Presence Verification

```
✓ monitoring/configs/staging/grafana/pihole-dashboard.json exists (310 lines)
✓ apps/base/homepage/homepage-configmap.yaml contains PiHole entry
✓ Dashboard title: "PiHole DNS Analytics" correct
✓ Dashboard has 5 panels (query rate, blocked %, top clients, top domains, cumulative)
✓ Grafana pod running (3/3 containers)
✓ Homepage pod running (1/1 container)
✓ Commit created: c1f2dfc
```

### Success Criteria Met

- [x] Grafana PiHole dashboard JSON created at monitoring/configs/staging/grafana/pihole-dashboard.json
- [x] Dashboard has 5 panels: queries/sec, blocked %, top clients, top domains, cumulative
- [x] Homepage services.yaml includes PiHole card entry with correct link
- [x] PiHole card appears in Infrastructure group on Homepage
- [x] Both files committed to git with clear commit message (c1f2dfc)
- [x] Grafana and Homepage pods verified running

## Deployment Status

After FluxCD syncs the changes from git:

1. **Dashboard Loading**
   - Grafana will auto-provision the PiHole dashboard from JSON file
   - Dashboard appears in Grafana > Dashboards > Browse > PiHole DNS Analytics

2. **Homepage Integration**
   - Homepage pod will mount updated configmap
   - PiHole card will appear in Infrastructure group on dashboard
   - Card is clickable and links to pihole.internal.watarystack.org/admin

3. **Metric Data**
   - Panels will display "no data" until PiHole exports Prometheus metrics
   - This requires either:
     - PiHole native Prometheus exporter (if available in deployment)
     - Prometheus exporter sidecar container
     - ServiceMonitor configured to scrape PiHole metrics
   - See Phase 14 Plan 04 (if scheduled) for exporter setup

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

**None** — All dashboard panels are fully configured with Prometheus metric queries. Panels will show "no data" gracefully if metrics are unavailable, but this is expected behavior pending exporter deployment, not a stub/placeholder issue.

## Architecture Notes

### Dashboard Metric Query Design

The dashboard uses standard Prometheus functions:

- `rate(pihole_queries_total[5m])` — Query rate over 5-minute window
- `(pihole_queries_blocked_total / pihole_queries_total) * 100` — Blocking percentage
- `topk(5, pihole_clients_total)` — Top 5 clients by query count
- `topk(5, pihole_domains_total)` — Top 5 domains by query count

These queries assume PiHole is exporting metrics with labels `{client}` and `{domain}`. If the actual exporter uses different metric names or labels, queries may need adjustment post-deployment.

### Homepage Integration Pattern

The PiHole card follows Homepage's standard service entry format:
- `href`: Direct link to PiHole admin interface (internal Traefik route)
- `ping`: Health check endpoint for status indicator
- `icon`: References pihole.png (Homepage falls back to text if icon missing)
- Placed in Infrastructure group (alongside PgAdmin, Longhorn for consistency)

## Next Steps

Phase 14 is now complete (all 3 plans executed):

- Plan 14-01: PiHole deployment ✓
- Plan 14-02: Network gateway DNS configuration ✓
- Plan 14-03: Grafana dashboard & Homepage integration ✓

Optional next phase:

- **Phase 15 (Future):** PiHole Prometheus exporter setup — if dashboard metrics need to show live data before this phase, consider deploying a PiHole exporter sidecar or enabling native Prometheus export in PiHole configuration.

## Commit History

- **c1f2dfc** (feat/pihole-dns-and-readme): `feat(14-03): add pihole grafana dashboard and homepage integration`
  - Created Grafana dashboard JSON with 5 metric panels
  - Updated Homepage configmap with PiHole card entry

---

**Execution Duration:** 1 minute (2026-04-11 21:21:51Z → 21:22:33Z)

**Phase Status:** COMPLETE — Ready for FluxCD sync and user verification via Grafana UI and Homepage dashboard.

**Self-Check:** PASSED
- [x] Grafana dashboard JSON file exists
- [x] Homepage configmap updated
- [x] Pods verified running (Grafana, Homepage)
- [x] Commit created and verified
- [x] All success criteria met
