# Phase 23 — Video Sync with Diff Dialog: implementation log

## 2026-05-11 — rails-impl single-pass dispatch

Per master agent's autonomous-lock of the 8 open questions, this dispatch
implements 23a/b/c/d in a single pass (the lanes are small and the file sets
don't collide much beyond `app/controllers/videos_controller.rb`).

### Q1 research outcome

YouTube enforces a 14-day cooldown on **channel** title / handle changes
(`channels.update` rate-limited on these two fields — locked into
`Channel#title_locked?` / `Channel#handle_locked?` in Phase 7.5 §11a).

Live-API research confirms YouTube does NOT enforce the same cooldown on
**video** titles. `videos.update` is rate-limited only by the daily quota
(10,000 units; each update costs 50). Per the master agent's locked Q1 decision
("populate but inert"):

- The `title_changed_at` column WAS added to `videos` (migration
  `20260511021256_add_video_metadata_columns_for_diff.rb`).
- `Youtube::VideoDiffApply` stamps `title_changed_at` on Pito-wins title applies
  for audit purposes.
- `Video#title_locked?` and `Video#title_unlock_at` are present on the model but
  return `false` / `nil` unconditionally — the diff dialog never gates the title
  row.

The implementation comment in `Video#title_locked?` documents the research and
the swap path if YouTube ever changes their mind. No code changes required if
they do — only the body of the two helpers.

### Files changed (high-level)

Schema:

- `db/migrate/20260511021256_add_video_metadata_columns_for_diff.rb` — adds
  `embeddable`, `public_stats_viewable`, `view_count`, `like_count`,
  `comment_count`, `title_changed_at`, `last_diff_checked_at`.
- `db/migrate/20260511021257_create_video_change_logs.rb` — append-only audit
  table mirroring `channel_change_logs`.
- `db/migrate/20260511021258_create_video_diffs.rb` — open-diff registry with
  partial unique index `(video_id) WHERE resolved_at IS NULL`.

Models:

- `app/models/video.rb` — `has_many :video_change_logs`,
  `has_many :video_diffs`, `has_one :open_diff`; validations for the new
  counters and `thumbnail_url`; inert `title_locked?` helpers per Q1.
- `app/models/video_change_log.rb` — new, append-only.
- `app/models/video_diff.rb` — new, with `#fields`, `#field_diff`, `#open?` /
  `#resolved?` helpers and `:open` / `:resolved` scopes.
- `app/models/notification.rb` — new enum value `video_diff_detected: 9`.

Services:

- `app/services/youtube/diff_computer.rb` — pure-function diff producer.
  Tolerates type mismatches (string counts → integers), tags reorder (sorted-set
  compare), nil-vs-blank, ISO 8601 duration, thumbnail tier fallback (`maxres` →
  `standard` → `high` → `medium` → `default`).
- `app/services/youtube/video_diff_persister.rb` — idempotent upsert.
- `app/services/youtube/video_diff_apply.rb` — orchestrator. In one transaction:
  YouTube-wins → local column writes; Pito-wins → push via
  `Youtube::VideosClient#update_video(fields:)`; `VideoChangeLog` row per
  applied field; transaction rolls back on YouTube failure.
- `app/services/youtube/videos_client.rb` — extended with `fields:` filter on
  `#update_video` so the apply path can push exactly the selected Pito-wins
  fields without dragging unrelated local state.
- `app/services/notification_formatter/templates/video_diff_detected.rb` — Phase
  16 formatter template.
- `app/services/notification_formatter/templates.rb` — registry entry.

Jobs:

- `app/jobs/video_diff_check_job.rb` — per-video diff check (one `videos.list`
  call, persist via `VideoDiffPersister`, emit notification when payload is
  non-empty).
- `app/jobs/bulk_video_diff_check_job.rb` — fan-out scheduler with 4-hour
  stagger window.
- `app/jobs/video_sync.rb` — naming-convention shim so the existing bulk-sync
  framework (`BulkSyncJob` → `<TargetType>Sync`) can dispatch video sync via
  `[sync]` button without a special case. Delegates to `VideoDiffCheckJob`.

Controllers + routes:

- `config/routes.rb` — added `GET /videos/diffs`, `GET /videos/:slug/diff`,
  `PATCH /videos/:slug/apply_diff`.
- `app/controllers/videos_controller.rb` — three new actions (`diff`,
  `apply_diff`, `diffs`) with HTML + JSON parity.

Cron:

- `config/sidekiq_cron.yml` — daily entry at 01:30 UTC (separate from channel
  diff per Q5).

Views + components + helpers:

- `app/views/videos/diff.html.erb` — three-column reconciliation page.
- `app/views/videos/diffs.html.erb` — paginated index of open diffs.
- `app/views/shared/_diff_table.html.erb` — shared partial.
- `app/views/videos/show.html.erb` — flash banner + `[sync]` link.
- `app/components/diff_decision_radio_component.rb` + .html.erb — shared
  component.
- `app/helpers/diff_helper.rb` — `human_diff_value`, `diff_field_display_only?`.

MCP:

- `app/mcp/tools/video_diff_show.rb` — read tool, scope: `app`.
- `app/mcp/tools/video_diff_apply.rb` — write tool, scope: `app`, two-step
  `confirm: yes` flag.

### Specs added

- `spec/models/video_diff_spec.rb` — associations, validations, scopes, field
  accessors, partial unique index enforcement (10 examples).
- `spec/models/video_change_log_spec.rb` — read-only-on-destroy, validations,
  enum, scopes (10 examples).
- `spec/models/video_spec.rb` — Phase 23 additions: associations, display-only
  counter validations, inert `title_locked?` (8 examples).
- `spec/services/youtube/diff_computer_spec.rb` — no-diff, single, multi-field,
  type mismatch, sorted-set tags, missing fields, nil-vs- blank, ISO duration,
  thumbnail tier fallback, boolean coercion (17 examples).
- `spec/services/youtube/video_diff_persister_spec.rb` — empty, non-empty new,
  non-empty replace, post-resolve creates fresh row (8 examples).
- `spec/services/youtube/video_diff_apply_spec.rb` — validation, YouTube-wins,
  Pito-wins, mixed, display-only rejection, push failure rollback,
  no-connection, quota exhausted (22 examples).
- `spec/services/youtube/videos_client_spec.rb` — extended with the Phase 23
  `fields:` filter coverage (+4 examples → 17 total).
- `spec/jobs/video_diff_check_job_spec.rb` — happy/sad/edge incl. video not
  found, no connection, needs-reauth, response with no items, quota exhausted
  re-raise (13 examples).
- `spec/jobs/bulk_video_diff_check_job_spec.rb` — fan-out, lonely-channel skip,
  stagger window distribution, return count (5 examples).
- `spec/requests/videos/diff_spec.rb` — GET happy/edge/JSON, PATCH
  happy/sad/idempotent, /videos/diffs paginated index (17 examples).
- `spec/requests/videos/sync_spec.rb` — `[sync]` → confirmation page →
  `BulkSyncJob` → `VideoSync` → `VideoDiffCheckJob` chain (6 examples).
- `spec/components/diff_decision_radio_component_spec.rb` — bracketed labels,
  default selection, disabled state, custom name (6 examples).
- `spec/helpers/diff_helper_spec.rb` — `human_diff_value` formatters,
  `diff_field_display_only?` (12 examples).
- `spec/mcp/tools/video_diff_show_spec.rb` — scope gating, open / no-diff
  branches, integer-id slug, video-not-found (5 examples).
- `spec/mcp/tools/video_diff_apply_spec.rb` — scope gating, preview posture,
  confirm: yes apply, no-diff / no-video errors, stale-diff surfacing (7
  examples).
- `spec/services/notification_formatter/templates/video_diff_detected_spec.rb` —
  template title pluralization, body formatting, URL shape, empty payload
  graceful (6 examples).
- `spec/system/video_sync_diff_flow_spec.rb` — end-to-end Capybara spec covering
  the YouTube-wins and Pito-wins critical journeys (2 examples).

Spec delta: ~175 new examples across model, service, job, request, component,
helper, MCP, and one selective system spec.

### Gates

- `bundle exec rspec` — Phase 23 specs: 173 examples, 0 failures. Broader suite
  (`spec/models/`, `spec/services/`, `spec/jobs/`, `spec/components/`,
  `spec/helpers/`) — 1922 examples, 0 failures (1 pending unrelated).
  `spec/requests/` — 1474 examples, 1 failure
  (`spec/requests/concerns/sessions/auth_concern_spec.rb:57` — pre- existing,
  unrelated to Phase 23; POST to `channels_path` which doesn't have a `:create`
  route).
- `bundle exec rubocop` — clean on all touched files (13 ruby files, 0 offences;
  19 spec files, 0 offences). RuboCop refuses to parse erb; not exercised on the
  new templates.
- `bin/brakeman -q -w2` — 0 security warnings, 0 errors. Two obsolete ignore
  entries reported (pre-existing).

### Surprising / noteworthy

1. **Master agent committed parallel scaffolding mid-session.** Commit `4403e73`
   ("Phase 22/23 partial scaffolding") landed the bulk of the 23a model + job +
   controller + MCP file shells while this session was in flight; commit
   `756361c` ("Phase 23 spec coverage") committed my spec files. My local edits
   merged cleanly with the committed state. The migrations, additional spec
   coverage, and the apply orchestrator business logic (the bulk of
   `Youtube::VideoDiffApply`) all landed via this session. The session-end
   snapshot has only four uncommitted files: the videos_client spec extension
   and three new spec files (`video_diff_apply` MCP, `video_diff_detected`
   template, `video_sync_diff_flow` system spec).

2. **Helper file naming matters in Rails 8.1.** I initially wrote
   `app/helpers/diff_helpers.rb` (module `DiffHelpers`) and Rails did NOT
   auto-include it. Renaming to `diff_helper.rb` (module `DiffHelper`) fixed it.
   The convention requires singular `_helper` suffix for auto-discovery from
   controllers / views; the project's existing helpers (`compact_time_helper`,
   `note_helper`, `youtube_helper`) all follow the same shape.

3. **Channel diff (11i) hasn't shipped yet.** The spec calls for extracting the
   shared `_diff_table.html.erb` partial and `DiffDecisionRadioComponent` and
   refactoring `app/views/channels/ diff.html.erb` to use them. That channel
   diff view does NOT exist in the current codebase — the 11i feature spec ships
   an architect doc but no rails-impl pass has landed. The shared partial +
   component ARE extracted (per Q8's "same dispatch" recommendation), ready for
   the 11i implementation pass to consume. The two relevant acceptance
   checkboxes are left unticked.

4. **Display-only field defense.** The diff payload can include fields YouTube
   CANNOT accept on `videos.update` (e.g., `view_count`, `comment_count`). The
   apply orchestrator raises a clear validation error when the user submits
   `accept pito` on a display-only field, rather than silently dropping the
   decision. The diff page disables the `accept pito` radio for display-only
   rows so the UI prevents the situation from arising in normal flow; the
   validation is a belt-and-suspenders for API / MCP clients.

5. **`design.md` update box left unticked.** The diff page reuses
   `pane--standalone` and the bracketed-link convention. No new visual primitive
   ships. Per the spec's parenthetical ("likely none"), no update needed.

### Cross-stack scope

| Surface       | Status                                                                  |
| ------------- | ----------------------------------------------------------------------- |
| Rails web     | Complete. Diff page, apply, sync flash banner, /videos/diffs index.     |
| MCP           | Complete. `video_diff_show` + `video_diff_apply`, both `app`-scoped.    |
| Rails JSON    | Complete. GET / PATCH `/videos/:slug/diff.json` + `/videos/diffs.json`. |
| `pito` CLI    | Out of scope (per spec) — CLI consumes the JSON API once the parity     |
|               | sweep follow-up runs.                                                   |
| Website       | Out of scope (per spec).                                                |
| Sidekiq job   | Complete. `VideoDiffCheckJob` + `BulkVideoDiffCheckJob` + cron entry.   |
| Notifications | Complete. `video_diff_detected: 9` enum + formatter template.           |

### Open follow-ups

- **Channel diff (11i) rails-impl pass.** When that ships, refactor
  `app/views/channels/diff.html.erb` to consume `shared/_diff_table` +
  `DiffDecisionRadioComponent` and tick the two remaining acceptance boxes.
- **CLI parity sweep.** The CLI `pito videos diff` subcommand consumes the JSON
  endpoints landed here; tracked in the existing follow-up.
- **Per-field auto-resolve policy (Q7).** Out of scope per master lock; revisit
  after dogfooding.

### Plan checkboxes

The phase plan (`docs/plans/beta/23-video-sync-diff-dialog/plan.md`) contains no
acceptance checkboxes — the acceptance list lives in the spec file
(`specs/01-video-sync-and-diff-dialog.md` §Acceptance). Checkboxes ticked: 26 of
30 (2 left for channel-diff coordination, 2 left for the design.md /
channel-shared-partial coordination work that depends on 11i landing first).
