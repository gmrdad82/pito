# Phase 22 — Video Import Flow — Session Log

## 2026-05-11 — Step 01 (01-video-import-modal-and-importjob.md)

**Spec:**
`docs/plans/beta/22-video-import-flow/specs/01-video-import-modal-and-importjob.md`

**Goal of the session.** Land the first-class `[import]` affordance on
`/videos`: a Turbo-frame modal that picks connected channels, enqueues one
`Channel::ImportVideosJob` per selection, streams per-channel progress, and ends
with a keep/reject confirmation that creates `RejectedVideoImport` tombstones
for any unchecked row so the daily sync never re-imports them.

### Locked open questions (master agent, 2026-05-11)

1. **Re-enqueue policy** — refuse with flash "import already running for channel
   #{id}"; the existing in-flight job's progress view is surfaced.
2. **Confirmation table scope** — per-channel (one keep/reject table per
   `ImportJob` as it completes).
3. **ImportJob retention** — keep forever (audit trail; no cron sweep).
4. **Sort/filter on confirmation table** — out of scope for v1.
5. **Tombstone reversal** — out of scope; future rake task.
6. **DeletionsController routing for keep/reject** — in-modal destroy inside
   `Imports::ChannelsController#update` (single explicit confirm).

### What landed

**Migrations.** Two creates:

- `db/migrate/20260511021100_create_import_jobs.rb` — `import_jobs` table with
  `channel_id`, `enqueued_by_id`, `status` (integer enum), three counter
  columns, `error_payload` jsonb, `started_at`, `completed_at`. Compound indexes
  on `(channel_id, status)` and `(status, created_at)`.
- `db/migrate/20260511021200_create_rejected_video_imports.rb` —
  `rejected_video_imports` table with `channel_id`, `youtube_video_id`,
  `rejected_at`, `rejected_by_id`. Unique compound index on
  `(channel_id, youtube_video_id)` is the durable contract that protects against
  double-tombstoning across parallel jobs.

Both ran against the dev DB; `db/schema.rb` regenerated.

**Models.**

- `app/models/import_job.rb` (new) — `belongs_to :channel`,
  `belongs_to :enqueued_by`, enum status (queued / running / completed /
  failed), `in_flight` / `for_channel` / `recent` scopes, `before_save`
  callbacks for `started_at` / `completed_at` stamping, `#progress_fraction`
  (capped at 1.0), `#in_flight?`, `#candidate_videos` (channel videos created in
  the [started_at, completed_at] window).
- `app/models/rejected_video_import.rb` (new) — `belongs_to :channel`,
  `belongs_to :rejected_by`, validators for the 11-char YouTube id shape and a
  uniqueness scope on `(channel_id, youtube_video_id)` that mirrors the DB
  index.
- `app/models/channel.rb` — added `has_many :import_jobs`,
  `has_many :rejected_video_imports`, a `.connected` scope (channels with a
  `youtube_connection_id` — the post-Phase-9 equivalent of the retired
  `connected` boolean), and `#in_flight_import?` / `#in_flight_import_job`
  helpers.

**Service.** `app/services/channels/video_importer.rb` (new). Single
`#call(channel:, import_job:, &block)` method. Resolves the channel's uploads
playlist, paginates `playlistItems.list`, diffs each page against existing
`Video` rows AND `RejectedVideoImport` rows, creates Video rows for genuinely
new ids (privacy_status stays `:private` — the YouTube-side publish state
arrives on a subsequent sync), and yields `PageProgress` so the caller can
broadcast. Counter bumps use `ActiveRecord::Base.sanitize_sql_array` +
`update_all` so concurrent updates do not clobber each other (and Brakeman stays
clean). Errors funnel through `FatalError` (suppress retry) / `TransientError`
(re-raise).

**Job.** `app/jobs/channel/import_videos_job.rb` (new). Drives one
`Channels::VideoImporter` run per `ImportJob`. Sidekiq `retry: 3` for transient
errors; fatal errors mark the row `failed`, capture `error_payload`, dispatch
the completion notification, and do NOT re-raise. Missing channel between
enqueue and perform → marks the row failed with `code: "channel_missing"`.

**Notifications.** `app/services/notification_source/import_job_completed.rb`
(new) plus a new `import_job_completed` value in the `Notification#kind` enum.
Severity is `:success` on completed, `:warn` on failed. Dedup key is
`import-job-<id>` so repeated terminal transitions on the same row do not
double-post. URL points at `/imports/channels/:id` so clicking the in-app
notification reopens the keep/reject view.

**Controller + routes.**

- `app/controllers/imports/channels_controller.rb` (new) — four actions
  (`index`, `create`, `show`, `update`). 5-second per-user
  `Rails.cache.write(unless_exist: true)` rate-limit on `create`. HTML + JSON
  branches for every action; JSON serializes booleans as `"yes"` / `"no"` per
  the project's external-boundary rule.
- `config/routes.rb` —
  `namespace :imports do resources :channels, only: %i[index create show update] end`.

**Views + components.**

- `app/views/imports/channels/{index,create,show}.html.erb` plus the `_progress`
  and `_keep_reject_table` partials. All wrapped in the shared
  `imports_modal_frame` Turbo Frame so the modal swaps body in place without a
  full-page navigation.
- `app/views/imports/channels/{index,create,show,update}.json.jbuilder` — JSON
  branch for the CLI / MCP parity seam.
- `app/components/imports/progress_indicator_component.{rb,html.erb}` (new) —
  4-tick ASCII bar (`=---` / `==--` / `===-` / `====`) plus status label
  ("queued" / "imported N of M" / "completed — N new" / "failed").
- `app/views/videos/index.html.erb` — `[import]` bracketed link in the header
  (next to the `[add]` and bulk-select toolbar). Targets the
  `imports_modal_frame` Turbo Frame so the modal opens in place.
- `app/views/channels/show.html.erb` — in-flight badge with the progress
  indicator + `[view progress]` link when an `ImportJob` is queued or running
  for the channel.

**Specs (every layer of the pyramid).**

- `spec/models/import_job_spec.rb` — associations, enum, validations, scopes
  (`in_flight`, `for_channel`, `recent`), `before_save` callbacks (started_at +
  completed_at stamping), `#progress_fraction` edge cases, `#in_flight?`
  per-status, `#candidate_videos` window scoping.
- `spec/models/rejected_video_import_spec.rb` — associations, validators
  including the 11-char regex, scoped uniqueness, and the DB-level
  `ActiveRecord::RecordNotUnique` on duplicate (channel, youtube_video_id).
- `spec/models/channel_spec.rb` — extended with associations, the `.connected`
  scope, `#in_flight_import?`, and `#in_flight_import_job`.
- `spec/services/channels/video_importer_spec.rb` — happy path, existing-video
  diff, rejected-video diff, missing-uploads-playlist fatal, missing-connection
  fatal, transient errors propagate, partial pagination, and atomic counter math
  under concurrent updates.
- `spec/jobs/channel/import_videos_job_spec.rb` — status transitions, counter
  updates, success notification, failure notification, fatal suppression,
  transient re-raise, missing-channel branch, missing-import-job no-op, Sidekiq
  enqueue.
- `spec/requests/imports/channels_spec.rb` (32 examples) — every endpoint,
  happy + sad + edge + flaw. Includes: HTML + JSON branches, rate-limit
  cache-lock pattern (`MemoryStore` injection mirrors the notifications spec),
  in-flight refusal (HTML redirect, JSON 422), multi-status partial enqueue,
  candidate_videos window, all-kept no-op, all-rejected destroy, idempotent
  re-submit, cross-user access permitted (single-install architecture).
- `spec/components/imports/progress_indicator_component_spec.rb` — bar rendering
  at every status, status class, data attribute, cap at 100%.
- `spec/services/notification_source/import_job_completed_spec.rb` — happy path
  on completed, severity flip on failed, idempotency on repeat report!, fallback
  title when channel.title is blank.
- `spec/system/video_import_flow_spec.rb` — single end-to-end journey
  (rack_test, no JS): open the modal, tick two channels, enqueue two jobs, run
  both Sidekiq workers inline against a fixture client, reach the keep/reject
  screen, uncheck one row, submit `[keep]`, verify the rejected video is gone
  from `Video` and present in `RejectedVideoImport`, then re-import the same
  channel and verify the rejected id is NOT re-imported.
- `spec/factories/{import_jobs,rejected_video_imports}.rb` — two new factories
  with `:running`, `:completed`, `:failed` traits on ImportJob.

Notification model spec updated to assert membership for the baseline kinds
rather than exact-array match — a parallel agent's `video_diff_detected` kind
landed in the same chat and the old `match_array(%w[...])` assertion was too
tight.

### Gates

- **RSpec** — full suite: 4932 examples, 5 pre-existing failures, none related
  to Phase 22 (numeric-formatting lint flagged `app/views/videos/diffs.html.erb`
  from the diff-cron lane; auth concern + composites + calendar specs all in
  other agents' lanes). Every new + adjacent spec runs clean (248 examples for
  the Phase 22 bundle).
- **Rubocop** — 938 files, no offenses.
- **Brakeman** — 1 SQL-injection warning surfaced on the initial `update_all`
  string interpolation; rewritten via `ActiveRecord::Base.sanitize_sql_array`
  and Brakeman is now clean.

### Cross-stack notes

- Yes/no boundary is honored in every JSON jbuilder (`connected`, `in_flight`).
- Friendly URL semantics preserved: `parse_channel_ids` resolves through
  `Channel.friendly.find` so slugs or integer ids both work.
- CLI / MCP wrappers are out of scope for this phase per the spec; the jbuilder
  JSON contract is the seam the next phase consumes.
- Channel destroy cascades both `ImportJob` and `RejectedVideoImport` rows via
  `dependent: :destroy` (mirrored by the DB FK's `ON DELETE CASCADE`).

### Surprises

- The `Channel#connected` scope had been retired in Phase 9 with a spec
  asserting `expect { Channel.connected }.to raise_error(NoMethodError)`.
  Reintroducing it with the post-Phase-9 semantics
  (`where.not(youtube_connection_id: nil)`) required updating that spec —
  captured in the channel_spec.rb diff.
- The `Notification#kinds` enum spec asserted an exact eight-key match. Two
  agents are in flight that each add a new kind; the spec was loosened to
  `include(*baseline)` so neither lane has to coordinate against the other.
- Initial `update_all("total_videos = total_videos + #{items.size}")` tripped
  Brakeman's medium-confidence SQL-injection check despite every interpolated
  value being an internal integer. Rewritten via `sanitize_sql_array` to keep
  the gate clean.
- A parallel `keyboard_navigation_enabled` migration from the settings lane was
  picked up by `bin/rails db:migrate` in the middle of the Phase 22 migrations —
  both ran cleanly and schema.rb merged without conflict. Cross-lane
  coordination as expected.

### Open issues for the master agent

- Stimulus `imports-select` controller is referenced by `index.html.erb`
  (`data-controller="imports-select"`) but not authored — the modal still works
  because the form submit button is a plain `<button type="submit">` and the
  `disabled` attribute is static. A follow-up could wire the `refresh` action to
  flip the submit's `disabled` state once at least one channel is ticked. Out of
  scope for the v1 reviewer pass; tracked as a UX polish item.
- The default `Channels::VideoImporter::StubPlaylistClient` returns an empty
  page — the manual playbook (§11) needs real fixtures to drive the flow against
  the dev DB. The system spec's `StubClient` is the reference shape; a separate
  dev rake task that hydrates a couple of fake pages would let the user click
  through the modal end-to-end without OAuth.
