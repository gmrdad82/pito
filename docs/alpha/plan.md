# Build Plan

## Completed

- [x] **Step 1:** Rails app foundation — Ruby 3.4.9, Rails 8.1.3, gems, database.yml, docker-compose, Sidekiq + Redis, RSpec
- [x] **Step 2:** Initial layout + top nav + Sidekiq Web with auth
- [x] **Step 3:** Initial models + migrations + encrypted attributes + factories + model specs
- [x] **Step 4 (partial):** Settings page for OAuth credentials — form works, needs expansion

## Phase 1 — Purge + Visual Overhaul

- [x] **Step 5:** Purge Production, Notes, Compare — down-migrations, remove models/factories/specs/controllers/views/routes/nav links
- [x] **Step 6:** Visual baseline — Verdana 12px, color palette, compact spacing, bracketed nav/buttons, header logo, footer with version
- [x] **Step 7:** _(merged into Step 6)_ Header + nav overhaul — logo, bracketed nav, footer
- [x] **Step 8:** _(merged into Step 6)_ Unified button style — bracketed lowercase bold buttons, blue hover

## Phase 2 — Schema + Models

- [x] **Step 9:** Channel schema update — replace `owned` with `connected` (boolean, default false), migration + model + factory + spec update
- [x] **Step 10:** Video schema additions — add scheduled_publish_at, privacy_status (enum), category_id, default_language, made_for_kids (boolean), migration + model + factory + spec
- [x] **Step 11:** Playlist + PlaylistItem models — migrations, associations, validations, factories, model specs
- [ ] **Step 12:** SavedView model — kind enum (channels/videos), url, position, unique index on [kind, url], display_name method, factory, model specs
- [ ] **Step 13:** BulkOperation + BulkOperationItem models — kind enum, status enum, parameters/target_video_ids/dry_run_preview (json), per-item status tracking, factories, model specs
- [ ] **Step 14:** VideoUpload model — belongs_to channel, optional video, status enum, resumable upload fields, factory, model specs

## Phase 3 — Core UI Components

- [ ] **Step 15:** Breadcrumb helper — static, declared per view, rendered by layout only when present, 32-char per-segment truncation, specs
- [ ] **Step 16:** Custom confirmation dialog — Stimulus + `<dialog>`, for transient confirmations only (discard unsaved changes), focus trap, Esc close
- [ ] **Step 17:** Excel-like table component — sticky header, sticky first col, zebra rows, sortable headers with ↑↓, scroll container
- [ ] **Step 18:** Table enhancements — dense-mode toggle (localStorage), column visibility popover (localStorage), numeric right-alignment, indicator cells (▲▼)

## Phase 4 — Settings + OAuth

- [ ] **Step 19:** Settings page expansion — max_panes (default 5), max_concurrent_uploads (default 2) in AppSetting, form sections with labels/hints
- [ ] **Step 20:** OAuth service objects — Youtube::OauthClient for token exchange/refresh, WebMock-stubbed specs
- [ ] **Step 21:** Channel OAuth connect — full-page sub-page `/channels/:id/oauth/connect` with breadcrumb, initiates OAuth flow, stores tokens on Channel, sets connected=true
- [ ] **Step 22:** Channel OAuth disconnect — action screen at `/channel_disconnections/new?targets=channel:ID`, dry-run preview, revokes tokens, sets connected=false

## Phase 5 — Sync

- [ ] **Step 23:** Youtube::ChannelFetcher service — fetch channel metadata via Data API, WebMock specs
- [ ] **Step 24:** Youtube::VideoFetcher service — fetch video list + metadata for a channel, WebMock specs
- [ ] **Step 25:** Youtube::AnalyticsFetcher service — fetch daily stats per video via Analytics API, WebMock specs
- [ ] **Step 26:** Youtube::PlaylistManager service — fetch playlists + items, WebMock specs
- [ ] **Step 27:** SyncChannelJob — orchestrates channel metadata + video list sync, job specs with Sidekiq::Testing
- [ ] **Step 28:** SyncVideoStatsJob — daily stats sync (last 30 days, idempotent), job specs
- [ ] **Step 29:** SyncPlaylistsJob — playlist + items sync, job specs

## Phase 6 — Action Screen Framework

- [ ] **Step 30:** Action screen shared partial — breadcrumb slot, heading, preview table, parameters form slot, sticky footer with submit/cancel
- [ ] **Step 31:** DeletionsController — first action screen end-to-end, routes, dry-run preview, transactional local delete, single + bulk, request specs
- [ ] **Step 32:** BulkOperationsController#show — progress page for async operations, Turbo Stream broadcasts from Sidekiq jobs, request specs

## Phase 7 — Picker Pages

- [ ] **Step 33:** Channels picker — `/channels` (no panes), channels table with `[ Open ]` per row, `[ + Add channel ]` (register by ID/URL), request specs
- [ ] **Step 34:** Channels picker bulk mode — `[ bulk ]` toggle, checkbox column, States 1-4, header checkbox, `[ Open N channels ]`, `[ delete ]` link to action screen, Stimulus controller
- [ ] **Step 35:** Videos picker — `/videos` (no panes), videos table with `[ Open ]` per row, `[ + Add video ]`, request specs
- [ ] **Step 36:** Videos picker bulk mode — same pattern as channels, Stimulus controller

## Phase 8 — Workspaces

- [ ] **Step 37:** Channels workspace — single pane at `/channels?panes=UCabc`, full-width channel detail with video table, request specs
- [ ] **Step 38:** Channels multi-pane — 2+ panes side-by-side, pane toolbar (× ⇄ ▸), `[ + ]` add pane popover, max_panes enforcement
- [ ] **Step 39:** Resizable pane dividers — Stimulus controller for drag-resize between panes
- [ ] **Step 40:** Videos workspace — single pane at `/videos?panes=vid1`, video detail layout (player area + side metadata + stats), request specs
- [ ] **Step 41:** Videos multi-pane — 2+ panes side-by-side, same controls as channels
- [ ] **Step 42:** Cross-workspace navigation — video click in channel pane → `/videos?panes=vid`, channel name click in video pane → `/channels?panes=UC...`

## Phase 9 — URL State + Edge Cases

- [ ] **Step 43:** URL state encoding — sort/filter in URL per pane, dense/columns in localStorage, Cache-Control: no-store on workspace pages
- [ ] **Step 44:** Missing entity handling — MissingPane placeholder when pane ID doesn't resolve, warning notice per pane, `[ × Remove ]` link

## Phase 10 — Saved Views

- [ ] **Step 45:** Saved Views CRUD — `[ Save view ]` in workspace pane strip, POST /saved_views, idempotent (no-op if URL already saved), flash notice
- [ ] **Step 46:** Saved Views on picker pages — section above entity list, computed display_name ([C] Title1 · Title2 +N more), `[ Delete ]` via action screen
- [ ] **Step 47:** Saved Views edge cases — [deleted] labels for missing entities, all-panes-deleted still shown, position ordering

## Phase 11 — Charts

- [ ] **Step 48:** Chart.js global config — animation:false, pointRadius:0, borderWidth:1.5, LTTB decimation, crosshair tooltip, legend below
- [ ] **Step 49:** Video stats charts — views/likes/comments over time on Video pane, Chartkick + Groupdate
- [ ] **Step 50:** Chart toolbar — time-range selectors `[ 7d ] · [ 30d ] · [ 90d ] · [ 1y ] · [ all ]`, CSV export

## Phase 12 — Video Management Action Screens

- [ ] **Step 51:** Youtube::VideoUpdater service — update title/description/tags/category/privacy/schedule via Data API, WebMock specs
- [ ] **Step 52:** Youtube::ThumbnailUpdater service — set custom thumbnail, WebMock specs
- [ ] **Step 53:** MetadataEditsController — action screen for editing video metadata (bulk: prefix/suffix, tags add/remove, category set)
- [ ] **Step 54:** SchedulingsController — action screen for scheduling publish (bulk: stagger option)
- [ ] **Step 55:** PrivacyChangesController — action screen for changing privacy status
- [ ] **Step 56:** ThumbnailChangesController — action screen for changing thumbnails
- [ ] **Step 57:** PlaylistAdditionsController — action screen for adding videos to playlists

## Phase 13 — Video Upload

- [ ] **Step 58:** Youtube::VideoUploader service — resumable upload via videos.insert, WebMock specs
- [ ] **Step 59:** Upload page — `/videos/upload` with breadcrumb, file picker, channel selector, metadata form
- [ ] **Step 60:** Resumable upload Stimulus controller — chunked client-side upload, progress tracking
- [ ] **Step 61:** UploadToYoutubeJob — server-side resumable upload to YouTube, chunk progress updates, resumption on failure
- [ ] **Step 62:** Upload progress UI — sticky bottom bar with active uploads, per-upload text progress, expandable

## Phase 14 — Search (Meilisearch)

- [ ] **Step 63:** Meilisearch Docker service — add to docker-compose, healthcheck, update bin/dev, .env.example additions
- [ ] **Step 64:** Search::Engine interface + Search::MeilisearchEngine — pluggable engine, full method coverage, specs against real Meilisearch
- [ ] **Step 65:** Searchable concern — include in Channel/Video, declare fields, after_commit callbacks
- [ ] **Step 66:** SearchIndexJob + SearchRemoveJob + ReindexJob — async indexing, specs with Sidekiq::Testing
- [ ] **Step 67:** Navbar search input — form in header, GET /search, style to match
- [ ] **Step 68:** SearchController#show — channel + video sections, independent pagination, highlighting, empty/error states
- [ ] **Step 69:** Settings search section — include-channels toggle, engine display, `[ Reindex all ]` via ReindexingsController action screen

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
