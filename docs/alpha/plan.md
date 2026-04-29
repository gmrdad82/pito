# Build Plan

## Completed

- [x] **Step 1:** Rails app foundation — Ruby 3.4.9, Rails 8.1.3, gems, database.yml, docker-compose, Sidekiq + Redis, RSpec
- [x] **Step 2:** Initial layout + top nav + Sidekiq Web with auth
- [x] **Step 3:** Initial models + migrations + encrypted attributes + factories + model specs
- [x] **Step 4 (partial):** Settings page for OAuth credentials — form works, needs expansion
- [x] **Step 5:** Purge Production, Notes, Compare
- [x] **Step 6:** Visual baseline — Verdana 12px, color palette, compact spacing, bracketed nav/buttons, header logo, footer with version
- [x] **Step 7:** _(merged into Step 6)_
- [x] **Step 8:** _(merged into Step 6)_
- [x] **Step 9:** Channel schema update — replace `owned` with `connected`
- [x] **Step 10:** Video schema additions — privacy_status enum, scheduled_publish_at, category, language, made_for_kids
- [x] **Step 11:** Playlist + PlaylistItem models
- [x] **Step 12:** SavedView model
- [x] **Step 13:** BulkOperation + BulkOperationItem models
- [x] **Step 14:** VideoUpload model (lightweight)
- [x] **Step 15:** Breadcrumb helper + nav/footer restyle
- [x] **Step 16:** Custom confirmation dialog + lowercase tone
- [x] **Step 17:** Table component + Dashboard — sortable headers ↑↓, zebra rows, indicator cells ▲▼, seed data, bracketed link rework, page titles, font bump to 13px

## Phase 4 — Picker Pages

- [x] **Step 19:** Channels + Videos picker pages — `/channels` and `/videos` tables with `[ open ]` per row, `[ add channel ]` / `[ add video ]`, sortable headers, request specs
- [x] **Step 20:** Bulk mode for Channels + Videos pickers — `[ bulk ]` toggle, checkbox column, header checkbox, bulk actions bar (open/delete/cancel), Stimulus controller
- [x] **Step 21:** _(merged into Step 19)_
- [x] **Step 22:** _(merged into Step 20)_

## Phase 5 — Workspaces (moved before Action Screens)

- [x] **Step 26:** Channels workspace — `/channels/:id` show page, `/channels/panes?ids=1,2,3` multi-pane with reorder arrows, focus/add/remove, add-pane modal, URL-based sorting via hash fragments, comma-separated IDs, pane_title_length setting, comprehensive specs
- [x] **Step 27:** _(merged into Step 26)_
- [x] **Step 28:** _(repurposed — pane reorder arrows ◀ ▶ implemented in Step 26)_
- [x] **Step 29:** _(deferred — videos workspace will reuse channels pattern)_
- [x] **Step 30:** _(deferred — merged into Step 29)_
- [x] **Step 31:** _(deferred — merged into Step 29)_

## Phase 6 — Action Screen Framework + Delete Flow

- [x] **Step 23–25, 32–33 (combined):** Action screen shared partial, DeletionsController (preview + progress), BulkDeleteJob with Turbo Stream broadcasts, polymorphic BulkOperationItem, terminal-style progress bar, bounce loader animation, ActionCable/Redis for cross-process broadcasts, comprehensive request specs

## Phase 7 — ViewComponent Foundation

- [x] **Step (new):** ViewComponent gem + BracketedLinkComponent, BreadcrumbComponent, StatusIndicatorComponent, SavedViewsSectionComponent — component specs, refactored helpers to delegate rendering

## Phase 8 — Saved Views + Videos Workspace

- [x] **Step 34–36 (combined):** SavedViewsController (create/destroy), `[ save view ]` on workspace pages, saved views section on picker pages, entity_labels with [deleted] annotations, position ordering, idempotent save, Videos workspace (show + panes + pane partial + add dialog), breadcrumb actions (`[ delete ]` on show, `[ save view ]` / `[ delete saved view ]` on panes), request + model + component specs

## Phase 9 — Charts, Decorators, JSON Responses

- [x] **Step 37–39 (combined):** Draper decorators (Video, Channel, VideoStat), Chart.js global config, Chartkick dashboard with 4 charts (daily views, views by channel, top videos, daily engagement), ChartToolbarComponent with time-range selectors `[ 7d ] · [ 30d ] · [ 90d ] · [ 1y ] · [ all ]`, JSON responses on dashboard/channels/videos controllers, improved seed data with realistic trends (90 days, decay curves, viral spikes), decorator + component + request specs

## Phase 9b — Dark Mode, Design System, Polish

- [x] **Step 40 (combined):** Dark mode with Dracula-inspired dark theme, CSS custom properties for all colors, theme toggle `[ dark ]` / `[ light ]` in navbar, AppSetting persistence (light/dark/auto), Stimulus theme controller with localStorage + server sync, flash prevention `<script>` in `<head>`, Chart.js theme-aware recoloring (`recolorCharts()`), synced crosshair plugin across dashboard charts, `docs/design.md` comprehensive design system document, page width constraints (channels 900px, videos 1400px), Sidekiq testing API update, bold chart legend labels, theme endpoint specs

## Phase 14 — Bigger Seed + Meilisearch Search + UI Polish

- [x] **Step 40 (combined):** Bigger seed data (10 channels, 270 videos), Meilisearch search stack, UI polish

## Phase 15 — Cleanup + Polish (pre-MCP)

- [x] **Step 70:** VERSION file + dynamic footer — version read from `VERSION`, clickable git SHA in footer, bumped to v0.0.1.alpha3
- [x] **Step 71:** sidekiq-cron schedule — daily Meilisearch reindex at 4am, YouTube sync jobs commented for beta
- [x] **Step 72:** Mobile responsiveness — header wraps, tables horizontal scroll, panes stack vertically, charts full width
- [x] **Step 73:** Final polish — README update with full stack description, bin/setup Meilisearch healthcheck, cleanup
- [x] Moved YouTube-related phases (OAuth, Sync, Video Management, Upload) to `docs/beta/plan.md`

## Phase 16 — MCP Server (Model Context Protocol)

### Step 1 — Local stdio server (done)

- [x] **Step 74:** `mcp` gem (v0.14.0), `bin/mcp` stdio entry point, 15 tools (list/get/create/update/delete for channels, videos, saved views + dashboard, search, settings), 3 resources (design doc, app status, mcp doc), 38 specs, `docs/mcp.md`

### Step 2 — HTTP transport + tunnel (done)

- [x] **Step 75:** `POST /mcp` endpoint (Streamable HTTP), `McpAccessToken` model, dedicated Puma on port 3001, rake tasks for token management, Cloudflare Tunnel (`mcp.pitomd.com` + `app.pitomd.com`), auth removed for alpha (OAuth deferred to beta)
