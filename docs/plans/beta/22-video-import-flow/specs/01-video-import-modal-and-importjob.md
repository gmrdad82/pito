# Phase 22 — Step 01 — Video Import Modal + ImportJob

> Introduce `[import]` on `/videos`. First-class affordance, NOT a
> keybinding-only feature. Click opens a modal; the modal walks channel
> selection, per-channel background jobs, live progress, and a keep/reject
> confirmation table. Rejected videos land in a `RejectedVideoImport`
> tombstone so the daily sync never re-imports them. Source of truth: B6 of
> `docs/notes/2026-05-10-22-29-58-reply-to-keybindings-and-future-development.md`.

---

## 1. Goal

Give the user a single, low-friction surface for pulling fresh videos from
their connected YouTube channels into pito, with explicit per-row control over
what stays and what gets permanently rejected. The flow must:

- Stay on `/videos` (modal, not navigation) so the user keeps their context.
- Treat each channel as an independent import unit — one `ImportJob`, one
  Sidekiq job, one retry lane.
- Diff against existing `Video` rows so re-runs only fetch new uploads.
- Diff against `RejectedVideoImport` rows so previously-rejected uploads stay
  rejected forever (no soft-delete loops on the next daily sync).
- Surface progress on both the modal and the channel show page so the user can
  navigate away without losing visibility.
- End with a keep/reject confirmation table that defaults to "keep everything"
  and converts unchecked rows into genuine `Video#destroy` + tombstone inserts.

This is the videos-side counterpart to the existing channel sync framework. It
is NOT the daily diff sync (B2 in the same Mobile note — separate phase) and
it does NOT push to YouTube — it only pulls metadata for newly-discovered
uploads.

## 2. Scope

In scope:

- New `import_jobs` table + `ImportJob` model.
- New `rejected_video_imports` table + `RejectedVideoImport` model.
- `[import]` button on `/videos` index (web).
- Turbo-frame modal with four logical steps (selection, confirm, progress,
  keep/reject).
- `Imports::ChannelsController` (HTML + JSON branches).
- `Channel::ImportVideosJob` Sidekiq worker, one per selected channel.
- `Channels::VideoImporter` service object — the seam between the model layer
  and the YouTube API call.
- Channel show page badge / inline indicator when an `ImportJob` is in flight.
- Notification dispatch on `ImportJob` completion (success and failure).
- Per-user rate limit on the enqueue endpoint (5-second cache lock).
- yes/no boundary conversion on every external surface.
- Full spec pyramid coverage (see §10).

Out of scope (open questions to resolve first, or follow-up phases):

- Sort/filter on the keep/reject table (waits for the `f` / `s` keybinding
  schema lock — see plan.md open question 4).
- Tombstone reversal UX (open question 5).
- The CLI surface for this flow. The JSON branch lands so the CLI can pick it
  up later; the actual `pito` subcommand is a separate spec.
- The MCP tool wrapper. Same reasoning — JSON contract lands; tool wrapping
  defers until the auth phase reshuffles the MCP scope catalog.
- Daily background diff sync (B2 in the same Mobile note) — separate phase.
- Real YouTube API wiring. The `Channels::VideoImporter` service has a single
  injection point for the upstream call; tests stub it. Live wiring is Phase
  7 / Phase 8 territory.

## 3. Files touched

### Migrations + schema

- `db/migrate/<ts>_create_import_jobs.rb`
- `db/migrate/<ts>_create_rejected_video_imports.rb`
- `db/schema.rb` (regenerated)

### Models

- `app/models/import_job.rb` (new)
- `app/models/rejected_video_import.rb` (new)
- `app/models/channel.rb` (associations: `has_many :import_jobs`,
  `has_many :rejected_video_imports`; helper scopes for "has an in-flight
  import")
- `app/models/video.rb` (no new columns; verify `dependent: :destroy` does not
  cascade to cross-channel state we care about preserving)

### Controllers + routes

- `app/controllers/imports/channels_controller.rb` (new) — `index`, `create`,
  `show`, `update` (the keep/reject confirm)
- `config/routes.rb`:
  ```ruby
  namespace :imports do
    resources :channels, only: %i[index create show update]
  end
  ```
- Friendly URL slugs preserved on the channel-side references via FriendlyId
  (consistent with existing channel routes).
- Auth gating via the existing `Sessions::AuthConcern` (applied at the
  `Imports::ChannelsController` level).

### Jobs

- `app/jobs/channel/import_videos_job.rb` (new) —
  `perform(channel_id, import_job_id)`; flat naming aligns with the existing
  `ChannelSync` precedent (see `CLAUDE.md` "Architecture notes").

### Services

- `app/services/channels/video_importer.rb` (new) — encapsulates the
  `playlistItems.list` walk, the diff against `videos` and
  `rejected_video_imports`, the row creation, and the counter updates. Single
  public method `call(channel:, import_job:)`. Yields per-page progress via a
  block so the job can broadcast Turbo Streams without the service knowing
  about Action Cable.

### Views + components

- `app/views/imports/channels/index.html.erb` (modal frame: channel-selection
  step)
- `app/views/imports/channels/_channel_row.html.erb` (selection-row partial:
  checkbox + label + in-flight badge)
- `app/views/imports/channels/show.html.erb` (modal frame: progress step)
- `app/views/imports/channels/_progress.html.erb` (per-channel progress block)
- `app/views/imports/channels/_keep_reject_table.html.erb` (post-import table)
- `app/views/imports/channels/update.turbo_stream.erb` (apply keep/reject)
- `app/views/imports/channels/show.turbo_stream.erb` (progress broadcast
  frame)
- `app/views/videos/index.html.erb` — add `[import]` button alongside the
  existing controls, next to the `[add]` affordance restored in B1.
- `app/views/channels/show.html.erb` — add in-flight-import badge / link that
  reopens the modal at the progress step.
- `app/components/imports/progress_indicator_component.rb` plus
  `progress_indicator_component.html.erb` — wraps the existing `=---`
  indicator with a per-channel "imported N of M" label when known.

### JSON (CLI/MCP parity branch)

- `app/views/imports/channels/index.json.jbuilder`
- `app/views/imports/channels/create.json.jbuilder`
- `app/views/imports/channels/show.json.jbuilder`
- `app/views/imports/channels/update.json.jbuilder`

Boolean fields serialized as `"yes"` / `"no"` strings — never raw booleans.
Status enum serialized as the string symbol (`"queued"`, `"running"`,
`"completed"`, `"failed"`).

### Locales

- `config/locales/en.yml` — labels for `[import]`, `[start import]`, `[keep]`,
  error copy ("an import is already running for this channel"), modal
  headings, progress lead paragraph (one sentence per line per architect rule
  B).

### Specs (all under `spec/`)

- `spec/models/import_job_spec.rb`
- `spec/models/rejected_video_import_spec.rb`
- `spec/models/channel_spec.rb` (extend — new associations, scopes)
- `spec/services/channels/video_importer_spec.rb`
- `spec/jobs/channel/import_videos_job_spec.rb`
- `spec/requests/imports/channels_spec.rb` (HTML + JSON branches)
- `spec/components/imports/progress_indicator_component_spec.rb`
- `spec/system/video_import_flow_spec.rb` (single end-to-end journey)
- `spec/factories/import_jobs.rb`
- `spec/factories/rejected_video_imports.rb`

### Docs

No project-doc changes expected. If the spec introduces a new component
pattern (the progress indicator component is borderline — it wraps an
existing `=---` indicator), the architect-docs agent updates `docs/design.md`
after the user validates.

## 4. Data model

### 4.1 `ImportJob`

Table: `import_jobs`.

| Column            | Type      | Constraints                         |
| ----------------- | --------- | ----------------------------------- |
| `id`              | bigint    | PK                                  |
| `channel_id`     | bigint    | FK to channels.id, NOT NULL, indexed |
| `status`          | string    | NOT NULL, default `"queued"`        |
| `total_videos`    | integer   | NOT NULL, default 0                 |
| `imported_videos` | integer   | NOT NULL, default 0                 |
| `failed_videos`   | integer   | NOT NULL, default 0                 |
| `error_payload`   | jsonb     | nullable                            |
| `started_at`      | timestamp | nullable                            |
| `completed_at`    | timestamp | nullable                            |
| `enqueued_by_id`  | bigint    | FK to users.id, NOT NULL            |
| `created_at`      | timestamp | NOT NULL                            |
| `updated_at`      | timestamp | NOT NULL                            |

Indexes:

- `(channel_id, status)` — supports the "is there an in-flight job for this
  channel?" scope.
- `(status, created_at)` — supports the dashboard / future audit views.

Status values: `queued`, `running`, `completed`, `failed`. Implemented via
`enum status: { queued: 0, running: 1, completed: 2, failed: 3 }` (integer
storage; surface as string in JSON).

Associations:

- `belongs_to :channel`
- `belongs_to :enqueued_by, class_name: "User"`

We deliberately do NOT add a `import_job_id` foreign key to `videos`. The
`imported_videos` counter is the canonical answer; videos created by an
import live independently after the import finishes. This keeps
`Video#destroy` cheap and avoids `dependent: :destroy` cascade surprises.

Validations:

- `status` presence, inclusion in the enum keys.
- `total_videos`, `imported_videos`, `failed_videos` non-negative.

Scopes:

- `in_flight` — `where(status: %i[queued running])`
- `for_channel(channel)` — `where(channel: channel)`
- `recent` — `order(created_at: :desc)`

Callbacks:

- `before_save :stamp_started_at` — when status transitions to `running` and
  `started_at` is nil.
- `before_save :stamp_completed_at` — when status transitions to `completed`
  or `failed` and `completed_at` is nil.

Public methods:

- `#progress_fraction` — returns `imported_videos.to_f / total_videos` capped
  at 1.0; returns 0.0 when `total_videos` is 0.
- `#in_flight?` — `queued? || running?`
- `#candidate_videos` — videos created on this channel between `started_at`
  and `completed_at` (used by `update` to enumerate the keep/reject set).

### 4.2 `RejectedVideoImport`

Table: `rejected_video_imports`.

| Column                | Type      | Constraints                          |
| --------------------- | --------- | ------------------------------------ |
| `id`                  | bigint    | PK                                   |
| `channel_id`          | bigint    | FK to channels.id, NOT NULL, indexed |
| `youtube_video_id`    | string    | NOT NULL                             |
| `rejected_at`         | timestamp | NOT NULL                             |
| `rejected_by_user_id` | bigint    | FK to users.id, NOT NULL             |
| `created_at`          | timestamp | NOT NULL                             |
| `updated_at`          | timestamp | NOT NULL                             |

Indexes:

- Unique `(channel_id, youtube_video_id)` — the contract that prevents a
  channel from re-tombstoning the same YouTube ID twice. The unique index
  also short-circuits race conditions where two parallel jobs would otherwise
  insert duplicates.

Associations:

- `belongs_to :channel`
- `belongs_to :rejected_by, class_name: "User"`

Validations:

- `youtube_video_id` presence, format (basic YouTube ID shape — 11-char
  base64-url-ish — match the existing validator used on `Video` if one
  exists, otherwise inline regex).
- `rejected_at` presence.

### 4.3 Why a table instead of a JSON column on `channels`

The Mobile note explicitly asks for a recommendation. The spec recommends the
table over a `jsonb` column on `channels` for these reasons:

- **Indexability.** The diff query at import time is
  `WHERE channel_id = $1 AND youtube_video_id IN (...)`. A unique compound
  index on the table runs in O(log n); a `jsonb @> ANY(...)` query against a
  jsonb array does not. The diff happens on every import AND every daily
  sync.
- **Concurrency.** Two parallel jobs (or a job plus a user-initiated
  keep/reject confirm running in different requests) racing to insert the
  same rejection collide cleanly on the unique index. A jsonb-array update
  has to read, mutate, write — which means either a transaction with
  `SELECT FOR UPDATE` or a race window.
- **Auditability.** `rejected_at` plus `rejected_by_user_id` give a real
  audit trail. A jsonb array of bare strings loses that without nested
  objects, which then defeats the indexability argument anyway.
- **Symmetry with existing patterns.** The codebase already uses small
  associated tables for similar "exclusion lists" (the channel deletion path
  cleans up associations cleanly per Phase 3 architecture notes). Following
  the existing pattern keeps the mental model uniform.

The cost — one extra table — is negligible. The decision stays a table.

### 4.4 `Video` deletion path

`Video#destroy` is the canonical delete. It already runs:

- `dependent: :destroy` on associations the model owns.
- The notification + audit cleanup any prior phase wired up.

The keep/reject confirm step uses `Video#destroy` (NOT a soft-delete column).
The same controller action inserts the matching `RejectedVideoImport` row in
the same transaction so the tombstone is durable before the destroy
completes.

Any background job that holds a stale `video_id` and tries to load the video
must rescue `ActiveRecord::RecordNotFound` and log-and-skip rather than fail
the job. This is a general policy beyond this spec, but the spec calls it out
explicitly for `Channel::ImportVideosJob` and any job we touch in passing
(audit log here is mandatory; global enforcement is a follow-up phase).

## 5. Controller + routes

### 5.1 Routes

```ruby
namespace :imports do
  resources :channels, only: %i[index create show update]
end
```

Yielding:

- `GET    /imports/channels`     — modal frame (channel selection step)
- `POST   /imports/channels`     — enqueue per-channel ImportJobs
- `GET    /imports/channels/:id` — per-ImportJob progress + keep/reject table
- `PATCH  /imports/channels/:id` — apply keep/reject decisions

The `:id` on `show` / `update` is the `ImportJob#id`. The controller is named
`Imports::ChannelsController` (the selection step lists channels and the
routes thread reads cleanly). A future `Imports::VideosController` could
exist for direct video imports without hurting the namespace.

### 5.2 `Imports::ChannelsController` actions

#### `index` (HTML + JSON)

Renders the modal frame at the channel-selection step. Lists every `Channel`
that's `connected: true`. Each row carries:

- The channel slug + label.
- Whether the channel currently has an `ImportJob#in_flight?` — if so, the
  checkbox is disabled and the row shows an in-flight badge with a link to
  the progress view (`GET /imports/channels/:id`).

JSON returns the same shape via jbuilder, with `connected` and `in_flight`
serialized as `"yes"` / `"no"`.

#### `create` (HTML + JSON)

Inputs:

- `channel_ids[]` — array of channel IDs (or slugs — controller accepts both,
  resolves to IDs).

Behavior:

- Auth gate via `Sessions::AuthConcern`.
- Per-user 5-second cache lock on the action via
  `Rails.cache.write("imports:enqueue:user:#{current_user.id}", true, expires_in: 5.seconds, unless_exist: true)`.
  If the lock is already set, respond 429 with the bracketed-link copy
  `[try again in a moment]`.
- For each `channel_id`:
  1. Validate the channel exists and is connected.
  2. Check there is no `ImportJob.in_flight.for_channel(channel).exists?`.
     If there is one and the user has selected this channel, reject per
     plan.md open question 1 (default proposed: refuse with explanatory
     message; surface a link to the existing job's progress view).
  3. Create an `ImportJob` in `queued` status with
     `enqueued_by: current_user`.
  4. Enqueue
     `Channel::ImportVideosJob.perform_later(channel.id, import_job.id)`.
- Respond with a turbo_stream that swaps the modal body to the progress step,
  listing every newly-enqueued ImportJob with its initial `=---` indicator.
- JSON returns `{ import_jobs: [...] }` with status + counters + ids.

#### `show` (HTML + JSON)

Inputs:

- `:id` — `ImportJob#id`.

Behavior:

- Renders the progress step for that one job, OR the keep/reject table if the
  job has completed.
- Polled every 2 seconds by a Stimulus controller on the modal (fallback;
  primary delivery is Turbo Stream broadcasts from the job itself).
- JSON returns the full job payload plus (if `completed`) the list of
  imported videos pending keep/reject.

#### `update` (HTML + JSON)

Inputs:

- `:id` — `ImportJob#id`.
- `keep_video_ids[]` — array of `Video#id` the user wants to keep.

Behavior:

- Resolve the candidate set via `ImportJob#candidate_videos` (videos for this
  channel created between `started_at` and `completed_at`).
- In a single transaction:
  - For every candidate video NOT in `keep_video_ids`:
    - Insert a `RejectedVideoImport` with `channel`, `youtube_video_id`,
      `rejected_at: Time.current`, `rejected_by: current_user`.
    - `video.destroy!`.
  - For every candidate video IN `keep_video_ids`: no-op.
- Respond with a turbo_stream that closes the modal and flashes a
  confirmation ("kept N, rejected M").
- JSON returns `{ kept: <count>, rejected: <count> }`.

### 5.3 Bulk-as-foundation reading

The `CLAUDE.md` hard rule says single-record destructive / sync actions are
bulk operations with a one-element id list (`/<action>s/:type/:ids`). The
keep/reject confirm IS a bulk destructive action (deleting N videos at
once). The controller's `update` action lives at `/imports/channels/:id`
because the "object" being updated is the `ImportJob`, not the set of
videos. The bulk destruction inside `update` happens via the standard
ActiveRecord delete in a single transaction. This does NOT route through
`DeletionsController` because the destruction is a side-effect of confirming
the import, not the primary purpose of the action.

The architect flags this for review during dispatch. If the reviewer prefers
routing the destruction through `DeletionsController` (so it inherits the
action-confirmation page framework), the spec will be amended to a two-step
flow: keep/reject form, then action confirmation page, then destroy. The
default is to keep it in-modal because the user already implicitly confirmed
by submitting the keep/reject form.

## 6. Job + service

### 6.1 `Channel::ImportVideosJob`

- Queue: `:default` (or `:imports` if the project has a named queue policy;
  inherit from the existing `ChannelSync` precedent).
- Retries: Sidekiq default (25 attempts with exponential backoff) for
  transient YouTube errors (503, 429, network timeouts). Non-retriable errors
  (404 channel, invalid token after OAuth phase) mark the job `failed`,
  capture `error_payload`, do NOT retry.

Illustrative shape (rails-impl agent writes final code):

```ruby
class Channel::ImportVideosJob < ApplicationJob
  queue_as :default

  def perform(channel_id, import_job_id)
    channel = Channel.find(channel_id)
    import_job = ImportJob.find(import_job_id)
    import_job.update!(status: :running)

    Channels::VideoImporter.new.call(channel:, import_job:) do |progress|
      import_job.update!(
        total_videos: progress.total,
        imported_videos: progress.imported,
      )
      broadcast_progress(import_job)
    end

    import_job.update!(status: :completed)
    Notifications::ImportJobCompleted.deliver(import_job)
  rescue Channels::VideoImporter::FatalError => e
    import_job.update!(
      status: :failed,
      error_payload: { code: e.code, message: e.message },
    )
    Notifications::ImportJobCompleted.deliver(import_job)
    raise unless e.suppress_retry?
  end
end
```

### 6.2 `Channels::VideoImporter`

Single public method `#call(channel:, import_job:, &block)`. Steps:

1. Resolve the channel's uploads playlist (a YouTube API concept; pre-OAuth
   phase this is a stubbed seam returning a fixture id).
2. Page through `playlistItems.list` (50 per page).
3. For each page:
   - Diff against existing
     `Video.where(channel: channel, youtube_video_id: ids_in_page)`.
   - Diff against
     `RejectedVideoImport.where(channel: channel, youtube_video_id: ids_in_page)`.
   - For every id NOT in either: create a `Video` row with the metadata from
     the page response (title, length, category, youtube_video_id, channel).
   - Yield a `PageProgress(total:, imported:)` so the caller can update the
     `ImportJob` counters and broadcast.
4. Return when paging is exhausted.

Errors:

- Transient (503, 429, network) — raise to let Sidekiq retry.
- Permanent (404 channel, malformed payload, missing uploads playlist) —
  raise `Channels::VideoImporter::FatalError` with `code:` and
  `suppress_retry: true`.

The service does NOT touch Turbo Streams. It does NOT know about Action
Cable. It is pure Ruby + ActiveRecord + an injected upstream-client object
(constructor-injected so specs can stub).

### 6.3 Notifications

On `completed` and `failed` transitions, dispatch a notification via the
existing Phase 16 pipeline:

- Channel: `Notifications::ImportJobCompleted` (new class under
  `app/services/notifications/` or wherever the pipeline expects new
  notification types — confer with the Phase 16 spec at dispatch time).
- Recipient: `import_job.enqueued_by`.
- Payload: channel label, imported count, failed count, status, link to
  `/imports/channels/:id`.

This ensures the user is informed even if they close the modal before the
job finishes.

## 7. UX details

### 7.1 Entry point on `/videos`

- New `[import]` bracketed link in the page header controls, alongside the
  existing `[add]` (restored in B1 of the same Mobile note) and the
  `[bulk delete]` affordance. Order: `[add] [import] [bulk delete]`.
- Bracketed-link convention: `[import]` — no inner padding spaces (per
  architect rule A).
- Clicking opens the modal via a Turbo Frame request to
  `GET /imports/channels`. The modal is the existing wide variant (the
  `.modal--wide` class, or whatever the Phase 4 modal primitive declares) per
  the keybindings note D23.

### 7.2 Modal step 1 — channel selection

- Heading: "Import videos".
- Muted lead paragraph (one sentence per line per architect rule B):
  ```html
  Pick the channels to pull new uploads from.<br>
  Already-imported and previously-rejected videos are skipped.
  ```
- A list of connected channels. Each row:
  - `[ ] channel-slug — channel label` (the `[ ]` here is the 3-char
    checkbox indicator per architect rule A's checkbox exception).
  - If the channel has an in-flight ImportJob, the row shows the in-flight
    badge: `[ ] channel-slug — channel label  [import running]` with the
    checkbox disabled and `[import running]` linking to
    `/imports/channels/:id`.
- Footer: `[start import]` confirm button. Disabled until at least one
  channel is checked.

### 7.3 Modal step 2 — progress

- After the user clicks `[start import]`, the modal swaps to a per-channel
  progress list. Each row starts as:
  ```
  channel-slug — channel label
    =--- (queued)
  ```
  and becomes:
  ```
  channel-slug — channel label
    ===- imported 17 of 42
  ```
  as the job broadcasts progress.
- The progress indicator is the existing `=---` indicator component.
- When all jobs reach a terminal state (`completed` or `failed`), the modal
  swaps to step 3 (keep/reject) per the resolution of plan.md open question
  2. Default proposed behavior: each `ImportJob` swaps to its own keep/reject
  table as it completes (per-channel), so the user can start curating
  immediately for finished channels while others are still running. The
  aggregated alternative waits for all jobs.

### 7.4 Modal step 3 — keep/reject table

- Heading: "Keep what to import for channel-label".
- Muted lead paragraph:
  ```html
  All rows are kept by default.<br>
  Uncheck a row to permanently reject that video.<br>
  Rejected videos are not re-imported by future syncs.
  ```
- Table columns: `[checkbox] | title | length | category`.
- All checkboxes checked by default.
- Footer: `[keep]` confirm button. Submits PATCH `/imports/channels/:id`
  with `keep_video_ids[]` carrying the still-checked IDs.

### 7.5 Channel show page indicator

- When `Channel#in_flight_import?` is true, the show page renders an inline
  status block above the channel header:
  ```
  [import running] imported 17 of 42 — [view progress]
  ```
- `[view progress]` links to `/imports/channels/:id`, which opens the modal
  directly on the progress step (or the keep/reject table if completed).
- The block is rendered inside a `pane--standalone` container per architect
  rule C.

### 7.6 Re-opening the modal mid-flight

If the user navigates away and clicks `[import]` again later:

- `GET /imports/channels` checks for any in-flight ImportJob the current user
  enqueued.
- If exactly one: redirect (Turbo Frame swap) to its `show` view.
- If multiple: show the channel-selection step BUT with each in-flight
  channel rendered with its progress inline (so the user sees both "pick
  more channels" and "your running jobs" in the same modal).
- The selection-step rendering covers both cases via the partial in §3.

## 8. Cross-stack scope

| Surface   | Status   | Notes                                                             |
| --------- | -------- | ----------------------------------------------------------------- |
| Rails web | In scope | Full modal + jobs + tombstone implementation.                     |
| JSON API  | In scope | Mirrors the four endpoints; yes/no boundary; serves CLI/MCP later. |
| CLI       | Skipped  | Surface deferred. JSON branch is the seam. Linked from plan.md.   |
| MCP       | Skipped  | Tool wrapper deferred to the auth-phase scope catalog reshuffle.  |
| Website   | N/A      | No marketing-site implications.                                   |

## 9. Cross-cutting rules

- **Yes/no boundary.** Every external boolean — `connected`, `in_flight`,
  any keep-flag if one ever surfaces, MCP payloads when they land — uses
  `"yes"` / `"no"` strings. Internal storage stays Boolean. Convert at every
  JSON branch and request-param read.
- **Friendly URLs.** Channel slugs continue to be the user-facing identifier
  on the channel show page; the import flow accepts both slugs and IDs at
  the controller level.
- **Bulk-as-foundation.** The keep/reject destructive step is bulk by
  construction — N videos destroyed in one transaction. See §5.3 for the
  routing debate.
- **Auth gate.** `Sessions::AuthConcern` applied at controller level.
- **Rate limit.** Per-user 5-second cache lock on `create` to prevent
  double-clicks and sync bursts. Inline 429 message routes to the bracketed
  copy `[try again in a moment]`.
- **Notifications.** Completion (success + failure) feeds the Phase 16
  pipeline. The user is informed even if the modal was closed.
- **No JavaScript alerts.** All confirms via the standard turbo-frame modal
  pattern. No `data-turbo-confirm`, no `window.confirm`. The keep/reject
  form's `[keep]` submit IS the confirmation step — the user explicitly
  committed by clicking it.
- **Tombstone durability.** `RejectedVideoImport` rows are insert-only from
  this flow. Reversal UX is open question 5.

## 10. Acceptance

Each item is objectively verifiable by the reviewer agent or by the manual
test recipe in §11.

### Schema

- [ ] `import_jobs` table exists with all columns from §4.1 and the two
      indexes.
- [ ] `rejected_video_imports` table exists with all columns from §4.2 and
      the unique compound index.
- [ ] No new columns on `videos`.
- [ ] No new columns on `channels`.
- [ ] `db/schema.rb` regenerated and committed.

### Models

- [ ] `ImportJob` model: `belongs_to :channel`, `belongs_to :enqueued_by`,
      enum status, `in_flight` / `for_channel` / `recent` scopes,
      validations from §4.1, callbacks for `started_at` / `completed_at`,
      `progress_fraction`, `in_flight?`, `candidate_videos`.
- [ ] `RejectedVideoImport` model: `belongs_to :channel`,
      `belongs_to :rejected_by`, validations from §4.2.
- [ ] `Channel#in_flight_import?` returns true when an `in_flight`
      ImportJob exists for the channel.
- [ ] `Channel` has `has_many :import_jobs`,
      `has_many :rejected_video_imports` with appropriate dependent options.
- [ ] `Video#destroy` does not cascade to `import_jobs` or
      `rejected_video_imports`.

### Server logic

- [ ] `Imports::ChannelsController#index` lists every `connected: true`
      channel, marks in-flight rows as disabled.
- [ ] `#create` accepts `channel_ids[]`, validates each, refuses channels
      with an in-flight job (per open question 1 default), creates one
      `ImportJob` per remaining channel, enqueues one
      `Channel::ImportVideosJob` per `ImportJob`.
- [ ] `#create` is rate-limited per-user via a 5-second cache lock; a
      second call within 5s responds 429.
- [ ] `#show` returns the per-job state; renders the keep/reject table when
      the job is `completed`, the progress block otherwise.
- [ ] `#update` accepts `keep_video_ids[]`, destroys non-kept videos and
      inserts `RejectedVideoImport` rows in a single transaction.
- [ ] `Channel::ImportVideosJob` updates status `queued` to `running` to
      `completed` / `failed`, increments counters, broadcasts Turbo Stream
      progress, captures `error_payload` on fatal errors.
- [ ] `Channels::VideoImporter` diffs against both existing `Video` rows
      AND `RejectedVideoImport` rows; previously-rejected IDs never become
      Videos.

### Wire contracts

- [ ] JSON responses serialize booleans as `"yes"` / `"no"`.
- [ ] JSON `status` field is the string enum value.
- [ ] JSON includes per-channel counters and links.

### UX

- [ ] `[import]` button visible in the `/videos` header alongside `[add]`
      and `[bulk delete]`.
- [ ] Clicking `[import]` opens the modal as a Turbo Frame; does not
      navigate.
- [ ] Channel selection step lists all connected channels with checkboxes.
- [ ] `[start import]` is disabled until at least one channel is selected.
- [ ] Progress step shows the `=---` indicator per channel and updates live
      via Turbo Stream.
- [ ] Channel show page renders the in-flight badge with a `[view progress]`
      link when an `ImportJob` is running.
- [ ] Re-opening `[import]` while a job is in-flight surfaces the progress
      state.
- [ ] Keep/reject table shows columns `[checkbox] | title | length |
      category`, all checked by default.
- [ ] `[keep]` confirm submits the form; unchecked rows are destroyed +
      tombstoned in a single transaction.
- [ ] No `window.confirm` / `alert` / `prompt` / `data-turbo-confirm` is
      introduced anywhere in this flow.

### Notifications

- [ ] On `ImportJob` `completed` and `failed`, a notification is dispatched
      to `import_job.enqueued_by` via the Phase 16 pipeline.

### Test coverage (spec pyramid sweep per architect rule D)

- [ ] Model specs for `ImportJob` (validations, associations, scopes,
      callbacks, `progress_fraction`, `in_flight?`, `candidate_videos`).
- [ ] Model specs for `RejectedVideoImport` (validations, associations,
      uniqueness).
- [ ] Channel model spec extended for the new associations and
      `in_flight_import?`.
- [ ] Service spec for `Channels::VideoImporter`: happy path; channel with
      no uploads playlist; 404 channel; transient 503 retried; permanent
      error to `FatalError`; partial pagination; previously-imported videos
      skipped; previously-rejected videos skipped; counter math correct.
- [ ] Job spec for `Channel::ImportVideosJob`: enqueue happy path;
      transitions status correctly; updates counters; broadcasts progress;
      handles `FatalError` with `suppress_retry: true`; handles transient
      errors by re-raising; dispatches completion notification on both
      success and failure.
- [ ] Request specs for every endpoint, happy + sad + edge + flaw:
  - `index` happy path; unauthenticated to 401/redirect; no connected
    channels.
  - `create` happy path; rate-limit second-call to 429; in-flight channel
    selection refused; invalid channel id to 422.
  - `show` happy path while running; happy path after completion; not
    found; cross-user access (still allowed per single-install architecture,
    but verify).
  - `update` happy path with all kept; happy path with mixed; all unchecked
    to all destroyed + all tombstoned; idempotent re-submit (after first
    submit, candidate set is empty — should be a no-op rather than a 500).
  - JSON branch: each action; yes/no serialization verified.
- [ ] Component spec for `Imports::ProgressIndicatorComponent`.
- [ ] System spec for the end-to-end happy path described in §11.
- [ ] Factory definitions for `ImportJob` and `RejectedVideoImport`.

### Docs

- [ ] If the keep/reject table or the progress indicator introduces a
      pattern not yet in `docs/design.md`, the architect-docs agent updates
      it post-validation (out of scope for the rails-impl lane).
- [ ] Phase log (`docs/plans/beta/22-video-import-flow/log.md`) is appended
      with what was implemented, which files changed, and which open
      questions still remain.

## 11. Manual test recipe

Prereq: a fresh terminal with the dev stack running (`bin/dev`), at least two
connected channels in the dev DB (seed if needed via the existing channel
seed task), and at least 3 brand-new uploads visible on YouTube for each
channel that aren't yet in the local `videos` table. If the YouTube API
isn't wired (pre-Phase 7), point the importer stub at the fixture data
described in `spec/services/channels/video_importer_spec.rb`.

1. Open `http://localhost:3000/videos`.
2. Verify the page header shows `[add] [import] [bulk delete]` (order, no
   inner padding).
3. Click `[import]`. The modal opens; the URL does NOT change.
4. Verify the modal lists every connected channel with a checkbox.
5. Tick two channels. `[start import]` becomes enabled.
6. Click `[start import]`. The modal swaps to the progress step. Each ticked
   channel shows the `=---` indicator.
7. Watch progress update live. Each indicator should advance and the text
   should read "imported N of M" where M is the total fetched.
8. While the jobs are running, in a separate tab visit one of the channel
   show pages (`/channels/:slug`). Confirm the in-flight badge
   `[import running] imported N of M — [view progress]` is visible.
9. Click `[view progress]` on the channel show page. Confirm it opens the
   modal at the progress step for that ImportJob.
10. When the first ImportJob completes, confirm the modal swaps that
    channel's section to a keep/reject table with `[checkbox] | title |
    length | category` columns, all checkboxes ticked.
11. Uncheck one row. Click `[keep]`.
12. The modal closes (or swaps to the next channel's keep/reject table per
    the resolution of open question 2). A flash message appears confirming
    "kept N, rejected 1".
13. In a `bin/rails console`:
    - `Video.where(channel: <channel>).where(youtube_video_id: <id>).any?`
      returns `false`.
    - `RejectedVideoImport.where(channel: <channel>, youtube_video_id: <id>).any?`
      returns `true`.
14. Click `[import]` again, tick the same channel, click `[start import]`.
    The new ImportJob runs but does NOT re-import the rejected video. Verify
    in the keep/reject table that the rejected ID is absent.
15. Open `http://localhost:3000/notifications`. Confirm there is a
    completion notification for each ImportJob from step 6.
16. Click `[import]` a third time while no jobs are running. Try to click
    `[start import]` twice in rapid succession (within 5 seconds). The
    second click should respond with the `[try again in a moment]` message.

Teardown: `bin/rails db:reset` if you want to discard the test data, or
selectively delete the test `ImportJob` and `RejectedVideoImport` rows from
the console.

## 12. Open questions

Identical to plan.md "Open questions". Re-listed here so reviewers see the
full picture in one spec read.

1. **Re-enqueue policy** when a channel already has an in-flight ImportJob.
   Spec default: refuse + surface existing progress.
2. **Confirmation table scope** — per-channel as each job completes vs.
   aggregated after all jobs finish. Spec default: per-channel.
3. **ImportJob retention** — forever vs. expire after N days. Spec default:
   forever (no cron sweep added).
4. **Sort/filter on the confirmation table** — deferred until `f` / `s`
   keybinding schema lands.
5. **Tombstone reversal UX** — manual edit / rake task / future Settings
   page? Treated as a follow-up phase.
6. **Routing the destructive step through `DeletionsController`** vs.
   in-modal direct destroy (see §5.3). Spec default: in-modal because the
   keep/reject form submission IS the user's explicit confirmation.

The master agent resolves these with the user before dispatching the
rails-impl lane.
