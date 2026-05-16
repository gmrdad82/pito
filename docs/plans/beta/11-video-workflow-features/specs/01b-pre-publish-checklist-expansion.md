# 01b — Pre-Publish Checklist Expansion

> Parent: `docs/plans/beta/11-video-workflow-features/plan.md`. Depends on `01a`
> — chapters + end-screens have to exist before the new automatic checks can
> read them. Do not dispatch until `01a` is green.

---

## Goal

The Phase 22 pre-publish modal today checks four manual booleans
(`pre_publish_game_ok`, `pre_publish_age_ok`, `pre_publish_paid_promotion_ok`,
`pre_publish_end_screen_ok`) plus the `pre_publish_checked_at` stamp. Phase 11
stacks five new **automatic** checks on top:

1. `thumbnail_attached` — `Video#thumbnail.attached?` is true.
2. `tags_min_three` — `Video#tags.compact.size >= 3`.
3. `chapters_or_explicit_none` — `Video#video_chapters.any?` OR a
   `video_check_skips` row exists for `check_key: 'chapters_or_explicit_none'`.
4. `description_min_100_or_explicit_minimal` — `Video#description.to_s.size
   > = 100`OR a`video_check_skips`row exists for`check_key:
   > 'description_min_100_or_explicit_minimal'`.
5. `end_screen_configured_or_explicit_none` — `Video#video_end_screens.any?`
   (including `kind: none` rows) is true.

Each new check exposes a `[skip]` link that captures a free-text rationale into
a new `video_check_skips` table. The publish gate calls
`Videos::PrePublishChecklist#passed?` which returns `true` when every check
either passes or has a skip row. Failing un-skipped checks at publish time route
through the existing action-screen framework (`shared/_action_screen.html.erb` +
`Confirmable`) — hard block, no JS confirm.

The existing four manual booleans (Phase 22) keep their current UX. Phase 11
does **not** rewrite them.

---

## Files touched

### Migrations

- `db/migrate/<TS>_create_video_check_skips.rb` —
  `id, video_id, check_key string NOT NULL, rationale text NOT NULL, skipped_by_user_id bigint FK, skipped_at timestamp, timestamps`;
  unique index on `(video_id, check_key)`.

### Models

- `app/models/video_check_skip.rb` (new) — `belongs_to :video`,
  `belongs_to :skipped_by, class_name: "User"`. Validations:
  `check_key presence + inclusion in CHECK_KEYS`,
  `rationale presence + length <= 500`.
- `app/models/video.rb` — `has_many :video_check_skips, dependent: :destroy`.

### Lib / value object

- `app/lib/videos/pre_publish_checklist.rb` (new) — composes the nine checks.
  Each check exposes `#key`, `#label`, `#passed?`, `#skipped?`,
  `#skip_rationale`, `#manual?` (true for the four Phase 22 booleans; false for
  the five new automatic ones). The composer surfaces `#all_results` for view
  consumption and `#passed?` (every result is passing or skipped) for the
  publish gate.

### Controllers

- `app/controllers/videos/checks_controller.rb` (new) — single action `create`
  (`POST /videos/:youtube_video_id/checks/:check_key/skip`). Permits `rationale`
  body. Upserts the `VideoCheckSkip` row (unique on `(video_id, check_key)`).
- `app/controllers/videos_controller.rb` — extend the `publish` / `publish_now`
  action to call `Videos::PrePublishChecklist.new(video)` and route through
  `shared/_action_screen.html.erb` when `passed?` is false.

### Views

- `app/views/videos/_pre_publish_checklist.html.erb` — rewrite (Phase 22
  partial) to render the nine checks. Each failing row shows a `[skip]` inline
  form (textarea + submit).
- `app/views/videos/checks/new.html.erb` (or inline) — the skip form surfaces
  inline; no separate page is needed.
- `app/views/shared/_action_screen.html.erb` — no change; the existing framework
  consumes the new checklist via `Confirmable`.

### Routes

- `config/routes.rb` — add
  `resources :videos, only: [] do member do post 'checks/:check_key/skip', to: 'videos/checks#create', as: :skip_check end end`.
  Friendly URL preserved (the parent `:youtube_video_id` segment).

### Specs

- `spec/lib/videos/pre_publish_checklist_spec.rb` (new) — exhaustively covers
  every check: happy (passing input), sad (failing input), edge (boundary
  inputs: exactly 3 tags, exactly 100 description chars), flaw (corrupt or
  missing video associations).
- `spec/models/video_check_skip_spec.rb` (new) — validations, uniqueness on
  `(video_id, check_key)`, upsert path.
- `spec/factories/video_check_skips.rb` (new).
- `spec/requests/videos/checks_spec.rb` (new) — skip endpoint happy / sad /
  edge.
- `spec/requests/videos_publish_spec.rb` — extend to cover the publish gate:
  failing un-skipped check blocks; all checks passing or skipped proceeds.
- `spec/system/pre_publish_checklist_spec.rb` (new) — system spec: skip a check
  via the inline form, watch the row flip to `[skipped — <rationale snippet>]`;
  attempt publish on a failing video and observe the action-screen route.

---

## Acceptance

- [ ] `Videos::PrePublishChecklist#all_results` returns nine `Result` structs
      (one per check) with `#key`, `#label`, `#passed?`, `#skipped?`,
      `#skip_rationale`, `#manual?`.
- [ ] `Videos::PrePublishChecklist#passed?` is `true` only when every result
      either passes or is explicitly skipped.
- [ ] `thumbnail_attached` check: passes when `video.thumbnail.attached?` is
      true; fails otherwise.
- [ ] `tags_min_three` check: passes when `video.tags.compact.size >=     3`;
      fails when 0 / 1 / 2 tags.
- [ ] `chapters_or_explicit_none` check: passes when chapters exist OR a skip
      row exists.
- [ ] `description_min_100_or_explicit_minimal` check: passes when
      `video.description.to_s.size >= 100` OR a skip row exists.
- [ ] `end_screen_configured_or_explicit_none` check: passes when any
      `video_end_screens` row exists (including `kind: none`).
- [ ] `POST /videos/:youtube_video_id/checks/:check_key/skip` with a `rationale`
      body upserts a `video_check_skips` row.
- [ ] Re-submitting the skip form for the same `(video_id, check_key)` pair
      updates the existing row's `rationale` (no duplicate row).
- [ ] Pre-publish modal renders the nine checks with `[ok]`, `[fail]`, or
      `[skipped — <rationale>]` status indicators.
- [ ] Skip form is an inline textarea + submit; no JS confirm / alert / prompt
      anywhere.
- [ ] Publish on a video with any failing un-skipped check routes through
      `shared/_action_screen.html.erb` with the failing list + `[cancel]` link.
- [ ] Publish on a video with all checks passing or skipped proceeds to the
      existing publish path (Phase 22 flow).
- [ ] Yes/no boundary applied — the skip endpoint accepts no Boolean input;
      reserved guard documented inline.
- [ ] Friendly URL preserved on the skip route.
- [ ] `bundle exec rspec` green on every new + extended spec file.

---

## Manual test recipe

1. `bin/rails db:migrate` (creates `video_check_skips`).
2. `bin/dev` → visit `http://localhost:3000/videos/<some_yt_id>/edit`.
3. Attach a thumbnail (`01a` flow) and add 1 tag only.
4. Click `[run pre-publish check]`. The modal lists nine checks:
   - `[ok]` for `thumbnail_attached`.
   - `[fail]` for `tags_min_three`.
   - `[fail]` for `chapters_or_explicit_none` (unless chapters exist).
   - `[fail]` for `description_min_100_or_explicit_minimal` (unless description
     ≥100 chars).
   - `[fail]` for `end_screen_configured_or_explicit_none` (unless end-screens
     exist).
   - Manual booleans show their current state.
5. **Skip a check.** Click `[skip]` on
   `description_min_100_or_explicit_minimal`. Inline textarea appears. Type
   `short-form video, intentionally minimal`. Submit. Reload the modal; the
   check now reads `[skipped — short-form video, intentionally minimal]`.
6. **Update a skip rationale.** Click `[skip]` again on the same check; enter
   `intentionally minimal — vlog`. Submit. Reload. The rationale updates in
   place (no duplicate row in `video_check_skips` — confirm via
   `bin/rails console`:
   `VideoCheckSkip.where(video_id: <id>, check_key: 'description_min_100_or_explicit_minimal').count == 1`).
7. **Publish gate — block.** With at least one un-skipped failing check, attempt
   publish. The action-screen renders with the failing list and a `[cancel]`
   link. Click `[cancel]` — back to edit.
8. **Publish gate — pass.** Skip every remaining failing check; confirm
   `Videos::PrePublishChecklist.new(video).passed?` returns `true` (via
   `bin/rails console`). Hit publish — the existing Phase 22 publish flow runs.
9. **`bundle exec rspec`** — green.

---

## Cross-stack scope

| Surface            | Status                                      |
| ------------------ | ------------------------------------------- |
| Rails web          | IN SCOPE                                    |
| Rails MCP          | DEFERRED — captured in sub-spec `01f`       |
| `pito` CLI (Rust)  | DEFERRED — MCP/TUI pause; captured in `01f` |
| Cloudflare website | OUT OF SCOPE                                |

---

## Open questions

1. **AppSetting gate.** Parent open question §1 — should the expanded checklist
   be opt-in via `AppSetting#pre_publish_strict`? Architect leans no gate;
   surface for user lock before dispatch.
2. **Skip rationale length.** 500 chars feels generous. The implementation agent
   can lower to 200 if the architect surfaces it as a follow-up.
3. **Re-running automatic checks after edit.** Today's modal stamps
   `pre_publish_checked_at` when the user runs the check. After edits, should
   the timestamp reset? Architect leans **reset on writable change** — the
   existing `after_update_commit :enqueue_sync_back` hook on `Video` already
   gates on `writable_field_changed?`; mirror that gate to null out
   `pre_publish_checked_at` so the modal re-runs.
4. **Manual boolean migration.** The four Phase 22 booleans (`pre_publish_*_ok`)
   stay as-is. If/when those collapse into the same `video_check_skips` shape,
   that's a follow-up sub-spec — out of scope here.
