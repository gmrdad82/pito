# Phase 7.5 — Step 11i — Daily Channel Diff-Check Cron + Diff Resolution Page

> Sub-spec of Step 11 (Channel Detail Page). Implements the diff-detection half
> of the "YouTube is source of truth, but Pito edits can be pushed back"
> contract: a daily cron diff-check, a side-by-side resolution page, and the
> user-triggered `[sync]` button that piggybacks on the same path.
>
> Source of truth: parent Step 11 spec, Locked decisions **D11** (on-connect +
> on-demand + daily diff-check cron) and **D20** (bidirectional `[accept pito]`
> / `[accept youtube]` per-field decision + single `[apply changes]` button),
> plus the **Q7** resolution that turned the user-triggered `[sync]` button into
> a diff trigger rather than a one-way overwrite.

---

## Goal

Keep the Pito-side cache of channel metadata aligned with YouTube without ever
silently overwriting either side. A daily Sidekiq cron job fetches the
authoritative state from YouTube for every connected channel, computes a field-
by-field diff against the local cache, and — if anything changed — persists a
`ChannelDiff` row, emits a notification, and renders an in-page banner on the
channel show page. The user opens the diff page, makes a per-field decision
between `[accept pito]` (push the Pito value to YouTube) and `[accept youtube]`
(update the local cache from YouTube), and clicks `[apply changes]` to commit
the resolution. The same path is reused when the user clicks `[sync]` on the
show page: it does NOT overwrite anything; it enqueues a single-channel diff
check that surfaces the same banner.

This locks in the bidirectional posture from D20: YouTube remains the default
source of truth (the default radio for every field is `accept youtube`), but
nothing is overwritten without the user's explicit per-field decision.

## Files touched

### Migration

- `db/migrate/<TS>_create_channel_diffs.rb` — new `channel_diffs` table (see
  Schema below).

### Models

- `app/models/channel_diff.rb` — new model. Validations, associations, jsonb
  shape helpers, the `resolved?` predicate, the open / resolved scopes.
- `app/models/channel.rb` — add the `has_many :channel_diffs` association and
  the `open_channel_diff` convenience accessor (`channel_diffs.unresolved.first`
  — there is at most one per channel by partial unique index).

### Services

- `app/services/channels/diff_computer.rb` — new PORO. Takes a `Channel` and a
  normalized YouTube response hash; returns a `field_diffs` hash of
  `{ field_name: { pito:, youtube: } }` containing ONLY the fields that
  semantically differ. Owns the whitelist of fields-that-count-as-diffs.

### Jobs

- `app/jobs/channel_diff_check_job.rb` — new Sidekiq job. Two invocation modes:
  cron-wide (`perform`, iterates every connected channel) and single-channel
  (`perform(channel_id:)`, used by the `[sync]` button and by tests). Idempotent
  on re-run.

### Controllers

- `app/controllers/channels/diffs_controller.rb` — new. `#show` renders the
  resolution page; `#apply` commits the per-field decisions in a transaction.
  Namespaced under `Channels::` so the routes file can scope cleanly:
  `resources :channels do scope module: :channels do resource :diff, only: [:show] do post :apply end end end`
  (final shape: the implementation agent picks the cleanest REST variant; the
  spec contract is the two URLs below).

### Views

- `app/views/channels/diffs/show.html.erb` — new. Side-by-side resolution page.
- `app/views/channels/diffs/_decision_row.html.erb` — new. One row per diffing
  field. Three columns: Pito value · YouTube value · radio pair `[accept pito]`
  / `[accept youtube]`.
- `app/views/channels/show.html.erb` — edit. Add the
  `_open_diff_banner.html.erb` render at the top of the pane content when
  `@channel.open_channel_diff` is present. The banner copy is "YouTube has X
  newer values. [review changes]" linking to the diff page.
- `app/views/channels/_open_diff_banner.html.erb` — new. The banner partial.
  Pulled out so the Turbo Stream broadcast on `[sync]`-triggered diff completion
  can target the same DOM node by ID (`#open-diff-banner`).

### Config

- `config/sidekiq_cron.yml` — new entry:

  ```yaml
  channel_diff_check_job:
    cron: "0 4 * * *" # daily at 04:00 UTC
    class: "ChannelDiffCheckJob"
    queue: default
    description: "Daily diff-check every connected channel against YouTube"
  ```

- `config/routes.rb` — edit. Add the diff sub-resource under `channels`.

### Notifications (Phase 16 surface — produce only)

- The Phase 16 notification kind `channel_diff_detected` does not exist yet; the
  job emits via the existing notification scaffolding from Step 11 (or via the
  Step-11 placeholder seam if Phase 16 has not landed when this spec ships).
  This spec defines the **payload shape** the producer emits:

  ```json
  {
    "kind": "channel_diff_detected",
    "severity": "info",
    "channel_id": 42,
    "deep_link": "/channels/<slug>/diff",
    "field_count": 3
  }
  ```

  If the notification table / framework is not yet in place when this sub-spec
  is implemented, the producer call goes through whatever seam Step 11's parent
  spec defines (placeholder log line or stubbed `Notifications::Emit` service).
  Surface this on the open question Q-NOTIF below.

### Specs

- `spec/models/channel_diff_spec.rb` — new.
- `spec/services/channels/diff_computer_spec.rb` — new.
- `spec/jobs/channel_diff_check_job_spec.rb` — new.
- `spec/requests/channels/diffs_spec.rb` — new.
- `spec/system/channel_diff_resolution_spec.rb` — new (one thin system spec for
  the critical user journey only, per Spec Pyramid rule D10).

## Schema

`channel_diffs` table:

| column                | type      | notes                                                                       |
| --------------------- | --------- | --------------------------------------------------------------------------- |
| `id`                  | bigserial | PK.                                                                         |
| `channel_id`          | bigint    | FK → `channels.id`, NOT NULL, indexed.                                      |
| `detected_at`         | timestamp | NOT NULL. When the diff was first observed.                                 |
| `field_diffs`         | jsonb     | NOT NULL, default `{}`. Shape `{ field: { pito:, youtube: } }`.             |
| `resolved_at`         | timestamp | nullable. Set when `[apply changes]` succeeds.                              |
| `resolved_by_user_id` | bigint    | FK → `users.id`, nullable.                                                  |
| `resolution_payload`  | jsonb     | nullable. Shape `{ field: { decision: "pito"\|"youtube", value: <final> }}` |
| `created_at`          | timestamp | NOT NULL.                                                                   |
| `updated_at`          | timestamp | NOT NULL.                                                                   |

Indexes:

- `index :channel_diffs, :channel_id`
- **Partial unique index** ensuring at most one open diff per channel:
  `add_index :channel_diffs, :channel_id, unique: true, where: "resolved_at IS NULL", name: "index_channel_diffs_on_channel_id_open"`

The partial unique index is load-bearing. Cron re-runs UPSERT into the existing
open row via "find or create by `channel_id WHERE resolved_at IS NULL`" — the
DB-level constraint guards against the race where two cron passes overlap.

## Diff computer contract

`Channels::DiffComputer.new(channel, youtube_payload).call` returns a hash:

```ruby
{
  title:       { pito: "Old title", youtube: "New title" },
  description: { pito: "...",       youtube: "..." },
  # only fields that semantically differ
}
```

Rules:

1. **Whitelist of fields that count as diffs.** Only these comparisons produce
   rows:
   - `title`
   - `handle`
   - `description`
   - `country`
   - `default_language`
   - `keywords` (compared as a sorted set, not as a raw string — order-only
     changes do NOT diff)
   - `links` (compared as a sorted array of `{title, url}` tuples)
   - `banner_url` — see filter rule below
   - `avatar_url` — see filter rule below
   - `watermark_url` — see filter rule below
   - `watermark_timing`
   - `watermark_offset_ms`

2. **Statistics are display-only.** Stats fields (`subscriber_count`,
   `view_count`, `video_count`) are refreshed silently on every cron pass and do
   NOT contribute to the diff. The job writes them to the channel row directly.

3. **CDN-rotation filter for asset URLs.** YouTube re-issues CDN URLs for banner
   / avatar / watermark assets even when the underlying asset is unchanged. The
   diff computer compares by **content hash** when available (stored alongside
   the URL in the channel row by Phase 7's connect path; see open question
   Q-CDN), and falls back to comparing the URL path stripped of query string and
   CDN host prefix. Hash mismatch OR stripped-path mismatch triggers a diff;
   query-string-only rotation does not.

4. **Nil-vs-empty normalization.** `nil`, `""`, and `[]` are treated as
   equivalent. A channel that has never had keywords does not diff against a
   YouTube response that omits the keywords array.

5. **No side effects.** The computer is a pure function. It does not write to
   the channel, does not enqueue jobs, does not log. The job orchestrates.

## Job contract

`ChannelDiffCheckJob` has two invocation modes:

```ruby
# Cron mode — daily 04:00 UTC, iterates all connected channels.
ChannelDiffCheckJob.perform_later

# Single-channel mode — used by the [sync] button and by tests.
ChannelDiffCheckJob.perform_later(channel_id: channel.id)
```

`#perform(channel_id: nil)`:

1. Determine the channel scope: `channel_id` present → single channel,
   `Channel.find(channel_id)`; otherwise →
   `Channel.where.not(youtube_connection_id: nil)`.
2. For each channel in scope:
   1. Call
      `Youtube::Client.new(channel.youtube_connection).fetch_channel(channel)`.
   2. Update statistics columns silently (`subscriber_count`, `view_count`,
      `video_count`) in a small UPDATE.
   3. Run `Channels::DiffComputer.new(channel, payload).call` to get
      `field_diffs`.
   4. If `field_diffs.empty?` → close any stale open `ChannelDiff` for this
      channel that no longer has any diff (set `resolved_at = Time.current`,
      `resolved_by_user_id = nil`,
      `resolution_payload = { auto_closed: true }`). Continue to next channel.
   5. If `field_diffs.present?`:
      - **Upsert**: find the open `ChannelDiff` for this channel (partial unique
        index guarantees at most one). If present → refresh `field_diffs` and
        `detected_at`. If absent → create a new row.
      - **Notify**: emit one `channel_diff_detected` notification IF this is a
        fresh row (newly created) OR the set of diffing fields has expanded.
        Dedupe: if the same `field_diffs.keys` were already in the open row, do
        NOT re-notify. See Q-NOTIF.
      - **Broadcast**: if this is a single-channel run triggered by `[sync]`,
        broadcast a Turbo Stream to the channel show page replacing
        `#open-diff-banner` with the rendered partial.
3. Failure handling per channel:
   - `Youtube::Client::TransientError` → log + skip this channel + continue the
     iteration. Sidekiq's retry handles the next cron pass.
   - `Youtube::Client::QuotaExceededError` → log + STOP the iteration (no point
     burning more retries today) + raise so Sidekiq retries tomorrow's window.
     Single-channel mode re-raises immediately.
   - `Youtube::Client::NeedsReauthError` → mark the channel `connected = false`
     (matches Phase 7's contract) + skip + continue. Do NOT create / refresh a
     diff for a channel that just lost auth.
4. Idempotency: re-running the job within the same cron window with no YouTube
   changes is a no-op (no new diff rows, no duplicate notifications, no
   broadcasts).

## Resolution page contract

`GET /channels/:slug/diff`:

- Loads the channel by slug; 404 if no open diff exists.
- Renders a `pane--standalone` containing:
  - `<h1>Resolve diff — <channel.title></h1>`
  - Lead paragraph (one sentence per line, per project convention B): "YouTube
    is the source of truth.<br>Pick `accept youtube` to update your local
    cache.<br>Pick `accept pito` to push your local value back to YouTube."
  - A form
    (`form_with model: @channel_diff, url: apply_channel_diff_path(@channel), method: :post`)
    containing one `_decision_row` partial per field in
    `@channel_diff.field_diffs`. Each row:
    - Left column header: "Pito" with the current local value rendered as text
      (truncated to 80 chars with a `[show full]` disclosure link for long
      descriptions).
    - Middle column header: "YouTube" with the incoming value rendered the same
      way.
    - Right column: two radio inputs, `name="decisions[<field>]"`, values
      `"pito"` and `"youtube"`, labels `[accept pito]` and `[accept youtube]`.
      Default `checked`: `youtube` (per D20).
  - Bottom: `[apply changes]` submit button + `[cancel]` link back to
    `/channels/:slug`.
- Only fields with diffs render rows. Fields that agree are omitted.

`POST /channels/:slug/diff/apply`:

1. Authn / authz guard (any signed-in user — single-install + multi-user, per
   project convention F).
2. Load the open `ChannelDiff` for the channel. If absent (race: another user
   already resolved it), redirect to `/channels/:slug` with flash "This diff was
   already resolved."
3. Validate the submitted `decisions` hash:
   - Every key must be in `@channel_diff.field_diffs.keys` (reject extras).
   - Every key in `field_diffs.keys` must be present (reject incomplete).
   - Every value must be `"pito"` or `"youtube"` (yes/no boundary rule E does
     not apply here — these are domain enums, not booleans).
   - On validation failure → re-render `show` with 422 `:unprocessable_content`.
4. Wrap in `ActiveRecord::Base.transaction`:
   - For each `field, decision` pair:
     - `decision == "youtube"` → assign
       `channel[field] = field_diffs[field]["youtube"]`. Stage on the in-memory
       channel.
     - `decision == "pito"` → call
       `Youtube::Client.new(channel.youtube_connection).update_channel(channel, { field => field_diffs[field]["pito"] })`.
       (Per-field push so partial failures localize. Implementation agent may
       batch by API resource part — `snippet`, `branding`, etc. — if the YouTube
       API requires it; the spec contract is "one decision per field".)
   - After all decisions are processed, persist the staged channel changes
     (`channel.save!`).
   - For each field with `decision == "pito"` where
     `field.in?(%w[title handle])`, write a `ChannelChangeLog` row matching Step
     11g's audit table contract.
   - Mark the diff resolved: `resolved_at = Time.current`,
     `resolved_by_user_id = Current.user.id`, `resolution_payload` =
     `{ field => { decision:, value: <final> } }` for every field.
5. On success → redirect to `/channels/:slug` with flash
   `"Changes applied. N fields pushed to YouTube, M updated locally."`.
6. On `Youtube::Client::*Error` raised inside the transaction → rollback,
   re-render `show` with 422 `:unprocessable_content`, flash
   `"Could not push <field> to YouTube: <reason>. No changes applied."`. See
   Q-PARTIAL below — partial-failure UX is the architect-flagged open question.

## `[sync]` button reuse

Step 11b's channel show page already has a `[sync]` action wired to
`/syncs/channel/:ids` via the project-wide bulk-sync confirmation framework (per
`CLAUDE.md` hard rules). This sub-spec **does NOT** alter the URL shape or the
confirmation page. The change is in what the post-confirmation handler enqueues:

- Before this spec: `ChannelSync` placeholder job (no-op flip of `syncing`).
- After this spec: `ChannelDiffCheckJob.perform_later(channel_id: id)` for each
  id in the bulk operation.

The `syncing` flag on `Channel` is still toggled true on enqueue and back to
false in the job's `ensure` block, preserving the existing show-page indicator.
Once the job finishes:

- If a diff was detected → the Turbo Stream broadcast (above) injects the banner
  partial into `#open-diff-banner` on every open show-page tab for that channel.
- If no diff was detected → broadcast an empty turbo-stream that clears
  `#open-diff-banner` and a transient flash-style notice
  `"In sync with YouTube."` (rendered into a 5-second-autodismiss target that
  Step 11b already defines, or a new one if Step 11b did not define one — flag
  to architect-review).

## Acceptance

- [ ] Migration creates `channel_diffs` with the columns, the FK to `channels`,
      the FK to `users`, the `channel_id` index, and the partial unique index on
      `channel_id WHERE resolved_at IS NULL`.
- [ ] `ChannelDiff` model: belongs_to `:channel`, belongs_to
      `:resolved_by_user, class_name: "User", optional: true`; validates
      `field_diffs` is a hash; scopes `unresolved` (`resolved_at IS NULL`) and
      `resolved`; predicate `resolved?`.
- [ ] `Channel` model gains `has_many :channel_diffs, dependent: :destroy` and
      `open_channel_diff` returning `channel_diffs.unresolved.first`.
- [ ] `Channels::DiffComputer.call` returns a hash with ONLY the diffing fields;
      statistics fields never appear; CDN-rotation-only changes for banner /
      avatar / watermark URLs never appear; nil / "" / [] are equivalent.
- [ ] `ChannelDiffCheckJob.perform_later` runs the daily-cron flow over every
      `Channel.where.not(youtube_connection_id: nil)`.
- [ ] `ChannelDiffCheckJob.perform_later(channel_id:)` runs the single-channel
      flow.
- [ ] Statistics columns are refreshed silently on every job pass.
- [ ] An existing open `ChannelDiff` for a channel is updated in place when the
      job re-runs; no duplicate row is created (DB-level partial unique index
      enforced).
- [ ] An open diff is auto-closed (`resolved_at` set,
      `resolution_payload =     { auto_closed: true }`) when a subsequent cron
      pass finds no diffs.
- [ ] `TransientError` per-channel is logged and skipped; the iteration
      continues; the job exits 0 so Sidekiq does not retry the entire batch.
- [ ] `QuotaExceededError` aborts the cron iteration; Sidekiq retries tomorrow.
- [ ] `NeedsReauthError` flips `channel.connected = false` and does NOT create a
      diff row.
- [ ] The Phase 16 `channel_diff_detected` notification is emitted on fresh-row
      detection AND on expansion of the diffing field set; deduped on no-change
      and contraction.
- [ ] `config/sidekiq_cron.yml` has the new `channel_diff_check_job` entry at
      `0 4 * * *`.
- [ ] `GET /channels/:slug/diff` renders the side-by-side resolution page only
      if an open diff exists for the channel; returns 404 otherwise.
- [ ] Only diffing fields render rows; agreeing fields are omitted.
- [ ] Each row's default radio is `accept youtube`.
- [ ] `[apply changes]` validates the `decisions` hash, rejects extras, rejects
      incomplete submissions, rejects unknown values.
- [ ] On success, each `accept_pito` field calls
      `Youtube::Client#update_channel` with the single-field payload; each
      `accept_youtube` field writes the local column; `title` and `handle`
      pushes write a `ChannelChangeLog` row; the `ChannelDiff` is marked
      resolved with `resolved_by_user_id` and `resolution_payload`.
- [ ] On `Youtube::Client` failure mid-apply, the transaction rolls back; the
      channel is unchanged; the diff is unchanged; the user lands back on the
      diff page with a 422 + a flash naming the failing field.
- [ ] The `/channels/:slug` show page renders the `_open_diff_banner` partial at
      the top of the pane when `@channel.open_channel_diff.present?`.
- [ ] The `[sync]` button's confirmation handler enqueues
      `ChannelDiffCheckJob.perform_later(channel_id: id)` per channel rather
      than the legacy `ChannelSync` no-op.
- [ ] On `[sync]` completion, a Turbo Stream replaces `#open-diff-banner` with
      the latest state (banner if a diff was detected, empty otherwise).
- [ ] All endpoints / surfaces use the `[label]` bracketed-link convention
      (project rule A) — `[review changes]`, `[accept pito]`,
      `[accept youtube]`, `[apply changes]`, `[cancel]` — no inner spaces.
- [ ] Lead paragraph copy on the diff page uses the one-sentence-per-line
      `<br>`-separated style (project rule B).
- [ ] Resolution page uses `pane--standalone` (project rule C); no
      `framed-block`.
- [ ] No JS `confirm` / `alert` / `prompt` / `data-turbo-confirm` anywhere in
      the new code; the `[sync]` confirmation goes through the existing
      `/syncs/channel/:ids` framework (project hard rule).
- [ ] Spec sweep complete: model, service, job, request, system (per spec
      pyramid rule D).

## Spec coverage (mandatory sweep)

### `spec/models/channel_diff_spec.rb`

- Validations: `field_diffs` must be a Hash; `channel` required; default
  `field_diffs` is `{}`.
- Associations: `belongs_to :channel`;
  `belongs_to :resolved_by_user, class_name: "User", optional: true`.
- Scopes: `unresolved` returns rows with `resolved_at IS NULL`; `resolved`
  returns the complement.
- Predicate: `resolved?` returns the right boolean for both states.
- Partial unique index: creating a second open row for the same channel raises
  `ActiveRecord::RecordNotUnique`; creating a second row when the first is
  resolved succeeds.
- jsonb shape helper (if exposed): `diffing_fields` returns
  `field_diffs.keys.sort`.

### `spec/services/channels/diff_computer_spec.rb`

Happy:

- All whitelisted fields match → returns `{}`.
- Title differs → returns `{ title: { pito:, youtube: } }`.
- Multiple fields differ → returns each.

Sad:

- Statistics differ → still returns `{}` (stats not in whitelist).
- `nil` vs `""` vs `[]` are equivalent → no diff produced.
- Keywords array reordered → no diff (sorted-set comparison).
- Links reordered → no diff.

Edge:

- Banner URL query-string-only rotation → no diff.
- Banner URL path changes → diffs.
- Avatar / watermark URL same shape.
- Description with trailing whitespace differences only → flag whether this
  diffs or not (open question Q-WHITESPACE; default: trim before compare).

Flaw:

- YouTube payload missing an expected key → treat as `nil` per normalization
  rule 4; do not raise.
- YouTube payload contains a field NOT in the whitelist (e.g. an experimental
  field) → ignored silently.

### `spec/jobs/channel_diff_check_job_spec.rb`

Happy:

- Cron mode, three connected channels, one differs → exactly one open
  `ChannelDiff` row created; statistics refreshed on all three; one
  `channel_diff_detected` notification emitted.
- Single-channel mode + the channel has a diff → one row created, one
  notification, one Turbo Stream broadcast to the channel's show-page stream.
- Single-channel mode + no diff → no row, no notification, but a Turbo Stream
  broadcast clearing `#open-diff-banner` and surfacing the "in sync" notice.

Sad:

- An open `ChannelDiff` row already exists with the same diffing fields → the
  row's `field_diffs` and `detected_at` are refreshed; NO duplicate row; NO
  duplicate notification (dedupe by field-set).
- An open `ChannelDiff` row exists; the new pass finds an EXPANDED diffing field
  set → row refreshed, new notification emitted.
- An open `ChannelDiff` row exists; the new pass finds NO diffs → row
  auto-closed with `resolution_payload = { auto_closed: true }`.

Edge:

- `Youtube::Client::TransientError` for channel 2 of 3 → channels 1 and 3 are
  processed normally; channel 2 is logged and skipped; job exits 0.
- `Youtube::Client::QuotaExceededError` for channel 2 of 3 → channel 1
  processed; iteration aborts; the job re-raises so Sidekiq retries the cron
  window (or schedules tomorrow, depending on Sidekiq config).
- `Youtube::Client::NeedsReauthError` for channel 2 of 3 → channel 2 flipped to
  `connected = false`; NO `ChannelDiff` row created for channel 2; channels 1
  and 3 continue.
- Channels with `youtube_connection_id IS NULL` are skipped entirely (cron
  mode).
- Running the job twice in a row with no YouTube changes → second run is a total
  no-op: no row, no notification, no broadcast.

Flaw:

- Two cron passes overlap (one channel processed simultaneously by two job
  instances) → the partial unique index guarantees one open row; the second
  insert raises `ActiveRecord::RecordNotUnique`; the second pass rescues +
  retries the upsert as an update.

### `spec/requests/channels/diffs_spec.rb`

Happy:

- `GET /channels/:slug/diff` with an open diff → 200, renders the rows, default
  radios are `accept youtube`.
- `POST /channels/:slug/diff/apply` with all radios = `youtube` → channel fields
  updated from `field_diffs[field].youtube`; no YouTube API call; `ChannelDiff`
  resolved; redirect 302 with flash
  `"Changes applied. 0 fields pushed to YouTube, N updated locally."`.
- `POST /channels/:slug/diff/apply` with all radios = `pito` →
  `Youtube::Client#update_channel` called per field (or per resource part);
  channel local columns unchanged; `ChannelChangeLog` rows written for `title` /
  `handle`; redirect 302 with flash naming the pushed count.
- Mixed `pito` / `youtube` decisions → both code paths exercised; counts in
  flash match.

Sad:

- `GET /channels/:slug/diff` with no open diff → 404.
- `POST /channels/:slug/diff/apply` with an extra key not in `field_diffs` →
  422, error flash mentioning the unknown field.
- `POST /channels/:slug/diff/apply` missing a key that IS in `field_diffs` →
  422, error flash mentioning the missing field.
- `POST /channels/:slug/diff/apply` with a value other than `pito` / `youtube`
  → 422.

Edge:

- Concurrent resolution: user A submits `apply`, user B submits `apply` for the
  same diff a second later → the second request finds the diff already resolved,
  redirects to `/channels/:slug` with "This diff was already resolved." flash.
- `[sync]` triggered while a diff page is open → Turbo Stream broadcast updates
  the banner; the open diff form on user A's tab still works.

Flaw:

- Old payload replay: a user submits `apply` with a stale set of decisions whose
  `field_diffs` set no longer matches the current open diff (cron has re-run
  between page load and submit) → 422, error flash "The diff changed while you
  were reviewing; please re-open the page."
- Partial failure: `Youtube::Client#update_channel` raises for field 2 of 3 →
  the whole transaction rolls back; channel is unchanged; diff is unchanged; no
  `ChannelChangeLog` rows written; user lands on the diff page with a 422 flash
  naming the failing field.

### `spec/system/channel_diff_resolution_spec.rb`

One thin scenario (per spec pyramid rule D10 — system specs are selective):

- Given a connected channel with a stubbed YouTube payload that differs in title
  and description, when the daily cron runs, then a banner appears on
  `/channels/:slug`, when the user clicks `[review changes]`, then they see two
  rows, when they pick `[accept youtube]` for title and `[accept pito]` for
  description and click `[apply changes]`, then they land on `/channels/:slug`
  with the success flash, the local title is updated, the YouTube client
  received the description push, and the banner is gone.

## Manual test recipe

Preconditions:

- A connected channel exists (`Channel#youtube_connection_id` not null), the
  user is signed in, Sidekiq + Redis are running (`bin/dev`).

Steps:

1. Modify the channel's local cached title to differ from the YouTube payload
   the stubbed `Youtube::Client` will return — easiest path in dev:
   `bin/rails runner 'Channel.first.update_columns(title: "Local divergent title")'`.
2. Trigger the diff check manually:
   `bin/rails runner 'ChannelDiffCheckJob.perform_now(channel_id: Channel.first.id)'`.
3. Open `/channels/<slug>`. Confirm the banner reads "YouTube has 1 newer
   values. [review changes]".
4. Click `[review changes]`. Confirm the diff page lists exactly one row for
   `title` with the YouTube value in the middle column and your divergent local
   value in the left column.
5. Confirm the default radio is `[accept youtube]`.
6. Switch the radio to `[accept pito]` and click `[apply changes]`. Confirm you
   redirect to `/channels/<slug>` with a flash naming
   `1 fields pushed to YouTube, 0 updated locally`.
7. Confirm the banner is gone, the local title is unchanged (still "Local
   divergent title"), and a `ChannelChangeLog` row exists:
   `bin/rails runner 'pp ChannelChangeLog.last.attributes'`.
8. Re-run step 2. Confirm no new `ChannelDiff` row is created (the push made the
   sides agree).
9. Reset:
   `bin/rails runner 'Channel.first.update_columns(title: "<actual youtube title>"); ChannelDiff.delete_all'`.

Cron schedule manual check:

- `bin/rails runner 'pp Sidekiq::Cron::Job.find("channel_diff_check_job").attributes'`
  → confirms the cron entry registered with `"0 4 * * *"`.

## Cross-stack scope

- **Rails** — in scope.
- **`pito` CLI** — skipped. The diff resolution surface is web-only for now. The
  CLI displays connected channels but does not (yet) own the resolution UX. Open
  question Q-CLI below.
- **MCP** — skipped. No MCP tool surfaces channel diff resolution. The
  `channel_diff_detected` notification surface is web-only for Phase 7.5. Future
  surface (Phase 9+) may add `list_channel_diffs` / `resolve_channel_diff`
  tools.
- **Website (Cloudflare Pages)** — out of scope.

## Open questions

- **Q-NOTIF — Notification dedupe granularity.** The spec recommends deduping by
  the SET of diffing field names: notify on fresh row, notify on expansion of
  the set, no notify on no-change or contraction. Alternative: notify on every
  cron tick where a diff exists (noisier but no missed signal). Architect lean:
  dedupe by field-set. User confirm or flip.

- **Q-DEFAULT — Default radio per row.** Spec defaults to `accept youtube` per
  Locked decision D20 (YouTube source of truth). Alternative: no default, force
  explicit pick (radios un-checked, `[apply changes]` disabled until all rows
  have a decision). User confirm or flip.

- **Q-PARTIAL — Partial-failure UX on multi-field push.** Spec wraps everything
  in a transaction and rolls back on any field failure. Alternative: commit
  successful field pushes, present a follow-up diff page for the failed ones.
  Architect lean: transaction with rollback is safer and matches the user's
  mental model ("apply changes" is atomic); add a clear flash naming the failing
  field. User confirm.

- **Q-CDN — Banner / avatar / watermark URL diff filtering.** YouTube CDN
  rotates these URLs without semantic change. The spec proposes content-hash
  comparison (requires storing the hash alongside the URL at connect-time — may
  need a small migration to add `*_hash` columns to `channels` if not already
  present from Phase 7) plus a fallback of stripped-path comparison. User
  confirm the approach AND confirm whether the hash columns already exist; if
  not, this sub-spec needs a small `add_column` migration too.

- **Q-WHITESPACE — Description normalization on diff compare.** Trim leading /
  trailing whitespace and collapse internal whitespace before comparing? Or
  treat whitespace differences as real diffs? Architect lean: trim + collapse
  before compare. Easy to flip in the diff computer; surface for confirmation.

- **Q-CLI — CLI resolution UX.** Should `pito` (CLI) surface a banner on its
  channel-detail screen pointing the user to the web for resolution, or stay
  silent until a dedicated CLI resolution flow ships? Architect lean: silent for
  Phase 7.5; revisit when Phase 9 CLI parity work lands. Defer the decision;
  mark CLI surface skipped in this spec.

- **Q-SYNC-NOTICE — "In sync" notice target.** The Turbo Stream broadcast on a
  no-diff `[sync]` completion needs a target in the show-page DOM. Does Step 11b
  already define a flash-style autodismiss target the broadcast can inject into?
  If not, this sub-spec needs to define one. Architect-review: cross-check Step
  11b's show.html.erb before implementation dispatches.

- **Q-CHANGELOG-FIELDS — Audit fields beyond `title` / `handle`.** Step 11g's
  `ChannelChangeLog` audits the two human-identity fields. Should pushes for
  other fields (description, country, language, keywords) also write audit rows?
  Architect lean: not in this sub-spec; keep the audit narrow until the user has
  data on what's worth auditing. User confirm.

- **Q-NOTIF-SEAM — Step 11 notification scaffolding.** Where does the
  `channel_diff_detected` notification get emitted from if Phase 16 has not
  landed yet? Step 11's parent spec defines a placeholder seam; this sub-spec's
  job calls into that seam. Architect-review: confirm the seam exists before
  dispatching this sub-spec. If not, the seam is added as part of this
  sub-spec's scope (small extension to the parent Step 11 work).
