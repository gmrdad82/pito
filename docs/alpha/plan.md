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

## Phase 10 — Settings + OAuth (local data only until this point)

- [ ] **Step 40:** Settings page expansion — max_panes (default 5), max_concurrent_uploads (default 2) in AppSetting, form sections
- [ ] **Step 41:** OAuth service objects — Youtube::OauthClient for token exchange/refresh, WebMock-stubbed specs
- [ ] **Step 42:** Channel OAuth connect — `/channels/:id/oauth/connect` with breadcrumb, initiates OAuth flow, stores tokens, sets connected=true
- [ ] **Step 43:** Channel OAuth disconnect — action screen, dry-run preview, revokes tokens, sets connected=false

## Phase 11 — Sync

- [ ] **Step 44:** Youtube::ChannelFetcher service — fetch channel metadata via Data API, WebMock specs
- [ ] **Step 45:** Youtube::VideoFetcher service — fetch video list + metadata for a channel, WebMock specs
- [ ] **Step 46:** Youtube::AnalyticsFetcher service — fetch daily stats per video via Analytics API, WebMock specs
- [ ] **Step 47:** Youtube::PlaylistManager service — fetch playlists + items, WebMock specs
- [ ] **Step 48:** SyncChannelJob — orchestrates channel metadata + video list sync, job specs
- [ ] **Step 49:** SyncVideoStatsJob — daily stats sync (last 30 days, idempotent), job specs
- [ ] **Step 50:** SyncPlaylistsJob — playlist + items sync, job specs

## Phase 12 — Video Management Action Screens

- [ ] **Step 51:** Youtube::VideoUpdater service — update title/description/tags/category/privacy/schedule via Data API, WebMock specs
- [ ] **Step 52:** Youtube::ThumbnailUpdater service — set custom thumbnail, WebMock specs
- [ ] **Step 53:** MetadataEditsController — action screen for editing video metadata (bulk: prefix/suffix, tags add/remove, category set)
- [ ] **Step 54:** SchedulingsController — action screen for scheduling publish (bulk: stagger option)
- [ ] **Step 55:** PrivacyChangesController — action screen for changing privacy status
- [ ] **Step 56:** ThumbnailChangesController — action screen for changing thumbnails
- [ ] **Step 57:** PlaylistAdditionsController — action screen for adding videos to playlists

## Phase 13 — Video Upload (client-side direct to YouTube)

Upload architecture: browser uploads directly to YouTube API via resumable upload. Backend never touches file bytes — only provides the resumable URI (using channel's OAuth token) and tracks upload status. Each connected channel also gets a direct YouTube Studio link as fallback.

- [ ] **Step 58:** Youtube::ResumableUploadInitiator service — uses channel OAuth token to get resumable upload URI from YouTube, WebMock specs
- [ ] **Step 59:** Upload page — `/videos/upload`, channel selector, file picker, metadata form (title/description/privacy/tags)
- [ ] **Step 60:** Client-side upload Stimulus controller — browser streams file directly to YouTube via resumable URI, chunked with progress bar
- [ ] **Step 61:** Upload status tracking — VideoUpload record updated via Turbo Stream, completion links to synced Video
- [ ] **Step 62:** YouTube Studio links — per-channel `[ YouTube Studio ]` link on channel detail (studio.youtube.com/channel/{id})

## Phase 14 — Search (Meilisearch)

- [ ] **Step 63:** Meilisearch Docker service — add to docker-compose, healthcheck, update bin/dev, .env.example additions
- [ ] **Step 64:** Search::Engine interface + Search::MeilisearchEngine — pluggable engine, full method coverage, specs against real Meilisearch
- [ ] **Step 65:** Searchable concern — include in Channel/Video, declare fields, after_commit callbacks
- [ ] **Step 66:** SearchIndexJob + SearchRemoveJob + ReindexJob — async indexing, specs with Sidekiq::Testing
- [ ] **Step 67:** Navbar search input — form in header, GET /search, style to match
- [ ] **Step 68:** SearchController#show — channel + video sections, independent pagination, highlighting, empty/error states
- [ ] **Step 69:** Settings search section — include-channels toggle, engine display, `[ reindex all ]` via ReindexingsController action screen

## Phase 15 — Finalize (pre-MCP)

- [ ] **Step 70:** sidekiq-cron schedule — recurring sync jobs in config/sidekiq_cron.yml
- [ ] **Step 71:** Mobile responsiveness — single column stack, header wrap, table horizontal scroll, pane stacking
- [ ] **Step 72:** Accessibility audit — skip-to-content link, aria attributes, focus rings, heading hierarchy, WCAG AA contrast
- [ ] **Step 73:** Final polish — README update, bin/setup improvements, cleanup

## Phase 16 — MCP Server (Model Context Protocol)

- [ ] **Step 74:** JSON serializers for read controllers (channels, videos, search, workspaces, bulk operations)
- [ ] **Step 75:** Mcp::InternalFetcher — in-process URL → JSON dispatch, specs
- [ ] **Step 76:** Mcp::Tools::FetchAppData — wraps InternalFetcher with MCP input/output, specs
- [ ] **Step 77:** Mcp::Tools::ProposeAction — action catalog, target validation, dry-check, URL building, specs
- [ ] **Step 78:** Mcp::Resources — catalog + renderer, static Markdown loading, dynamic user-context + state resources
- [ ] **Step 79:** Static MCP documentation — overview, url-patterns, data-shapes, actions, conventions (checkpoint: user review)
- [ ] **Step 80:** Mcp::ProtocolHandler — JSON-RPC 2.0 dispatch for MCP methods (initialize, tools/list, tools/call, resources/list, resources/read)
- [ ] **Step 81:** Mcp::ServerController — POST /mcp endpoint, streaming, auth enforcement
- [ ] **Step 82:** McpAccessToken + McpClient models — migrations, factories, specs
- [ ] **Step 83:** OAuth 2.1 authorization server — DCR, authorize, token, revoke endpoints + .well-known metadata
- [ ] **Step 84:** Settings MCP section — user context editor, public URL, token list, dev token mode
- [ ] **Step 85:** Token revocation action screen
- [ ] **Step 86:** MCP end-to-end integration test
- [ ] **Step 87:** README MCP section — Cloudflare Tunnel setup, connector configuration
