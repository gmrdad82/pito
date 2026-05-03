# Manual Test Playbook — Channel Revamp

**Date**: 2026-05-02 **Spec**:
pito-dev-kb/plans/beta/03-channel-revamp/specs/channel-revamp.md **Branch**:
main on every repo

## Preconditions

- Docker daemon healthy with iptables intact
- pito containers up: `docker compose up -d` (from pito repo) — verify
  pito-postgres-1, pito-redis-1, pito-meilisearch-1 are running
- client-api containers/networks/volumes are NEVER touched
- Run from a fresh shell — no env exports
- `Rails.application.credentials.owner` has been populated
  (`bin/rails credentials:edit`)
- `bin/rails db:drop db:create db:migrate db:seed` has been run on a clean DB

## Steps (run in order)

### 1. Stack health

- `docker ps --format '{{.Names}}\t{{.Status}}'` → expect pito-postgres-1,
  pito-redis-1, pito-meilisearch-1 all "Up"
- `bin/dev` starts: Web Puma (3000), MCP Puma (3001), Sidekiq, Tailwind watcher,
  no errors in log
- `curl -fsS https://app.pitomd.com/up` → 200
- `curl -fsS https://mcp.pitomd.com/mcp -X POST -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}'`
  → 200 with serverInfo.name == "pito"

### 2. Database state

- `bin/rails runner 'p Channel.column_names'` → expect
  `["id", "channel_url", "connected", "created_at", "last_synced_at", "star", "syncing", "tenant_id", "updated_at"]`
  (order may vary)
- `bin/rails runner 'p User.column_names'` → expect
  `["id", "created_at", "email", "password_digest", "tenant_id", "updated_at", "username"]`
  (no `name`)
- `bin/rails runner 'p Tenant.column_names'` → expect
  `["id", "created_at", "name", "updated_at"]`
- `bin/rails runner 'p [Tenant.count, User.count, Channel.count]'` → expect
  `[1, 1, 100]`
- `bin/rails runner 'p [Channel.where(star: true).count, Channel.where(connected: true).count, Channel.where(star: true, connected: true).count]'`
  → expect `[7, 6, 2]`
- `bin/rails runner 'p [BulkOperation.kinds.size, BulkOperationItem.statuses.size]'`
  → expect `[6, 4]`
- `bin/rails runner 'p Channel.included_modules.map(&:name).include?("Searchable")'`
  → expect `false`

### 3. Channel CRUD via web

- Visit https://app.pitomd.com/channels — list with URL column truncated, filter
  chips for starred/connected/syncing, `[view]` per row, `[add]`, `[bulk]`,
  saved-views section
- Click `[view]` on any row → opens canonical YouTube URL in a new tab with
  `rel="noopener noreferrer"`
- Click `[add]`, paste `https://www.youtube.com/@somehandle` → form rejects with
  the regex pattern hint
- Paste a fresh `https://www.youtube.com/channel/UC<22-char-id>` (e.g.
  `https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ` — if seeded
  already, generate another) → channel created
- Visit /sidekiq (basic auth from credentials) → confirm a `ChannelSync` job ran
  (after_create_commit)
- Click `[edit]` on the new channel → URL input is `readonly disabled`; star and
  connected render as toggleable checkboxes
- Toggle star on, submit → ChannelSync re-enqueues (after_update_commit when
  star?)
- From a separate terminal, attempt
  `curl -X PATCH -H 'Content-Type: application/json' -d '{"channel":{"channel_url":"https://www.youtube.com/channel/UCdifferent22charsXXXXXXXXX"}}' https://app.pitomd.com/channels/<id>`
  → URL silently ignored (strong params strip it; star/connected still
  permitted)

### 4. Bulk operations

- On /channels, click `[bulk]`, select 3 channels via checkbox (or space) —
  count chip updates
- Click `[delete N]` → confirmation page renders with 3 rows, `[confirm]` and
  `[cancel]`. NO browser confirm popup.
- Click `[cancel]` → returns to /channels with selections cleared
- Re-enter bulk mode, select 5 channels, including 2 already syncing (use
  `Channel.where(syncing: true).limit(2)` from a runner if seed didn't already
  create some, or trigger a sync on 2 to leave them mid-sync)
- Click `[sync 5]` → confirmation page renders. Already-syncing rows render in
  red as `[skip]` with a casual muted message ("already humming away") and a
  footer note "2 channels will be skipped (already syncing)"
- Submit → progress page renders. Counter starts at `2 of 5`. Skipped rows show
  `[skip]` immediately. Other 3 rows progress through `dot-loader` → `dot-done`.
  Counter ends at `5 of 5`.
- Repeat single-record path: select exactly 1 channel, `[sync 1]` → URL is
  `/syncs/channel/<id>`, same flow works for one or many
- Single-channel delete from `channels/<id>` show page → `[delete]` link routes
  to `/deletions/channel/<id>` (verified pre-phase, still wired)

### 5. Saved views

- From the channels page, save a current filter as a view (e.g., starred=1)
- Visit a saved-views list / dropdown that includes a channels-kind saved view →
  label renders the channel `id.to_s`, NOT a blank or a "title" call
- Repeat with a videos-kind saved view → label still renders the video title
  (kind-aware dispatch is in place)

### 6. Dashboard chart visibility

- Visit /dashboard → all charts visible by default; each chart container has
  `data-chart-id="<slug>"`; each chart header has a "sync" checkbox checked
- DevTools → Application → Local Storage →
  `localStorage.getItem("pito_dashboard_charts_visible")` → JSON array
  containing every slug present on the page
- Uncheck one chart's checkbox → chart container hides (CSS class toggle); array
  in localStorage no longer contains that slug
- Refresh → chart stays hidden, checkbox stays unchecked
- Re-check → chart reappears; slug returns to the array

### 7. MCP tools (via `bin/mcp` stdio or HTTP on :3001)

- `bin/rails runner 'puts Mcp::Tools::ListChannels.call({star: true}).inspect'`
  (or your tool framework's invocation) → returns 7 starred channels with the
  new shape (id, channel_url, star, connected, syncing, last_synced_at,
  created_at, updated_at)
- `bin/rails runner 'puts Mcp::Tools::CreateChannel.call({channel_url: "https://www.youtube.com/channel/UCnewfreshid22aaaaaaaaA"}).inspect'`
  → success
- `bin/rails runner 'puts Mcp::Tools::CreateChannel.call({channel_url: "https://youtu.be/bad"}).inspect'`
  → rejected with structured error (URL regex)
- `bin/rails runner 'puts Mcp::Tools::UpdateChannel.call({id: <id>, channel_url: "https://www.youtube.com/channel/UCdifferentxxxxxxxxxxxxxxxx"}).inspect'`
  → URL change rejected (silently dropped or structured error per implementer
  choice)
- `bin/rails runner 'puts Mcp::Tools::BulkSyncChannels.call({ids: [<a>,<b>,<c>]}).inspect'`
  (no `confirm`) → preview structure
  `{total:, syncable:, skipped:[{id,reason}], message:}` with no BulkOperation
  created
- Verify `BulkOperation.count` did NOT change between the preview call and the
  next step
- `bin/rails runner 'puts Mcp::Tools::BulkSyncChannels.call({ids: [<a>,<b>,<c>], confirm: true}).inspect'`
  → returns `{operation_id, progress_url}`; `BulkOperation.count` increased by
  1; `BulkSyncJob` enqueued
- Same two-step flow for `BulkDeleteChannels`
- Confirm there are NO registered `sync_channel(id:)` or `delete_channel(id:)`
  single-record tools. Inspect tool registry / list_tools output

### 8. Terminal app (pito-sh)

- `cd ~/Dev/pito-project/pito-sh && cargo run` (or against the live server)
- Channels list shows 100 rows; columns include URL (truncated), star,
  connected, syncing, last_synced_at
- Filters work (star, connected, syncing each narrow the visible set)
- Press `s` on a channel → star toggles, syncing pill may briefly appear
  (after_update star)
- Press `Y` on a single highlighted channel → bulk sync preview opens (NOT
  immediate). Press any non-`y` key → cancels with no API call.
- Multi-select with space (3 channels including 1 already syncing), press `Y` →
  preview shows red `[skip]` for the already-syncing row. Press `y` → bulk sync
  executes via MCP `bulk_sync_channels` with `confirm: true`.
- Repeat with `D` for bulk delete preview / confirm.
- Press `[v]` (or the configured `view` key) on a channel detail → opens the
  canonical URL via `xdg-open`
- Press `[e]` (edit) → URL is shown locked; attempting to change it flashes a
  "URL is locked" message; star and connected toggle.
- Confirm the search screen has NO channel-results section (Searchable removed);
  only video / playlist results render.

### 9. Spec gates from a fresh shell

- `bundle exec rspec` → **533 examples, 0 failures** (recorded 2026-05-02 by
  reviewer)
- `bundle exec brakeman --quiet` → **0 security warnings, 0 errors**
- `bundle exec bundler-audit check --update` → **No vulnerabilities found**
  (advisory db updated against ruby-advisory-db)
- `cd ../pito-sh && cargo test` → **29 passed; 0 failed; 0 ignored**
- `cd ../pito-sh && cargo check --all-targets` → **Finished `dev` profile**
  (warnings only, no errors)
- Grep gate:
  `rg -n 'data-turbo-confirm|window\.confirm|window\.alert|window\.prompt' app/`
  from pito repo → 0 hits

### 10. Schema sanity (recap)

- `bin/rails runner 'p Channel.column_names'` → exactly the 9 columns
  (`id, tenant_id, channel_url, star, connected, syncing, last_synced_at, created_at, updated_at`)
- `bin/rails runner 'p User.column_names'` → exactly the 7 columns
  (`id, tenant_id, username, email, password_digest, created_at, updated_at`)
- `bin/rails runner 'p Tenant.column_names'` → exactly the 4 columns
  (`id, name, created_at, updated_at`)
- `bin/rails runner 'p [BulkOperation.kinds.keys, BulkOperationItem.statuses.keys]'`
  →
  `[["update_metadata", "update_privacy", "add_to_playlist", "remove_from_playlist", "bulk_delete", "bulk_sync"], ["pending", "succeeded", "failed", "skipped"]]`

## Reviewer-flagged items

- Integration gap: `spec/requests/mcp_http_spec.rb:58` was using removed
  `title:` kwarg on `:channel` factory. Fixed in this review pass: factory call
  simplified to `create(:channel)` and assertion updated to look for
  `channel.channel_url` in tool output. No other gaps found across Phase B
  agents.
- All scope items in section 5 of the spec map to passing tests. URL-regex /
  URL-lock / star-toggle / cron / bulk skip / two-step confirm / dashboard
  localStorage / seeds / save-view label / Searchable removal — all covered.
- `Confirmable` concern (step A6b — "should-do, may defer") was actually
  shipped: `app/controllers/concerns/confirmable.rb` is present and included by
  both DeletionsController and SyncsController.
- Single-channel delete already routes through `/deletions/channel/<id>` (audit
  confirmed pre-phase, still true).
- Pre-existing JS confirm dialogs on SavedView delete are explicitly out of
  scope and remain (legacy, migrate later).

## Pass/Fail summary

[fill in after running through each step manually]

- [ ] Stack health
- [ ] Database state
- [ ] Channel CRUD via web
- [ ] Bulk operations (delete + sync, with skip badges)
- [ ] Saved views
- [ ] Dashboard chart visibility
- [ ] MCP tools (two-step confirm)
- [ ] Terminal app
- [ ] Spec gates from a fresh shell
- [ ] Schema sanity
