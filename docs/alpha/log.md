# Log

## 2026-04-26

### Session 1

**Step 1: Rails app foundation** — completed

- Moved original planning docs (channels, workflows, skills) to `_temp/`
- Installed Ruby 3.4.9 via mise (mise.toml + .ruby-version)
- Generated Rails 8.1.3 app in repo root: `rails new . --skip-test --database=mysql --css=tailwind`
- Configured Gemfile: Sidekiq, sidekiq-cron, Redis, Chartkick, Groupdate, google-apis-youtube_v3, google-apis-youtube_analytics_v2, dotenv-rails, RSpec, FactoryBot, Faker, Shoulda Matchers, WebMock, RuboCop rails-omakase
- Configured database.yml: utf8mb4 encoding, host/port from .env, credentials from rails credentials:edit
- Created docker-compose.yml: MySQL 8 (port 3307) + Redis 7 (port 6380) with healthchecks
- Created .env.example with MYSQL_HOST, MYSQL_PORT, REDIS_URL
- Rewrote bin/dev: checks Docker, starts/waits for Compose services, then runs Foreman (Puma + Sidekiq + Tailwind)
- Configured Sidekiq initializer with Redis URL, sidekiq-cron loader, cron schedule file (jobs commented until Step 6)
- Set Redis as cache store in development
- Set Sidekiq as Active Job queue adapter
- Configured RSpec with FactoryBot, Shoulda Matchers, WebMock
- Pinned Chartkick + Chart.js in importmap
- Wrote CLAUDE.md and README.md
- Verified: Rails boots, RSpec runs (0 examples, 0 failures)

**Decisions:**
- Used mise.toml (not just .ruby-version) because mise had a bug with --path .ruby-version; kept .ruby-version too for compatibility
- Kept solid_queue/solid_cache/solid_cable gems from Rails generator (only used in production config, won't interfere with Sidekiq in dev)
- MySQL uses empty root password for local dev simplicity

---

**Step 2: Craigslist-style layout + top nav + Sidekiq Web** — completed

- Created Craigslist-inspired Tailwind CSS: blue underlined links (#0000cc), dense tables, plain form inputs, small bordered buttons
- Created application layout with top nav: `pito · Dashboard · Channels · Compare · Production · Notes · Settings · Sidekiq`
- Created `nav_link` helper (bold span for current page, link for others)
- Created placeholder controllers and views for all nav pages
- Added Sidekiq::Web with HTTP basic auth from credentials (`sidekiq.username`, `sidekiq.password`)
- Added pry-rails for console
- Fixed CI workflow: MySQL/Redis via GitHub Actions services, test DB creds via env vars
- Split `.env` into `.env.development` and `.env.test` (both gitignored); `.env.example` is committed
- CI has its own env vars defined in the workflow file
- Fixed RSpec force-setting `RAILS_ENV=test` (user has `RAILS_ENV=development` globally)
- database.yml test section reads from env vars first (for CI), falls back to credentials (for local)
- 16 specs, 0 failures

**Decisions:**
- Force `ENV["RAILS_ENV"] = "test"` in rails_helper (not `||=`) because user has RAILS_ENV=development globally
- Sidekiq Web protected with HTTP basic auth via rails credentials, not left open
- CI test job uses env vars for DB config (no master key needed in CI)
- Separate .env.development/.env.test files instead of single .env

---

**Step 3: Models + migrations + encrypted attrs + factories + model specs** — completed

- Created 6 migrations: AppSetting, Channel, Video, VideoStat, Production, Note
- Added 7th migration: `owned` boolean on channels (default false) to distinguish owned channels (with OAuth/private analytics) from public competitor channels (public data only via API key)
- Configured Active Record Encryption (keys in credentials) for: AppSetting.value (deterministic), Channel.oauth_access_token, Channel.oauth_refresh_token
- Model validations: presence, uniqueness (with DB-level unique indexes)
- Enums: Production.status (idea/in_progress/published/archived), Note.kind (idea/log/todo/reference)
- Associations: Channel has_many Videos → has_many VideoStats; Video has_one Production (optional)
- Scopes: Channel.owned, Channel.public_only
- Class methods: AppSetting.get(key), AppSetting.set(key, value)
- Created FactoryBot factories for all 6 models with traits (:owned for Channel, :with_video for Production)
- 45 specs (27 model + 16 navigation + 2 Sidekiq), 0 failures
- Updated layout: "P" logo in header, added footer with © year
- RuboCop clean

**Decisions:**
- `owned` boolean (default false) instead of separate table or STI — simpler, same schema works for both channel types
- AppSetting.value encrypted with `deterministic: true` so we can query by encrypted value (needed for lookups)
- Production belongs_to :video is optional (can plan a production before filming/uploading)
- VideoStat uniqueness scoped to [video_id, date] — one stats row per video per day

---

**Step 4: Settings page for OAuth credentials** — completed

- Built Settings page with form to manage YouTube OAuth config (client_id, client_secret, redirect_uri) via AppSetting
- SettingsController with index (GET) and update (PATCH) actions
- Empty fields don't overwrite existing values (safe partial updates)
- Client secret uses password input type
- Fixed CI: Active Record Encryption keys provided via config when ENV["CI"] is set (no master key needed)
- 7 request specs for settings CRUD + flash messages
- 52 total specs, 0 failures

**Decisions:**
- Single form with all three OAuth fields rather than individual key/value CRUD — simpler UX for a fixed set of settings
- CI encryption keys hardcoded in test.rb behind ENV["CI"] guard — these are throwaway test keys, not real secrets

---

**Step 5: Purge Production, Notes, Compare + nav overhaul** — completed

- Dropped productions and notes tables (reversible down-migration)
- Removed Production, Note models, factories, specs, controllers, views
- Removed Compare controller, view, route
- Removed icon.png and icon.svg (replaced by Pito.png)
- New header: Pito.png logo + "Pito" text (both link to /), nav `Channels · Videos · Settings`
- Removed Dashboard, Compare, Production, Notes, Sidekiq from nav
- Added Videos controller + placeholder view
- Favicon now uses Pito.png
- Removed has_one :production from Video model
- 43 specs, 0 failures

**Decisions:**
- Sidekiq Web stays mounted at /sidekiq with auth but is not linked from anywhere in the UI — admin-only tool
- Logo links to / (Dashboard) with aria-label, no separate Dashboard nav link needed

---

**Step 6: Visual baseline** — completed (also covers Steps 7-8)

- Rewrote `app/assets/tailwind/application.css`: Verdana 12px base, compact headings (14/13/12px), blue links (#0000cc), visited (#551a8b), YouTube red for danger only (#cc0000), muted #555
- Dense tables with zebra rows, plain form inputs with blue focus outline
- Bracketed submit buttons: lowercase bold 13px, no border/background, blue on hover (`[ save ]`)
- Fixed 32px header: Pito.png logo (14px, nudged up 1px for alignment) + bracketed nav `[ Channels ] · [ Videos ] · [ Settings ]`
- Bracketed nav links: underline on text only (brackets/spaces outside `<a>` tag)
- Footer: copyright left, "Version 0.0.1.alpha" right
- Settings form constrained to 480px max-width
- Added `.rubocop.yml` exclusion for `app/assets/**/*` (CSS files were parsed as Ruby)
- 43 specs, 0 failures

**Decisions:**
- Merged Steps 7 (header/nav) and 8 (button style) into Step 6 since the visual overhaul naturally covered all three
- Used `!important` on `.header-logo` to override Tailwind preflight's `height: auto` on images
- Wrapped settings form in constraining div rather than inline style on form (Tailwind preflight interference)

---

**Step 9: Channel schema update + housekeeping** — completed

- Renamed `owned` column to `connected` on channels table (rename migration)
- Updated Channel model: scopes `connected` and `public_only` use `connected` column
- Updated factory: `:connected` trait replaces `:owned`
- Updated specs to match new naming
- Moved flash notices inside `<main>` so they align with page content
- Removed `docs/testing/` folder — testing instructions provided in conversation/PR instead
- Updated CLAUDE.md to remove testing folder references
- 43 specs, 0 failures

---

**Step 10: Video schema additions** — completed

- Added columns: scheduled_publish_at (datetime), privacy_status (integer enum), category_id (integer), default_language (string), made_for_kids (boolean, default false)
- Enum: privacy_status — public_video (0), unlisted (1), private_video (2)
- Factory traits: :unlisted, :private_video, :scheduled
- 47 specs, 0 failures

---

**Step 11: Playlist + PlaylistItem models** — completed

- Created Playlist model: belongs_to channel, has_many playlist_items/videos, privacy_status enum, unique youtube_playlist_id
- Created PlaylistItem model: belongs_to playlist + video, unique youtube_playlist_item_id, unique [playlist_id, video_id]
- Added has_many :playlists on Channel, has_many :playlist_items/playlists on Video
- 59 specs, 0 failures

---

**Step 12: SavedView model** — completed

- SavedView: kind enum (channels/videos), url, name, position, unique index on [kind, url]
- display_name method returns "Kind: name"
- 65 specs, 0 failures

---

**Step 13: BulkOperation + BulkOperationItem models** — completed

- BulkOperation: kind enum (update_metadata/update_privacy/add_to_playlist/remove_from_playlist), status enum with prefix (pending/running/completed/failed), JSON fields for parameters/target_video_ids/dry_run_preview
- BulkOperationItem: belongs_to bulk_operation + video, status enum with prefix (pending/succeeded/failed), unique [bulk_operation_id, video_id]
- 74 specs, 0 failures

---

**Step 14: VideoUpload model (lightweight)** — completed

- VideoUpload: metadata tracker only — backend never touches file bytes
- Upload architecture decision: browser uploads directly to YouTube via resumable URI, backend provides URI using channel OAuth token and tracks status
- Fields: channel (required), video (optional, linked after completion), status enum (pending/uploading/processing/completed/failed), privacy_status enum with prefix, title, file_name, file_size, bytes_sent, resumable_uri, youtube_video_id, error_message
- progress_percent method for UI progress bar
- Updated Phase 13 plan to reflect client-side direct upload approach
- YouTube Studio fallback links planned per connected channel
- 84 specs, 0 failures

---

## 2026-04-27

**Step 15: Breadcrumb helper + nav/footer restyle** — completed

- `breadcrumb` helper: views declare crumbs, layout renders only when present
- Supports linked segments (array `[label, path]`) and plain text (last = bold), `/` separator
- 32-char truncation per segment
- Restyled nav convention: `[ ]` wraps entire nav group, not individual links — `[ Channels · Videos · Settings ]`
- Footer: small nav `[ Home · Channels · Videos · Settings ]` + logo © year copyright line
- 88 specs, 0 failures

---

**Step 16: Confirmation dialog + lowercase tone** — completed

- Stimulus confirm-dialog controller with `<dialog>` element, Esc/click-outside to close
- Shared partial `_confirm_dialog.html.erb` with `destructive: true` option for red confirm button
- Dialog positioned at top of viewport (below navbar), centered horizontally
- Buttons grouped as `[ confirm · cancel ]` — confirm bold blue, destructive red, cancel blue
- All UI copy switched to lowercase casual tone (wanna, can't, etc.)
- Added "home" to top navbar
- Footer copyright link clickable, version lowercase
- Settings labels lowercase (keep YouTube, OAuth, URI, ID)
- 88 specs, 0 failures

---

**Step 17: Table component + Dashboard** — completed

- Sortable table Stimulus controller — client-side sort by string, number, or date; click header to toggle ↑↓
- Table CSS: zebra rows, vertical borders, 13px body / 14px headers, padding 4px 8px
- Sortable headers reserve arrow space (transparent `↕`) to prevent column width shift
- Indicator cells: ▲ green (>5% up), ▼ red (>5% down), — flat; compares recent 3 days vs older 3 days
- Duration formatting helper (H:MM:SS or M:SS)
- Dashboard controller loads videos with aggregated stats (SUM views/likes/comments/watch_time)
- Dashboard view: video table with 10 columns, summary line ("N videos across M channels")
- Seed data: 3 channels (2 connected, 1 public), 75 videos with 7-30 days of daily stats each
- Bracketed link rework: `[ text ]` is entire clickable link, only inner text underlined; current page shown as `[ page ]` in bold; applies to navbar, footer, breadcrumbs, dialog buttons, submit buttons
- Page titles: `pito ~ best YouTube tool` (home), `channels ~ pito` (subpages)
- Base font bumped from 12px to 13px site-wide, headings 15/14/13px, footer 11px
- 97 specs, 0 failures

---

**Step 19: Channels + Videos picker pages** — completed

- Channels picker at `/channels`: sortable table (title, connected, subscribers, videos, views), `[ open ]` per row, `[ add channel ]`
- Videos picker at `/videos`: sortable table (title, channel, views, trend, likes, comments, watch time, privacy, published, duration), `[ open ]` per row, `[ add video ]`
- Dashboard simplified to video/channel counts (table moved to Videos page)
- Table polish: sort arrows always visible (#999 muted, dark when active), tight `col-action` class for action columns, right-aligned dates/booleans/privacy, h1 bumped to 18px
- Sortable controller switched from `data-column` index to `indexOf(th)` so column shifts (bulk mode) work automatically
- 109 specs → 18 request specs for channels/videos/dashboard

---

**Step 20: Bulk mode for Channels + Videos pickers** — completed

- `[ bulk ]` toggle on both picker pages, swaps `[ open ]` column for checkbox column
- Header checkbox with select-all / indeterminate state
- Bulk actions bar: "N selected — [ open ] · [ delete ] · [ cancel ]"
- Shared `bulk_select_controller.js` Stimulus controller: enterBulk/exitBulk toggle visibility of checkbox vs action columns
- `[ open ]` and `[ delete ]` bulk actions are placeholder links (wired in workspace/action screen phases)
- Merged step 22 (videos bulk mode) into step 20
- Phase reorder: workspaces (phase 5) now come before action screens (phase 6)
- 45 specs, 0 failures

---

**Step 26: Channels workspace** — completed

- `/channels/:id` show page with channel metadata table + video list
- `/channels/panes?ids=1,2,3` multi-pane workspace with side-by-side channels
- Pane reorder arrows (◀ ▶), `[ focus ]` to single view, `[ − ]` to remove pane
- `[ + ]` opens `<dialog>` modal to add channels from available pool
- Comma-separated IDs in URLs (parser accepts commas, spaces, plus signs)
- URL-based sorting via hash fragments with `replaceState` — per-pane sort keys, no back-button pollution
- `data-sort-value` attribute for correct trend (signed %) and watch time sorting
- Watch time formatted as `Xh Ym` instead of raw minutes
- Stacked filled sort arrows (▲▼) for unsorted state, single arrow for active sort
- Pane dividers with breathing room, breadcrumb truncation with Unicode ellipsis (…)
- `pane_title_length` AppSetting with ENV fallback, exposed in settings screen
- Settings screen: responsive 2-column layout (workspaces left, YouTube OAuth right)
- Monospace font (system), bold links, all links consistently blue
- 150 specs, 0 failures

---

**Step 23–25, 32–33 (combined): Action screen framework + delete flow** — completed

- Shared `_action_screen.html.erb` partial: sticky footer with submit/cancel, supports destructive (red) and normal (blue) buttons
- `DeletionsController`: GET preview page + POST creates BulkOperation and renders progress in-place (no redirect)
- Preview page matches picker columns exactly: channels (title, connected, subscribers, videos, views), videos (title, channel, views, trend, likes, comments, watch time, privacy, published, duration)
- Empty first column as placeholder for status indicators
- `BulkDeleteJob`: processes all items in a single transaction, broadcasts per-item progress + terminal progress bar via Turbo Streams
- Polymorphic `BulkOperationItem` (target_type + target_id) — supports both Channel and Video targets
- Terminal-style progress bar: `[######.............] 3/7` with `#` filled, `.` empty
- Bounce loader animation: `=---` / `-=--` / `--=-` / `---=` per-item status indicator
- Item completion: green "done" or red "fail" replaces loader
- ActionCable configured with Redis adapter for cross-process Sidekiq→browser broadcasts
- `bulk_select_controller.js`: dynamic `[ delete N ]` links with `ref` param preserving current URL + hash for cancel navigation
- `BulkOperation` model: added `bulk_delete` kind, Turbo::Broadcastable, helper methods (target_count, succeeded_count, progress_percent)
- Migration: polymorphic target columns on bulk_operation_items, backfill from video_id
- Buttons: blue by default (#0000cc), `.btn-danger` for destructive red (#cc0000)
- CSS: `.action-screen-footer` sticky bottom, `.dot-loader` bounce animation, `.dot-done` / `.dot-fail` status colors
- 180 specs, 0 failures

---

**ViewComponent foundation + Step 34–36 (combined): Saved Views** — completed

- Installed `view_component` (4.8.0) and `capybara` (3.40.0) gems
- Created 4 ViewComponents:
  - `BracketedLinkComponent` — the `[ label ]` pattern with active, destructive, method, confirm, data attrs support
  - `BreadcrumbComponent` — renders crumb segments with `/` separator, truncation, delegates to BracketedLinkComponent
  - `StatusIndicatorComponent` — trend arrows (up/down/flat), dot-loader/done/fail with CSS variable animation delay
  - `SavedViewsSectionComponent` — renders saved views list with `[ open ]` + `[ delete ]` links, conditional render
- Refactored `nav_link` and `breadcrumb` helpers to delegate rendering to components (active-detection logic stays in helper)
- Refactored `view_trend_indicator` to use StatusIndicatorComponent
- Removed `breadcrumb_segment` private helper (logic moved into BreadcrumbComponent)
- Refactored inline bracketed links in action_screen, bulk_operations/show, deletions/progress, channels/_picker
- SavedView model enhancements: `.ordered` scope, `entity_labels`, `display_name_with_deletions`, `extract_ids_from_url`
- `SavedViewsController` — create (auto-position, idempotent duplicate handling), destroy (redirects to picker)
- `[ save view ]` / `[ delete saved view ]` in breadcrumb actions on panes pages (channels + videos)
- `[ delete ]` link in breadcrumb actions on show pages (channels + videos)
- No `[ save view ]` on single-entity show pages (only on multi-pane workspaces)
- SavedViewsSectionComponent rendered on channels picker and videos index (above table)
- Videos workspace: show, panes, _pane partial, _add_pane_dialog — mirrors channels workspace pattern
- `content_for(:breadcrumb_actions)` slot in layout for per-page breadcrumb actions
- `CGI.unescape` on URLs in SavedViewsController and panes lookups (Rails encodes commas as %2C)
- 247 specs, 0 failures

---

**Step 37–39 (combined): Charts, Decorators, JSON Responses** — completed

- Installed Draper 4.0.6 for decorator pattern
- Created decorators: `ApplicationDecorator` (base), `VideoDecorator`, `ChannelDecorator`, `VideoStatDecorator`
  - Decorators provide `as_summary_json` / `as_detail_json` for JSON API responses
  - `VideoDecorator` handles computed columns (`total_views` etc.) from controller queries
- Chart.js global config: monospace font, 11px, #555 color, legend bottom, point radius 0, line width 1.5, animations kept
- Dashboard rebuilt with 4 Chartkick charts:
  - Daily views (line), views by channel (multi-series line), top 10 videos (bar), daily engagement (likes + comments line)
  - `ChartToolbarComponent` — `[ 7d ] · [ 30d ] · [ 90d ] · [ 1y ] · [ all ]` range selector using BracketedLinkComponent
  - Groupdate `group_by_day` for zero-filled date series
  - `data-turbo-cache="false"` to avoid stale chart caching
- JSON responses added to dashboard, channels (index/show), videos (index/show) via `respond_to`
- Improved seeds: 90 days of stats per video, exponential decay from publish, channel growth profiles (growing/steady/declining), viral spikes (10% chance), weekend bumps, correlated likes/comments/shares/watch_time
- Channel and video edit pages (`[ edit ]` in breadcrumb actions)
- Breadcrumb action labels shortened: `[ save ]` not `[ save view ]`, `[ delete ]` not `[ delete saved view ]`
- 281 specs, 0 failures

---

**Step 40 (combined): Dark Mode, Design System, Polish** — completed

- Dark mode with Dracula-inspired color palette:
  - Background #282a36, foreground #f8f8f2, links #bd93f9 (purple), muted #6272a4 (comment), borders #44475a (current line)
  - Success #50fa7b (green), danger #ff5555 (red)
  - Chart colors: purple, green, pink, orange, cyan (all Dracula palette)
- All CSS colors converted to custom properties (`var(--color-xxx)`) — `:root` for light, `[data-theme="dark"]` for dark
- Fixed inline hardcoded colors: footer border `#ddd` → `var(--color-border)`, BracketedLinkComponent active `#1a1a1a` → `var(--color-text-bold)`
- Theme toggle `[ dark ]` / `[ light ]` in navbar header (right-aligned with `margin-left: auto`)
- AppSetting `theme` with 3 values: light, dark, auto (match system)
- `PATCH /settings/theme` endpoint in SettingsController
- Stimulus theme controller (`theme_controller.js`): localStorage + server persistence via fetch, system media query listener
- Priority: localStorage > server AppSetting > system preference (for "auto")
- Flash prevention: inline `<script>` in `<head>` applies theme before body renders (avoids white flash in dark mode)
- Chart.js theme adaptation: `recolorCharts()` function reads `--color-chart-N` CSS variables, applies to all Chartkick charts, also updates grid lines, axis labels, and tooltip colors. Called on DOMContentLoaded and after theme toggle.
- Synced crosshair plugin: charts with `data-sync-group="dashboard"` share hover position — hovering chart 1 shows crosshair on charts 3 and 4 at the same date. Uses `afterEvent` hook to broadcast index to siblings.
- Chart legend fix: hidden items keep `[ brackets ]` and bold, just muted color. Bold set globally via `Chart.defaults.plugins.legend.labels.font`.
- Page width constraints: channels picker `max-width: 900px`, videos picker `max-width: 1400px`
- Sidekiq testing: replaced deprecated `require "sidekiq/testing"` with `Sidekiq.testing!(:fake)`
- Created comprehensive `docs/design.md`: typography, all color tokens (light + dark), color rules, dark mode implementation, interactive elements, chart conventions, layout rules
- Updated CLAUDE.md to reference design doc
- 4 new theme endpoint specs (dark, light, auto, invalid)
- 285 specs, 0 failures

---

**Step 40: Plan update, housekeeping** — completed

- Confirmed max_panes is already fully implemented (AppSetting + settings UI + controllers + ENV fallback)
- Deferred max_concurrent_uploads to upload phase (Phase 13)
- Added `.claude/settings.json` to git (project-scoped Claude Code config)
- Marked Phases 10–13 as deferred (YouTube integration later)
- Added "Pre-Phase 14 — Bigger Seed Data" step to plan
- Reordered plan: bigger seed → search (Phase 14) → finalize (Phase 15) → MCP (Phase 16)

## 2026-04-27

### Session 1

**Phase 14: Bigger seed + Meilisearch search + UI polish** — completed

Seed data:
- Expanded to 10 channels (tech, gaming, cooking, music, fitness, travel, etc.) and 270 videos
- Varied categories, languages, privacy states, durations, 90 days of stats with realistic distributions

Meilisearch search stack:
- Added Meilisearch v1.13 Docker service (port 7700) to docker-compose.yml
- Added `meilisearch` gem for direct HTTP client (not meilisearch-rails)
- `Search::Engine` abstract interface with `index`, `remove`, `reindex_all`, `search`, `healthy?`, `index_stats`
- `Search::MeilisearchEngine` implementation using `Meilisearch::Client`, snake_case params, `find_in_batches` reindexing
- `Search` module with `engine`/`reset_engine!` accessor, AppSetting-based engine selection
- `Searchable` concern: `searchable(*fields)`, `filterable(*fields)` class macros, after_commit callbacks
- Channel: searchable title/description, filterable connected
- Video: searchable title/description/tags/category_id/default_language, filterable channel_id/privacy_status
- `SearchIndexJob`, `SearchRemoveJob`, `ReindexAllJob` on `:search` queue
- `SearchController#show` — searches both Channel and Video, combined results with highlighting, HTML + JSON
- Navbar: search input (200px) + `[ search ]` button with separator dot, theme toggle pushed far right

Settings + Sidekiq:
- Settings page split with `<hr>`: form with `[ save ]` above, search status + `[ reindex ]` below
- Sidekiq queue separation: `default`, `bulk_deletion`, `search` via `config/sidekiq.yml`
- `BulkDeleteJob` moved to `:bulk_deletion` queue

UI polish:
- Saved views: changed from inline list to `[ saved views ]` link + `<dialog>` modal, `width: max-content` with `white-space: nowrap`
- Clean deletion URLs: `/deletions/:type/:ids` path segments (was query params)
- Deletion breadcrumbs now show "delete 3 videos" / "deleting 3 videos"
- Deletion delay reduced from 5s to 3s
- `CheckboxComponent` (ViewComponent): markdown-style `[ ]`/`[x]`/`[-]` with bold indicator and optional muted label
- Replaced all native checkboxes in videos/channels tables with CheckboxComponent
- Dashboard chart sync: `[ ] sync` / `[x] sync` checkbox per line chart, `chart_sync_controller.js` toggles `data-sync-group`
- Separator dots (`·`) between all adjacent bracketed links (breadcrumb actions, title + `[+]`, pane headers, chart titles)
- Link alignment: `position: relative; top: -2px` next to h1, `-1px` next to h2
- Fixed Stimulus controllers: restored `eagerLoadControllersFrom` (importmap-compatible) after `stimulus:manifest:update` broke relative imports
- Replaced all `innerHTML` with safe DOM methods in `bulk_select_controller.js` (createElement/textContent/replaceChildren)
- `saved_views_controller.js` — new Stimulus controller for dialog open/close/clickOutside

Specs:
- `spec/services/search/engine_spec.rb`, `search/meilisearch_engine_spec.rb`, `search_spec.rb`
- `spec/models/concerns/searchable_spec.rb`
- `spec/jobs/search_index_job_spec.rb`, `search_remove_job_spec.rb`, `reindex_all_job_spec.rb`
- `spec/requests/search_spec.rb`, updated `settings_spec.rb`, `deletions_spec.rb`
- `spec/components/checkbox_component_spec.rb`, updated `saved_views_section_component_spec.rb`
