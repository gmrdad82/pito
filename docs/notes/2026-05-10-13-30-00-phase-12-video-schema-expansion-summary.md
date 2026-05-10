# Phase 12 — Video schema expansion + edit surface + pre-publish checklist

## Status

**Landed in main.** Implementation complete. 2354 RSpec examples passing
(suite-wide). Reviewer + security audit not yet dispatched on Phase 12
specifically (parallel-running other phases collapsed multiple commits
together).

## What changed

- Single migration: 19 column adds to `videos`, GIN index on `tags`, partial
  index on `publish_at`, plain indexes on `published_at` / `privacy_status`,
  switched `youtube_video_id` uniqueness to case-sensitive (per Q12 lock),
  renamed `playlist_items` → `playlist_videos` (Note 1 terminology).
- `Video` model now carries the YouTube Data API v3 writable subset (title,
  description, tags as jsonb, category_id, privacy_status, publish_at,
  embeddable, public_stats_viewable, made_for_kids, age_restriction,
  has_paid_promotion, end_screen_present, default_language,
  default_audio_language, captions_state, recording_date, recording_location,
  duration_seconds, last_sync_error).
- Pre-publish checklist as 4 booleans + 1 timestamp directly on `videos`.
- Direct `Video.project_id` foreign key (Timeline model retired per realignment
  ambiguity 1; `Project has_many :videos, dependent: :nullify`).
- `VideoPolicy` is the single-source-of-truth for the writable-field subset
  (shared between web controller + MCP `update_video` tool).
- New `VideoSyncBack` Sidekiq job for write-back to YouTube. New `VideoPublish`
  Sidekiq job for the publish state-machine transition.
- New `Youtube::VideosClient` + `Youtube::VideosReader` services. Added
  `videos.update => 50` to the YouTube quota table.
- New views: `videos/edit.html.erb`, `_form.html.erb`,
  `_pre_publish_modal.html.erb`.
- New Stimulus controller: `pre_publish_checklist_controller.js`. Modal is a
  Turbo Frame in-page overlay (not a full action-screen); uses the project's
  hard rule against `confirm()` / `alert()` / `prompt()`.
- MCP tools: `update_video` heavy edit (full writable subset, two-step
  `confirm`, smuggle guards), new `pre_publish_check_video`, new `publish_video`
  (rejects when checks incomplete).
- `Project#has_many :videos, dependent: :nullify`. Linked-videos pane on the
  project show page.
- `playlist_item.rb` deleted; replaced with `playlist_video.rb`.

## Quality gates

- 2354 RSpec examples → 0 failures (1 flaky on `calendar/month_spec.rb` — Phase
  15 lane, not Phase 12 regression).
- Rubocop: 547 files, 0 offenses.
- Brakeman: 0 security warnings, 0 errors.

## Master agent decisions honored (all 12 copy + 13 open questions)

- 4 boolean columns + 1 timestamp on `videos` for pre-publish (Q1).
- VideoPolicy single source for writable subset (Q2).
- Turbo Frame in-page modal (Q3).
- VideoSyncBack directional job name (Q4).
- Channel schema relaxation (Q5 — fall back to URL slug).
- `playlist_videos` rename (Q6).
- Persistent pre-publish state across edits (Q7).
- `unlisted ↔ public` skip checklist (Q8).
- Comma-separated tags + Stimulus pills (Q9).
- Optimistic sync-back on failure (Q10).
- `:nullify` on `Project has_many :videos` (Q11).
- Case-sensitive `youtube_video_id` uniqueness (Q12).
- `jsonb` for tags column (Q13).

## Validation steps when you walk through

1. `bin/setup && bin/rails db:migrate && bin/dev`.
2. `/videos` — confirm new privacy_status column + `[edit]` link per row.
3. `[edit]` on a private draft → form sections (basics / visibility / audience /
   disclosures / studio-only / project).
4. Edit title → `[update]` → redirect + Sidekiq `VideoSyncBack` enqueued.
5. `[publish]` → modal opens → submit disabled until 4 boxes ticked → submit →
   `privacy_status` flips to public.
6. On a published video, confirm `[publish]` is gone, `[unpublish]` shown,
   metadata edits do NOT fire the modal.
7. `[schedule]` flow with future timestamp → `privacy_status` stays private,
   `publish_at` set.
8. Project page → linked videos list appears.
9. Delete project → linked videos survive with `project_id IS NULL`.
10. MCP `update_video` with `confirm: "no"` returns dry-run preview; `"yes"`
    applies. Same two-step for `pre_publish_check_video` / `publish_video`.

## Open follow-ups

- Reviewer + security agent dispatches not yet run on Phase 12 specifically (the
  parallel-implementation cadence batched commits).
- Calendar test flake `spec/requests/calendar/month_spec.rb:35` needs isolation
  fix (Phase 15 lane).
- Phase 14 Spec 03 (Steam-shelf + `video_game_link` + 16 MCP tools) still
  blocked on awaiting cleanup; can now dispatch since Phase 12's
  `videos.duration_seconds` column exists.
