# Video Sync with Diff Dialog

## Goal

Widen Step 11's 11i diff-dialog reconciliation pattern — already locked for
channels — to **videos**. Both daily background sync and user-triggered `[sync]`
on `/videos/:slug` NEVER overwrite Pito state and NEVER push to YouTube
silently. Every divergence between Pito and YouTube surfaces as a **diff
dialog** the user resolves field-by-field, with per-row bidirectional resolution
(`accept pito` pushes the local value out to YouTube; `accept youtube` pulls the
remote value into Pito). The default radio selection on every field row is
`accept youtube`, preserving the YouTube-as-source-of-truth posture locked in
Step 11 D20.

This is the video sibling of 11i. Where logic is shareable (diff page renderer,
apply-changes controller flow, per-field decision form helpers), implementation
extracts shared partials / components so both surfaces use the same code. Where
logic is video-specific (the writable-field set, the quota math for
`videos.list` × N videos × daily, the rate-limit considerations for
`notifyNewVideo`), the spec calls it out explicitly.

The capability lets the user keep Pito and YouTube aligned across the
multi-channel video catalogue without silent overwrites in either direction —
which is the same property B3 of the source note pins as a **blocking design
decision** for any step that touches video sync.

## Files touched

### Schema (23a)

- `db/migrate/<ts>_add_video_metadata_columns_for_diff.rb` — adds the writable +
  display-only columns enumerated in §"Schema additions" below to `videos`.
  Several columns already exist on `Video` (Phase 12 brought back `title` /
  `description` / `tags` / `category_id` / `privacy_status` / `publish_at` /
  `self_declared_made_for_kids` / `contains_synthetic_media` per
  `app/models/video.rb`). The migration audits the live schema and adds only the
  missing fields:
  - `embeddable` (boolean, default true)
  - `public_stats_viewable` (boolean, default true)
  - `made_for_kids_effective` (boolean, read-only mirror — confirm whether Phase
    12 added this; if so, skip)
  - `view_count` / `like_count` / `comment_count` (bigint, default 0,
    display-only)
  - `duration_seconds` (integer, display-only — derived from
    `contentDetails.duration` ISO 8601 at sync time)
  - `published_at` (timestamp with time zone, display-only)
  - `thumbnail_url` (string, display-only — one tier, usually `maxres` falling
    back to `high`)
  - `etag` (string, opaque — used to short-circuit the diff when YouTube
    confirms "nothing changed")
  - `title_changed_at` (timestamp; 14-day rate-limit clock — see open question
    Q1 about whether YouTube enforces this for videos at all)
  - `last_diff_checked_at` (timestamp)
  - `last_sync_error` (text, nullable — surfaces the most recent sync failure on
    `/videos/:slug` if present)
- `db/migrate/<ts>_create_video_change_logs.rb` — append-only audit table shaped
  after `channel_change_logs` (Phase 7.5 §11a). Columns:
  `id, video_id (FK, ON DELETE CASCADE), field (string), old_value (text), new_value (text), source (enum: pito_apply | youtube_pull | initial_sync), changed_at, created_at`.
  Read-only at the model layer (`ActiveRecord::ReadOnlyRecord` on destroy
  attempts).
- `db/migrate/<ts>_create_video_diffs.rb` — open-diff registry. Columns:
  `id, video_id (FK, ON DELETE CASCADE), detected_at, resolved_at (nullable), payload (jsonb — { field => { pito:, youtube: } }), resolution_payload (jsonb, nullable — { field => "pito" | "youtube" }), resolved_by_user_id (FK to users, nullable), created_at, updated_at`.
  Partial unique index on `(video_id) WHERE resolved_at IS NULL` — one open diff
  per video at a time.

### Models (23a)

- `app/models/video.rb` — add `has_many :video_change_logs`,
  `has_many :video_diffs`,
  `has_one :open_diff, -> { where(resolved_at: nil) }, class_name: "VideoDiff"`.
  Validations on the new columns (numericality on counts;
  `duration_seconds >= 0`; URL format on `thumbnail_url`). Add `title_locked?` /
  `title_unlock_at` helpers parallel to `Channel#title_locked?` (gated on Q1 —
  if YouTube doesn't enforce 14-day for videos, drop these and the
  `title_changed_at` column).
- `app/models/video_change_log.rb` — new model, immutable, mirrors
  `ChannelChangeLog` shape. Include the read-only guard.
- `app/models/video_diff.rb` — new model. Methods: `#fields` (returns the keys
  of `payload`), `#field_diff(name)` (returns the `{pito:, youtube:}` pair for
  one field), `#resolved?` (alias for `resolved_at.present?`), scope `:open`,
  scope `:resolved`.

### Services (23a + 23c)

- `app/services/youtube/diff_computer.rb` — pure-function service. Takes a
  `Video` + a `videos.list` response payload, returns a hash
  `{ field => { pito: <value>, youtube: <value> } }` covering only the fields
  that differ. Tolerates type mismatches gracefully (e.g., YouTube returning a
  string where Pito stores an integer). Handles the array-vs-array semantics for
  `tags` (sorted-set comparison, not positional).
- `app/services/youtube/video_diff_persister.rb` — service that takes a diff
  hash + the video; if non-empty, upserts the open `VideoDiff` row and stamps
  `videos.last_diff_checked_at`. Idempotent: if an open diff already exists for
  the video, replaces its `payload`.
- `app/services/youtube/client.rb` — extend with
  `#update_video(video, fields:)`. Implements YouTube's destructive PUT-per-part
  pattern: for each writable field about to be pushed, the client first does a
  `videos.list?part=snippet,status,...` read (cheap, 1 unit), modifies only the
  target fields in the part bodies, and writes back the entire part bodies via
  `videos.update`. Reads the existing rate-limit handling (401 token refresh,
  403 quota exhaustion, 5xx retry-with-backoff) from the already-shipped Phase 7
  `Youtube::Client` and applies the same pattern. Returns a `Result` object:
  success bool + the response payload on success, error code + message on
  failure.

### Jobs (23a + 23d)

- `app/jobs/video_diff_check_job.rb` — Sidekiq job. Accepts a single `video_id`
  arg for targeted re-checks; without args, walks every `Video` whose
  `channel.youtube_connection_id IS NOT NULL` (the "owned + OAuth-connected"
  set). For each video: call
  `videos.list?id=<youtube_video_id>&part=snippet,status,contentDetails, statistics`,
  run `Youtube::DiffComputer`, persist via `Youtube::VideoDiffPersister`. On
  diff non-empty, enqueue a `Notifications::Emit` for
  `kind: video_diff_detected, severity: info` (Phase 16 surface).
- `app/jobs/bulk_video_diff_check_job.rb` — fan-out scheduler. Reads the set of
  connected channels, partitions the videos into stagger windows (e.g., divides
  the catalogue into 24 buckets by `id % 24` and enqueues each bucket with a
  `perform_in` offset), then enqueues one `VideoDiffCheckJob` per video.
- `config/sidekiq_cron.yml` (or equivalent) — daily entry. Separate from
  channel-diff cron per open question Q5 recommendation. Cron expression TBD on
  user input; recommend "00:30 UTC" so the spread runs in the off-peak window.

### Controllers + routes (23b + 23c)

- `config/routes.rb` — add
  `resources :videos, only: [] do member do; get :diff; patch :apply_diff; post :sync; end; end`.
  Friendly URL via `Video#to_param` — `:slug` resolves through
  `Video.friendly.find`.
- `app/controllers/videos_controller.rb` — add three actions:
  - `#diff` — renders the three-column diff page when an open `VideoDiff`
    exists; redirects to `/videos/:slug` with a flash when no diff is open.
  - `#apply_diff` — consumes the per-field decision form, calls
    `Youtube::VideoDiffApply.call(video:, decisions:)`, redirects to
    `/videos/:slug` with a success flash, or re-renders the diff page with
    errors on failure (e.g., a Pito-side validation rejection or a YouTube 4xx).
  - `#sync` — user-triggered sync. Enqueues `VideoDiffCheckJob` inline (sync via
    Sidekiq with `perform_inline` in development; in production, enqueue +
    redirect with a "checking…" flash). Reuses the existing `[sync]`
    confirmation framework (`SyncsController` + `Confirmable`) per the hard rule
    against JS `confirm` — single-record action goes through `/syncs/video/:ids`
    with one-element ids per bulk-as-foundation.
- `app/services/youtube/video_diff_apply.rb` — orchestrator. Takes the open
  `VideoDiff` + a decisions hash + the acting user. In one transaction:
  1. For each `accept youtube` field — update the Pito column from the YouTube
     payload snapshot.
  2. For each `accept pito` field — call
     `Youtube::Client#update_video(video, fields: { … })` with just that field.
  3. On every applied change (in either direction), append a `VideoChangeLog`
     row with `source: pito_apply` or `source: youtube_pull` accordingly.
  4. Stamp `video.last_diff_checked_at = Time.current` and
     `video_diff.resolved_at = Time.current`,
     `resolved_by_user_id = current_user.id`, `resolution_payload = decisions`.
  5. If `title` was Pito-wins applied, stamp
     `video.title_changed_at = Time.current` (gated on Q1).

The transaction rolls back if the YouTube push fails, so the local row and the
audit log stay consistent with the remote state.

### Views (23b)

- `app/views/videos/diff.html.erb` — three-column page. `<table>` with rows per
  differing field: column 1 the Pito value, column 2 the YouTube value, column 3
  a radio group `accept pito` / `accept youtube` with `accept youtube` checked
  by default. Below the table, an `[apply changes]` submit button
  (bracketed-link convention, no inner-space form). Reuses
  `shared/_pane.html.erb` with `pane--standalone`.
- `app/views/shared/_diff_table.html.erb` — **new shared partial** extracted at
  23b's start. Used by both `app/views/channels/diff.html.erb` (the existing 11i
  surface) and `app/views/videos/diff.html.erb`. Takes locals
  `subject:, fields:, diff:, decision_form_url:`. The 11i channel diff view is
  refactored in this spec to consume the shared partial — call that out in the
  23b dispatch so the rails-impl agent knows to touch the channel view too.
- `app/views/videos/show.html.erb` — add a flash-style banner when
  `@video.open_diff.present?`: bracketed link `[view diff]` pointing at
  `/videos/:slug/diff`. Banner copy: `youtube diverged on N fields`.
- `app/views/notifications/_video_diff_detected.html.erb` — notification
  formatter (Phase 16 plumbing). Renders the notification card with a
  `[view diff]` link.

### Components / helpers (23b)

- `app/components/diff_decision_radio_component.rb` — **new shared
  ViewComponent**. Renders the per-field radio group with bracketed labels
  (`[ ] accept pito` / `[x] accept youtube`). Takes
  `field:, pito_value:, youtube_value:, name:, disabled: false`. The `disabled`
  flag is used for read-only fields surfaced for context but not resolvable
  (e.g., showing `view_count` divergence in the table without a radio because
  it's display-only). Channel diff (11i) is refactored to consume the same
  component.
- `app/helpers/diff_helpers.rb` — **new** — `human_diff_value(field, value)`
  formats values for the table cells (truncate description to 240 chars with
  `[expand]`, render tags as pill list, render booleans as `yes` / `no` per the
  external-boundary rule, etc.).

### MCP / CLI (23a + 23c)

- `app/lib/mcp/tools/video_diff_show.rb` — **new tool**. Returns the open diff
  for one video as JSON. Scope: `app` (post-ADR 0004).
- `app/lib/mcp/tools/video_diff_apply.rb` — **new tool**. Two-step confirm flag
  per the hard rules (`confirm: bool`). Body shape:
  `{ video_id:, decisions: { field => "pito" | "youtube" }, confirm: }`. Scope:
  `app`. Tested via MCP tool spec; CLI parity tracked under the CLI
  feature-parity sweep follow-up rather than in this spec.
- The JSON branch on `VideosController#diff` returns the same shape as the MCP
  tool. The CLI consumes `GET /videos/:slug/diff.json` (Lane 2 work, scoped out
  of this spec — flagged in §"Cross-stack scope").

### Specs (every actor's parity sweep)

Per the project's spec pyramid rule (architect.md §D) and the user's auto-memory
note "spec exhaustively":

- `spec/models/video_spec.rb` — extend with the new columns' validations
  (numericality, URL format) + the `title_locked?` helpers' behaviour + the
  `has_many :video_change_logs / :video_diffs / open_diff` associations.
- `spec/models/video_change_log_spec.rb` — read-only-on-destroy guard; enum on
  `source`; presence of `field` + `changed_at`.
- `spec/models/video_diff_spec.rb` — `#open` / `#resolved` scopes; `#field_diff`
  returns the right pair; partial unique index enforces one open diff per video.
- `spec/services/youtube/diff_computer_spec.rb` — no-diff case (everything
  matches), single-field diff, multi-field diff, type-mismatch edge (YouTube
  string vs. Pito integer for `category_id`), tags sorted-set semantics (same
  tags reordered ≠ diff), missing-field edge (YouTube didn't return the part),
  nil- vs-blank edge.
- `spec/services/youtube/video_diff_persister_spec.rb` — empty diff → no-op;
  non-empty diff with no open diff → creates; non-empty diff with existing open
  diff → updates `payload`, leaves `resolved_at` nil.
- `spec/services/youtube/client_spec.rb` — extend with `#update_video` happy
  path (single field, multi-field, multi-part); sad paths: 401 (refresh token,
  retry succeeds); 403 quota exhausted (raises `Youtube::QuotaExhaustedError`);
  5xx server error with retry-with-backoff (success on retry, failure after N
  retries); rate-limit error on `notifyNewVideo` (handled as warning, not
  failure). All HTTP mocked via WebMock + VCR fixtures.
- `spec/services/youtube/video_diff_apply_spec.rb` — mixed decisions (some
  Pito-wins, some YouTube-wins) round-trip the database + the YouTube client
  correctly; transaction rollback on YouTube failure leaves Pito state
  untouched; `title_changed_at` stamped only on Pito-wins title applies;
  `VideoChangeLog` rows appended with the correct `source`.
- `spec/jobs/video_diff_check_job_spec.rb` —
  - happy: video with no diff → no `VideoDiff` row, no notification enqueued,
    `last_diff_checked_at` stamped.
  - happy: video with single-field diff → one `VideoDiff` row, one notification,
    `last_diff_checked_at` stamped.
  - sad: video record missing → job no-ops (logs warning, doesn't raise).
  - sad: channel's `youtube_connection_id` is null → job skips video.
  - sad: `videos.list` returns 403 quota → job raises
    `Youtube::QuotaExhaustedError`, Sidekiq retry policy handles backoff.
  - edge: batch where some videos diff and some don't — only the differing ones
    surface notifications.
- `spec/jobs/bulk_video_diff_check_job_spec.rb` — fan-out enqueues expected
  count; stagger windows distribute correctly.
- `spec/requests/videos/diff_spec.rb` —
  - GET happy: 200 with both columns populated, radios default to
    `accept youtube`.
  - GET edge: no open diff → redirect to `/videos/:slug` with flash.
  - PATCH happy: mixed decisions applied → Pito rows updated, YouTube push made
    via mocked client, redirect with success flash.
  - PATCH flaw: submit with no decisions made → re-render with error "select a
    decision for every field".
  - PATCH flaw: submit when both sides changed during the dialog (the diff
    payload is stale) → re-render with error "diff is stale, re-check", refresh
    diff in flight.
  - PATCH flaw: idempotency — submit while the diff is already resolved (a
    duplicate POST or a race with the daily job resolving the diff in a sibling
    tab) → re-render with "already resolved" notice, no double-apply.
- `spec/requests/videos/sync_spec.rb` — user-triggered sync routes through
  `/syncs/video/:ids` confirmation page; on confirm, enqueues
  `VideoDiffCheckJob`; redirects to `/videos/:slug` with "checking…" flash.
- `spec/components/diff_decision_radio_component_spec.rb` — renders the radio
  group with the expected bracketed labels; honours `disabled:` flag; default
  selection is `accept youtube`.
- `spec/helpers/diff_helpers_spec.rb` — `human_diff_value` formats description /
  tags / booleans / nil correctly.
- `spec/lib/mcp/tools/video_diff_show_spec.rb` /
  `spec/lib/mcp/tools/video_diff_apply_spec.rb` — scope gating, two- step
  confirm flag rejected without `confirm: true`, happy path matches the
  controller path.
- `spec/system/video_sync_diff_flow_spec.rb` — **selective system spec** per
  architect.md §D point 10 (critical user journey only). End-to-end: seed a
  video with a divergent local title; run `VideoDiffCheckJob` inline; assert a
  notification row exists; visit `/notifications`, click `[view diff]`; on the
  diff page, flip the title row to `accept pito`; click `[apply changes]`;
  assert the YouTube client received an `update_video` call with the new title,
  the local row's `title_changed_at` is stamped, the `VideoChangeLog` row exists
  with `source: pito_apply`, and the diff page now redirects back to
  `/videos/:slug` because no open diff remains.

## Acceptance

- [x] Migration adds the missing Video columns (audit the live schema before
      writing the migration; do not duplicate existing Phase 12 columns).
- [x] `video_change_logs` table exists, append-only, mirrors
      `channel_change_logs` shape.
- [x] `video_diffs` table exists with the partial unique index enforcing one
      open diff per video.
- [x] `Video` model exposes `has_many :video_change_logs`,
      `has_many :video_diffs`, `has_one :open_diff`, and `title_locked?` /
      `title_unlock_at` helpers (gated on Q1).
- [x] `VideoChangeLog` raises `ActiveRecord::ReadOnlyRecord` on `destroy`.
- [x] `VideoDiff#open` and `#resolved` scopes return the expected record sets.
- [x] `Youtube::DiffComputer` handles no-diff, single-field, multi- field,
      type-mismatch, tags sorted-set, missing-field, and nil-vs-blank cases
      correctly.
- [x] `Youtube::Client#update_video` implements the destructive PUT-per-part
      read-modify-write pattern.
- [x] `Youtube::Client#update_video` handles 401 (refresh), 403 (quota), 5xx
      (retry-with-backoff), and rate-limit-on- `notifyNewVideo` correctly.
- [x] `VideoDiffCheckJob` walks the connected videos, persists diffs, stamps
      `last_diff_checked_at`, enqueues notifications.
- [x] `BulkVideoDiffCheckJob` fan-out staggers across the day.
- [x] Sidekiq-cron entry scheduled (separate from channel-diff cron per Q5
      recommendation).
- [x] `/videos/:slug/diff` renders the three-column table with `accept youtube`
      as the default selection.
- [x] `/videos/:slug/diff` redirects to `/videos/:slug` with a flash when no
      open diff exists.
- [x] `[apply changes]` PATCH applies Pito-wins via the YouTube client and
      YouTube-wins to the local columns in a single transaction.
- [x] `[apply changes]` rolls back the local update when the YouTube push fails.
- [x] `VideoChangeLog` row appended for every applied field, with
      `source: pito_apply` or `source: youtube_pull` correctly.
- [x] `title_changed_at` stamped only on Pito-wins title apply (gated on Q1).
- [x] User-triggered `[sync]` button on `/videos/:slug` routes through the
      `SyncsController` confirmation page — no JS `confirm`, no
      `data-turbo-confirm`.
- [x] On confirm, the sync enqueues `VideoDiffCheckJob` and redirects with a
      flash.
- [x] Flash banner on `/videos/:slug` when `@video.open_diff.present?`, with
      `[view diff]` link.
- [x] Phase 16 notification `kind: video_diff_detected,     severity: info`
      produced when the job detects a diff.
- [x] MCP tools `video_diff_show` + `video_diff_apply` gated on `app` scope;
      `video_diff_apply` requires `confirm: true`.
- [x] All external booleans serialize as `"yes"` / `"no"` strings (decision
      values, diff page form, MCP I/O, JSON branch).
- [x] Friendly URL via `Video#to_param` — `/videos/:slug/diff` resolves through
      `Video.friendly.find`.
- [ ] Shared partial `shared/_diff_table.html.erb` extracted and consumed by
      **both** the new video diff view AND the existing channel diff view (11i
      refactored in 23b).
- [ ] Shared component `DiffDecisionRadioComponent` extracted and consumed by
      both surfaces.
- [x] Spec pyramid sweep: model specs, service specs, job specs, request specs
      (happy / sad / edge / flaw), component spec, helper spec, MCP tool specs,
      one selective system spec.
- [ ] `docs/design.md` updated if any new visual primitive ships (likely none —
      the diff page reuses `pane--standalone` and the bracketed-link
      convention).
- [x] `bundle exec rspec` green at full suite count.
- [x] `bundle exec rubocop` green.
- [x] `bin/rails db:migrate` applied to the dev DB after the rails-impl agent's
      migration lands (per architect.md §F).

## Manual test recipe

> Pre-requisites: `bin/dev` running. At least one `Channel` row with
> `youtube_connection_id` populated (a connected channel). At least one `Video`
> belonging to that channel. The MCP / CLI surface is outside this recipe — see
> "Cross-stack scope" for that.

### Step 1 — Force a diff

In a separate terminal:

```
bin/rails console
> v = Video.joins(:channel).where.not(channels: { youtube_connection_id: nil }).first
> v.update!(title: v.title.to_s + " [LOCAL EDIT]")
> exit
```

This makes Pito's local `title` diverge from the YouTube `title` the last sync
stamped.

### Step 2 — Trigger the daily diff check

In the same terminal:

```
bin/rails runner "VideoDiffCheckJob.perform_inline(Video.first.id)"
```

(`perform_inline` runs the Sidekiq job synchronously in dev so the diff lands
before you reload the browser.)

Watch the console output. Expect:

- One `videos.list` call to YouTube (1 quota unit).
- One `VideoDiff` row inserted with `payload[:title]` non-nil.
- One `Notification` row inserted with `kind: "video_diff_detected"`,
  `severity: "info"`.

### Step 3 — Visit the video show page

Browser → `http://127.0.0.1:3027/videos/<youtube_video_id>`.

Expect a banner at the top: `youtube diverged on 1 field` with a `[view diff]`
bracketed link.

### Step 4 — Open the diff page

Click `[view diff]` or navigate to
`http://127.0.0.1:3027/videos/<youtube_video_id>/diff`.

Expect:

- Three-column table: `Pito` | `YouTube` | `decision`.
- One row for the `title` field. The Pito column shows
  `<original title> [LOCAL EDIT]`; the YouTube column shows the original title.
- Radio group in the decision column: `[ ] accept pito` / `[x] accept youtube`.
  `accept youtube` is the default.
- `[apply changes]` button at the bottom.

### Step 5 — Apply (YouTube wins, default)

Click `[apply changes]` without flipping any radios.

Expect:

- Redirect to `/videos/<youtube_video_id>` with a flash
  `diff resolved (1 field accepted from youtube)`.
- `Video#title` reloaded — back to the original (without the `[LOCAL EDIT]`
  suffix).
- `VideoChangeLog` row with `source: youtube_pull, field: title`.
- No `videos.update` HTTP call to YouTube (YouTube already had the canonical
  value).
- `VideoDiff.last.resolved_at` populated.

### Step 6 — Repeat with Pito wins

Re-run Step 1 to re-introduce the divergence, then re-run Step 2 to re-detect
the diff. On the diff page, flip the radio to `[x] accept pito` and click
`[apply changes]`.

Expect:

- A `videos.update` HTTP request to YouTube with the new title (visible in
  `bin/rails console` log output, or in WebMock-style test stubs).
- `Video#title_changed_at` stamped (gated on Q1).
- `VideoChangeLog` row with
  `source: pito_apply, field: title, old_value: <original>, new_value: <... [LOCAL EDIT]>`.
- Redirect with flash `diff resolved (1 field pushed to youtube)`.

### Step 7 — Teardown

```
bin/rails console
> VideoDiff.destroy_all
> VideoChangeLog.delete_all
> Notification.where(kind: "video_diff_detected").destroy_all
> Video.first.update_columns(title: "<original title>")
> exit
```

## Cross-stack scope

| Surface           | Scope       | Notes                                                                                                                                                                                                                                                                                                             |
| ----------------- | ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rails web         | **In**      | Diff page, apply controller, sync button confirmation, flash banner, notification formatter. Lane 1 work.                                                                                                                                                                                                         |
| MCP               | **In**      | `video_diff_show` + `video_diff_apply` tools (Lane 2). Scope `app`. Two-step confirm flag on apply.                                                                                                                                                                                                               |
| Rails JSON API    | **In**      | `GET /videos/:slug/diff.json` returns the same payload as the MCP `video_diff_show` tool. `PATCH /videos/:slug/diff.json` consumes the same decisions hash. Used by the CLI lane.                                                                                                                                 |
| `pito` CLI (Rust) | **Skipped** | Tracked under the existing follow-up "CLI feature-parity sweep — channels list / videos list / settings panes / search results" (`docs/orchestration/follow-ups.md`). The CLI consumes the JSON API once it lands; sub-spec for the Rust client is a separate dispatch.                                           |
| Website           | **Skipped** | Marketing surface; no diff dialog there.                                                                                                                                                                                                                                                                          |
| Sidekiq job       | **In**      | `VideoDiffCheckJob` + `BulkVideoDiffCheckJob` + sidekiq-cron entry. Lane 1 work.                                                                                                                                                                                                                                  |
| Notifications     | **In**      | Phase 16 notification surface — `kind: video_diff_detected, severity: info`. Reuses the formatter pattern; new formatter partial per the spec. Discord / Slack webhook delivery (per realignment §"Notification surface + delivery channels") is upstream of this spec — fires automatically once the row exists. |

## Open questions

The master agent answers these before dispatching 23a.

1. **14-day rate limit on video title changes.** YouTube enforces a 14-day
   cooldown on channel title / handle changes (Phase 7.5 §11a wired this for
   `Channel`). It's unclear whether the same rule applies to video titles. The
   spec assumes it does (Q1 = "yes") and adds the `title_changed_at` column +
   `title_locked?` helper speculatively. Verify against the live YouTube Data
   API before 23a lands. If Q1 = "no", drop the column + helper from 23a's
   migration.

2. **Video diff retention.** Two options:
   - **Keep all resolved diffs.** Audit value high; storage low; the
     `video_diffs` table grows linearly with edits per video per day.
     Recommended.
   - **Expire resolved diffs after N days** (e.g., 90). Cheaper storage, less
     audit. Not recommended. Confirm before 23a.

3. **Diff page UX at scale.** When the user has 100+ videos and many have diffs,
   is one diff page per video sufficient? Or do we want a paginated diff index
   at `/diffs` that lists every open diff with quick-apply per row? Recommend
   per-video for v1; revisit after dogfooding.

4. **Field-level auto-resolve.** Should the user be able to configure
   per-channel rules like "always accept YouTube for `view_count`" so the diff
   dialog only surfaces fields without a rule? Recommend NO for v1; revisit
   after dogfooding. Display-only fields (`view_count`, `like_count`, etc.) are
   already auto-pulled — the only fields surfaced in the diff dialog are the
   writable ones from `Video::WRITABLE_FIELDS` minus any fields the user already
   resolved a rule for.

5. **Daily cron schedule — separate or combined?** Step 11's
   `ChannelDiffCheckJob` already has its own cron. Should `VideoDiffCheckJob`'s
   cron be combined into the same daily tick, or run separately? Recommend
   **separate** for two reasons:
   - Different quota budgets — channels use `channels.list` (1 unit × N
     channels, usually < 50), videos use `videos.list` (1 unit × N videos,
     potentially thousands). One job blowing through daily quota shouldn't take
     the other down.
   - Independent failure surfaces — a quota-exhausted video pass shouldn't mask
     a channel diff.

6. **Quota math sanity check.** With 1 connected channel and 500 videos, the
   daily pass costs ~500 units (1 unit per `videos.list`). With 4 connected
   channels averaging 500 videos each, that's ~2000 units / day just for video
   diff checks. YouTube's default daily quota is 10,000 units, so this leaves
   plenty of headroom for the rest of pito's API usage — but confirm before
   23d's cron schedule lands. If headroom is tight, the spec's recommendation to
   "skip videos older than X days from last edit" is a real lever; otherwise
   leave it off for v1.

7. **CLI sub-spec timing.** The CLI surface is explicitly out of scope for this
   phase, but the JSON API endpoints land here. When does the CLI consume them —
   immediately after 23d, or bundled into the next CLI parity sweep? Master
   agent's call.

8. **Step 11 / 11i refactor scope.** The spec calls for extracting
   `shared/_diff_table.html.erb` and `DiffDecisionRadioComponent` and
   refactoring the existing channel diff view to consume them. The 11i
   implementation landed before this spec — does the rails-impl agent touch
   `app/views/channels/diff.html.erb` in the same dispatch as 23b, or is the
   channel refactor a follow-up commit? Recommend same dispatch — the shared
   partial is most useful when it's shared from day one. Confirm with master
   agent.
