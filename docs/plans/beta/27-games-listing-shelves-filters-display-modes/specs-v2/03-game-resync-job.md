# 03 — Game resync job (live status + collection-aware fan-out)

> Phase 27 v2 spec. Hardens the existing `GameIgdbSync` Sidekiq job into the
> canonical `GameResyncJob` with explicit "IGDB-sourced vs ownership-sourced"
> field partition, Sidekiq uniqueness, live Turbo-Stream broadcast to the
> game detail page, and the collection-cover fan-out contract from
> `specs-v2/02-collection-cover-art-compositions.md`.

---

## Goal

When a user clicks `[resync]` on a game detail page, the job re-fetches IGDB
data, overwrites the IGDB-sourced fields (last-write-wins), preserves
ownership-sourced fields (per-platform ownership, played-on, recorded-on,
footage hours, notes), and broadcasts a live status flip on the detail page
so the user sees the resync state without refreshing. On success, every
collection the game belongs to is enqueued for a cover-art regen
(alphabetical-by-name sequential chain — see spec 02).

This is the foundation for the per-page `[resync]` action surface introduced
by `specs-v2/08-game-detail-revamp.md` (the `[edit]` link in the breadcrumb
is replaced with `[resync]`, leveraging this job). It also underpins the
keybinding `s sync` defined in `specs-v2/09-keybindings-page-actions.md`.

---

## Scope in

- Rename or re-canonicalize `GameIgdbSync` as the source-of-truth
  `GameResyncJob`. Either rename the class (and leave a thin
  `GameIgdbSync = GameResyncJob` alias for the existing call sites until
  they migrate) or keep the class name and harden it. Architect lean:
  **harden the existing `GameIgdbSync` class in place** — it is already the
  job and renaming costs more than it gains.
- Codify the field-partition: which columns the job overwrites, which it
  preserves. Bake this into the spec body AND into a model-level
  documentation comment. The model already documents this; verify and
  reinforce.
- Sidekiq uniqueness lock: `sidekiq_options lock: :until_executed,
  on_conflict: :log`. Matches the `ReindexAllJob` pattern. The DB-level
  guard (`games.resyncing` Boolean column, already exists) remains the
  belt-and-suspenders mutex.
- ActionCable / Turbo Stream broadcast that swaps the sync status badge on
  the detail page from `synced ~22m ago` → `=---` dot-loader during the
  run, and back to `synced just now` afterwards. Pattern mirrors
  `ReindexAllJob#broadcast_voyage_section`.
- On success, fan out collection cover-art regens via the contract from
  `specs-v2/02-collection-cover-art-compositions.md § Behavior` —
  `Collections::CompositeRebuildQueue.new.enqueue_for_game_resync(game)`.
- On `Igdb::Client::ValidationError` (the IGDB id does not exist), stamp
  `last_sync_error`, broadcast the same "no longer syncing" state, do NOT
  enqueue collection rebuilds (because no data changed).

## Scope out

- The bulk-resync pathway (`BulkSyncJob` over many games). That keeps the
  existing per-game `GameSync` advisory-lock wrapper. The advisory-lock
  rationale remains valid; we are not touching it.
- The legacy `/games/:id/edit` route deletion (handled in spec 08).
- IGDB API client itself (`Igdb::Client`, `Igdb::SyncGame`). Those services
  are upstream of this job and we treat their behavior as fixed.

---

## Files to change

### Job

- `app/jobs/game_igdb_sync.rb` (existing — harden in place)
  - Add `sidekiq_options ..., lock: :until_executed, on_conflict: :log`.
  - In `ensure` block, after `Game.where(id: game.id).update_all(resyncing:
    false)`, call `broadcast_resync_state(game_id)`.
  - On success path (after `Igdb::SyncGame#call` returns), call
    `Collections::CompositeRebuildQueue.new.enqueue_for_game_resync(game)`.
    This is BEFORE the `ensure` block flips `resyncing` false.
  - On `Igdb::Client::ValidationError` (non-retryable), do NOT enqueue
    rebuilds.
  - On `RateLimited` / network errors, do NOT enqueue rebuilds in the
    intermediate retry; the success path fires once on the eventually
    successful run.
  - Add `broadcast_resync_state(game_id)` private method — mirrors
    `ReindexAllJob#broadcast_voyage_section`. Re-renders the
    `games/_sync_status` partial and replaces target
    `game_sync_status_<id>` for the stream named
    `"game_resync:#{game_id}"`. The view subscribes to that stream when
    `@game.resyncing?` is true OR via a permanent
    `turbo_stream_from "game_resync:#{game.id}"` declared on the show
    view (recommended permanent subscription so the broadcast always
    lands).

### Model

- `app/models/game.rb`
  - Reinforce the docstring section that lists IGDB-sourced vs
    ownership-sourced columns. Add a comment pointing to this spec.
  - No code change beyond doc — the partition is enforced by
    `Igdb::SyncGame` (which only updates IGDB columns) and by the
    `local_only_params` permit list in `GamesController#update` (which
    only accepts ownership / notes / footage / version inputs).

### View

- `app/views/games/show.html.erb` (current — slated for full rewrite in
  spec 08; until then, harden in place)
  - Add `turbo_stream_from "game_resync:#{@game.id}"` at the top of the
    page so the broadcast lands.
  - Extract the sync-status block (the "Row 2" pane) into a new partial
    `app/views/games/_sync_status.html.erb` that takes `game:` and renders
    either the `=---` dot-loader (when `@game.resyncing?` is true) or the
    relative time-ago label + `[resync]` button (when false). The
    Turbo-Stream replace target ID is `game_sync_status_<id>` and wraps the
    partial.
- `app/views/games/_sync_status.html.erb` (NEW)
  - Wrapper `<div id="game_sync_status_<%= game.id %>">`.
  - Inside: the existing two states (idle button vs animated indicator).
  - Uses `time_ago_in_words(game.igdb_synced_at)` for the relative label.

When spec 08's revamp lands, this partial moves into the new LEFT-pane
layout but the contract (target id, stream name, broadcast format) carries
over unchanged.

### Controller

- `app/controllers/games_controller.rb#resync` (existing)
  - No functional change. The action already checks `resyncing?` to
    short-circuit duplicates, enqueues `GameIgdbSync.perform_async`,
    redirects to show with a notice. Confirm and document.
  - If the action is renamed to align with the breadcrumb (`[resync]`), no
    URL change here — the path stays `POST /games/:id/resync`.

---

## Behavior contracts

### Field partition (LOCKED — pin in the model docstring)

IGDB-sourced (OVERWRITTEN by every resync run, last-write-wins):

- `title` — IGDB owns the canonical name.
- `summary` — IGDB description.
- `cover_image_id` — IGDB cover token.
- `release_date` / `release_year` / `release_precision`.
- `igdb_rating` / `igdb_rating_count` / `aggregated_rating` /
  `aggregated_rating_count` / `total_rating` / `total_rating_count`.
- `ttb_main_seconds` / `ttb_extras_seconds` / `ttb_completionist_seconds`.
- `external_steam_app_id` / `external_gog_id` / `external_epic_id`.
- `igdb_id` / `igdb_slug` / `igdb_checksum`.
- `igdb_synced_at` (stamped on every successful run).
- `genres` (join rows under `game_genres`) — replaced wholesale.
- `platforms_available` (join rows under `game_platforms`) — replaced
  wholesale.
- `developers` / `publishers` (join rows under `game_developers` /
  `game_publishers`) — replaced wholesale.
- `primary_genre_id` — re-picked after `sync_genres` per spec 01.

Ownership-sourced (PRESERVED — NEVER touched by the resync run):

- `game_platform_ownerships` join rows (per-platform ownership).
- `played_at` — user-set play log.
- `notes` — free text.
- `hours_of_footage_manual` / `hours_of_footage_cached`.
- `manual_date_override` — blocks calendar derivation.
- `collection_id` — user-set bucket.
- `bundle_members` — bundle membership.
- `video_game_links` — video attribution.
- `version_parent_id` / `version_title` — multi-version grouping.
- `star` (channels-style) — N/A on Game.

The partition is enforced by `Igdb::SyncGame#call` (only writes IGDB
columns) and by the `local_only_params` allowlist in
`GamesController#update`. This spec adds a paranoid model spec assertion
that re-syncing a game with all ownership-sourced fields set leaves them
unchanged (see Spec coverage below).

### Sidekiq uniqueness

```ruby
sidekiq_options queue: :default, retry: 5,
                lock: :until_executed, on_conflict: :log
```

`lock: :until_executed` requires `sidekiq-unique-jobs` (OSS gem) or
Sidekiq Enterprise. In OSS without the gem, the option is a no-op intent
declaration. The real safety net is the `games.resyncing` Boolean column
the job flips at start (skipping when already true) and clears in the
`ensure` block. This pattern is consistent with `ReindexAllJob`.

### Live broadcast

- Stream name: `"game_resync:#{game_id}"`.
- Target: `game_sync_status_<id>`.
- Action: `Turbo::StreamsChannel.broadcast_replace_to(stream, target:,
  partial: "games/sync_status", locals: { game: })`.
- Fires from:
  - End of the success path (re-loaded game with fresh `igdb_synced_at`).
  - `ensure` block after `Game.where(...).update_all(resyncing: false)`.
- Wrap broadcast in `rescue StandardError → nil` — a Redis hiccup must
  not raise out of the job.
- The show view permanently subscribes via `turbo_stream_from
  "game_resync:#{@game.id}"` so the swap lands whether or not the user
  initiated this run (a CLI / MCP resync triggers the same swap on the
  open browser tab).

### Collection rebuild fan-out

- On success ONLY (the `Igdb::SyncGame#call` returned without raising),
  call:
  ```ruby
  Collections::CompositeRebuildQueue.new.enqueue_for_game_resync(game)
  ```
  before the `ensure` block. The orchestrator handles "the game belongs
  to zero collections → no-op" and the alphabetical sequencing rule.
- On retryable failure (`RateLimited`, network), do NOT enqueue; the
  successful retry will fire it.
- On `ValidationError` (game id no longer exists on IGDB), do NOT
  enqueue — no data changed, no covers to rebuild.

### Re-pick `primary_genre` after sync (cross-ref spec 01)

`Igdb::SyncGame` runs `sync_genres` then re-pick via
`Games::PrimaryGenrePicker`. This contract lives in spec 01. Cross-link.

---

## Migrations

None. The `games.resyncing` Boolean column already exists from the Phase
14 polish pass.

---

## Spec coverage required

### Job spec (`spec/jobs/game_igdb_sync_spec.rb`)

Extend the existing file:

- Happy: a fresh sync sets `igdb_synced_at`, flips `resyncing` false in
  the ensure block, broadcasts the `_sync_status` partial replacement,
  enqueues `CollectionCoverRebuildJob` for every collection the game is
  in.
- Happy: game is in zero collections → no `CollectionCoverRebuildJob`
  enqueue.
- Happy: game is in 3 collections (`c_c`, `c_a`, `c_b`) — chain head is
  enqueued with `c_a` first, remaining chain `[c_b.id, c_c.id]`.
- Sad: `ValidationError` is rescued, `last_sync_error` is stamped,
  `resyncing` is cleared, broadcast fires, NO collection rebuild
  enqueued.
- Sad: `RateLimited` is re-raised (so Sidekiq retries), `resyncing` is
  cleared in `ensure`, broadcast fires, NO collection rebuild enqueued.
- Edge: passing a `game_id` for a deleted game → no-op (return early).
- Edge: the job is called while `resyncing?` is true → no-op (return
  early, no broadcast, no enqueue).
- Flaw guard: ownership-sourced fields (notes, played_at,
  hours_of_footage_manual, game_platform_ownerships,
  manual_date_override, collection_id, version_parent_id) are unchanged
  before vs after a sync run. Use a strict equality check on the
  pre-sync attribute hash for those columns.
- Sidekiq options: `lock: :until_executed`, `on_conflict: :log`,
  `retry: 5`.

### Broadcast helper spec

- Tests the `broadcast_resync_state(game_id)` private method renders the
  partial and submits to `Turbo::StreamsChannel.broadcast_replace_to`
  with the expected stream / target / partial.
- Tests that a `StandardError` raised by the broadcast is swallowed.

### View / partial spec (`spec/views/games/_sync_status.html.erb_spec.rb`)

- Renders the wrapper `<div id="game_sync_status_<id>">`.
- When `game.resyncing?` is true → renders the `=---` indicator span.
- When `game.resyncing?` is false → renders the `[resync]` button and
  the `synced X ago` label.
- When `igdb_synced_at` is nil → renders `not synced yet.` label.

### Request spec (`spec/requests/games/resync_spec.rb` or extend
`spec/requests/games_spec.rb`)

- `POST /games/:id/resync` enqueues `GameIgdbSync` exactly once, returns
  302 to show with a notice.
- `POST /games/:id/resync` while `resyncing?` is true → no enqueue,
  returns 302 with the `already resyncing.` notice.
- JSON variant returns 202 + the job id on accept, 409 on the
  already-syncing branch.

### Model spec — field partition (`spec/models/game_spec.rb`)

- Existing tests for sync stay. NEW: a test that runs `Igdb::SyncGame`
  via a stubbed IGDB response and asserts every ownership-sourced
  column is exactly equal before and after.

### System spec

- Optional, ONE scenario: navigate to a game detail page, click
  `[resync]`, the badge flips to the dot-loader, the test then drains
  the Sidekiq queue, the page (with the permanent stream
  subscription) shows the updated status. Capybara on the rack_test
  driver does not exercise live ActionCable, so this scenario uses
  the `turbo-rails` testing helper or the
  `ActionCable::Channel::TestCase` pattern.

---

## Open questions

1. **`lock: :until_executed` — is `sidekiq-unique-jobs` already in the
   Gemfile?** Confirm at implementation time. If not, lean on the
   existing `games.resyncing` column as the real mutex and treat the
   sidekiq_options line as intent-only (`ReindexAllJob` does the same).
2. **Permanent vs conditional `turbo_stream_from` subscription on the
   show view.** Architect lean: permanent. Cost is one extra WebSocket
   subscription per open tab; benefit is that CLI / MCP-initiated
   resyncs land in the user's open browser without a refresh. If
   conditional (only when `@game.resyncing?` is true at render time)
   the user must already be looking at a syncing game to see the
   resolution swap.
3. **Where does the success-path fan-out land relative to the
   `ensure` block?** Architect lean: INSIDE the success branch,
   AFTER `Igdb::SyncGame#call` returns, BEFORE `ensure` clears
   `resyncing`. This way the collection rebuilds see the
   freshly-resynced game's data (cover_image_id etc.) which their
   composites depend on.
