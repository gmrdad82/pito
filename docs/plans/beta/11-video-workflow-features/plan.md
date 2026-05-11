# Phase 11 — Video Workflow Features

> Read `docs/plans/beta/beta.md` first. Then read this `plan.md`. Then read the
> sub-specs under `docs/plans/beta/11-video-workflow-features/specs/` in the
> order declared in §"Sequencing".
>
> **Status:** scaffolded by `pito-architect-spec` on 2026-05-11. This `plan.md`
> supersedes the prior Alpha-era Phase 11 outline (production state machine /
> resumable upload / KB-sandbox thumbnail history). That outline was written
> against the old `pito-yt-kb` repo + `tenant_id` model, both of which were
> retired (ADR 0003, YouTube KB drop). The current Phase 11 scope sits on top
> of the post-Wave-4a video pipeline (Phases 12 / 15 / 16 / 22 / 23 / 26) and
> fills the workflow polish gap.

---

## Goal

Phase 11 closes the gap between the "video record exists in pito" baseline
(Phases 12 / 22 / 23 / 26) and a workflow the user can actually live inside
end-to-end: a polished edit surface (thumbnail + tags + chapters + end-screen),
an expanded pre-publish checklist that gates publishes through the existing
action-screen framework, a post-publish nudge loop (comments + analytics
notifications fired on a configurable cadence), series / sequel tracking on
`Video`, and a tidy LINKS section that lifts the existing `video_links` table
out of "raw row" status.

The video pipeline already covers:

- `Video` schema with writable subset + four-boolean pre-publish checklist
  (Phase 12).
- `VideoPublish` job with timezone-aware scheduled publishing (Phase 26 §01h).
- `VideoDiffCheckJob` / `BulkVideoDiffCheckJob` (Phase 23).
- Import flow (Phase 22).
- YouTube Analytics integration (Phase 13 / Phase 26 §01g).

Phase 11 builds on that floor — it does **not** redo any of it. The edit
surface today is bare; the pre-publish gate today checks four booleans
(`pre_publish_game_ok`, `pre_publish_age_ok`, `pre_publish_paid_promotion_ok`,
`pre_publish_end_screen_ok`) plus the `pre_publish_checked_at` stamp; nothing
on the pito side fires a follow-up after a publish lands; sequels and series
are inferred only from title regex (if at all); and `video_links` exists as a
table but has no first-class UI. Phase 11 fills those five gaps.

Source-of-truth: master-agent dispatch (2026-05-11) — no Mobile drop note
yet. Surface a `docs/notes/...` capture if the scope expands during
implementation.

---

## Scope

In scope:

- **Edit page polish** — thumbnail upload + preview; tags input
  (comma-separated, no autocomplete, no chip JS); chapters nested-form editor
  (timestamp + label rows); end-screen configuration (related video / channel
  / playlist picker, up to 4 rows or one explicit `kind: none` row).
- **Pre-publish checklist expansion** — five new automatic checks on top of
  the existing four manual booleans: thumbnail attached, ≥3 tags, ≥1 chapter
  (or "no chapters" explicit), description ≥100 chars (or "minimal" explicit),
  end-screen configured (or "none" explicit). Each new check exposes a
  `[skip]` link that captures rationale text. Publishing while any check is
  failing AND not skipped routes through the action-screen framework with a
  hard block.
- **Post-publish workflow** — two new notification kinds (`video_comments_due`,
  `video_analytics_due`) fired on a per-channel cadence after a publish flips
  `published_at`. Cadence is configurable per channel; install-wide defaults
  live on `AppSetting`.
- **Series / sequel tracking** — optional self-FK on `Video`
  (`series_parent_id`) plus `series_part_number` integer column. Tile renders
  a `+part N of M` badge for series members. A dedicated series show page
  lists members ordered by `series_part_number` (NULLS LAST) then by
  `published_at`.
- **Video LINKS section polish** — first-class edit UI for the existing
  `video_links` table, four kinds (`related_video`, `related_channel`,
  `external_resource`, `sponsor`), grouped display on the video show page
  below description.
- **Backfill** — idempotent rake task seeding `series_parent_id` from a
  conservative title regex set (`/—\s*Part\s*\d+/i`, `/Episode\s*\d+/i`,
  `/Part\s*\d+/i`, `/Pt\.?\s*\d+/i`).
- **MCP + CLI parity capture** — sub-spec `01f` documents the MCP tool
  surface that would correspond to each above slice, with the CLI half
  deferred per the active MCP/TUI pause. **No code lanes are dispatched for
  `01f`** — it stays a registry until the pause lifts.

Out of scope:

- Reworking the existing Phase 22 pre-publish modal markup or the
  `pre_publish_*` boolean columns themselves. Phase 11 stacks on top of the
  existing checklist; it does not replace it.
- Reworking the diff-resolution surface (Phase 23). The pre-publish gate
  added here runs **before** publish, not on diff resolution.
- Re-styling the existing horizontal-scroll skin.
- Tenant-scoping. Single-install + multi-user stands (ADR 0003); no
  `tenant_id` columns.
- A dedicated `Series` model. Phase 11 uses the self-FK shape per locked
  decision §6 below — surfacing as an open question for the master agent
  for the final lock.
- Re-architecting `AppSetting` storage. New post-publish cadence fields land
  as plain columns on the existing `app_settings` singleton row.
- Browser-direct resumable upload (the prior Phase 11 outline carried this).
  Re-scope to a future phase if/when filming + upload from the browser
  becomes the user's primary intake path.
- Production state machine + `VideoProduction` table (prior Phase 11
  outline). The current `Video` lifecycle (`privacy_status` + `publish_at` +
  diff resolution + `published_at` flip) covers the use cases that matter
  in Beta.

---

## Locked decisions (master agent)

These apply to every sub-spec. Deviations need a fresh ADR before the
implementation lane is dispatched.

1. **Edit pane primitive.** The video edit surface continues to render
   inside a `.pane.pane--standalone` per `docs/agents/architect.md` rule C.
   Sub-sections (thumbnail, tags, chapters, end-screen, links) stack inside
   that pane — no nested `.pane` rows. The Wave 4a forms sweep already
   wrapped the edit form; sub-spec `01a` audits the wrap and lifts new
   sections into the same container.
2. **Thumbnail storage.** Active Storage `has_one_attached :thumbnail` on
   `Video`. Preview rendered via a new `:thumbnail` variant entry in the
   existing variant pipeline. Local disk in dev; S3 in production via the
   existing storage config — no new storage backend.
3. **Tags input shape.** Free-text comma-separated input bound to the
   existing `videos.tags` text-array column. No new tags table; no
   normalization (per YouTube's tags semantics, free-form is the contract).
4. **Chapters storage.** New `video_chapters` table —
   `id, video_id, start_seconds (integer, ≥0), label (string, ≤100), position (integer), timestamps`.
   Unique on `(video_id, start_seconds)`. Render order is `start_seconds ASC`.
   No timestamps written into `videos.description` in v1 — chapters live in
   their own table; description sync is a follow-up (open question §5).
5. **End-screen storage.** New `video_end_screens` table —
   `id, video_id, kind (enum: related_video / related_channel / related_playlist / none), target_id (string, nullable), target_label (string, nullable), position (integer), timestamps`.
   `kind: none` is a single explicit row marking "no end-screen needed".
   Multiple non-`none` rows are allowed (YouTube end-screens take up to 4
   elements).
6. **Series shape — self-FK.** `videos.series_parent_id` (bigint, nullable,
   FK to `videos.id`, `ON DELETE SET NULL`) + `videos.series_part_number`
   (integer, nullable). Mirrors Phase 28's `version_parent_id` pattern on
   `Game`. One level of nesting only: a video that is itself a series part
   cannot be the parent of another series. Open question §3 surfaces
   whether to lift to a dedicated `Series` model in a follow-up.
7. **Post-publish cadence — install-wide defaults + per-channel overrides.**
   `AppSetting#post_publish_comments_window_hours` (integer, default 24,
   NOT NULL) and `AppSetting#post_publish_analytics_window_days` (integer,
   default 7, NOT NULL) carry the defaults. `channels.post_publish_comments_window_hours`
   and `channels.post_publish_analytics_window_days` (both integer,
   nullable) override per channel when set. The notification scheduler
   reads the channel override first, falls back to the install default.
8. **Notification integration.** Reuses the Phase 16 notification pipeline.
   Two new kinds: `video_comments_due` (severity `normal`, action
   `[reply to comments]` linking to the YouTube Studio comments URL) and
   `video_analytics_due` (severity `normal`, action `[review analytics]`
   linking to the pito video analytics page). Both notifications stamp
   `video_id` on the notification row.
9. **Calendar entries.** Each post-publish notification ALSO derives a
   `CalendarEntry` (`calendar_entry_type: :video_comments_due` /
   `:video_analytics_due`, `state: :scheduled`). The Phase 15
   `CalendarDerivable` concern on `Video` is extended for these two
   additional entry kinds. Cancellation: if the user acknowledges via the
   notification action, the calendar entry flips to `:occurred`.
10. **Pre-publish checks composition.** A new value object
    `Videos::PrePublishChecklist` composes the existing four manual
    booleans PLUS the five new automatic checks. The publish gate calls
    `checklist.passed?` which returns true when every check passes or is
    explicitly skipped with rationale. Skip rationale is persisted to a
    new `video_check_skips` table —
    `id, video_id, check_key (string, NOT NULL), rationale (text, NOT NULL), skipped_by_user_id (FK), skipped_at, timestamps`.
    Unique on `(video_id, check_key)`. Skipping a check overwrites the
    prior skip row (rationale update is allowed).
11. **Bracketed-link convention.** Every clickable link in new copy uses
    the `[label]` form, no inner padding spaces (architect.md rule A).
    Examples: `[skip]`, `[reply to comments]`, `[review analytics]`,
    `[add chapter]`, `[remove]`, `[part 2 of 5]`.
12. **No JS confirm / alert / prompt.** Skip-with-rationale uses an inline
    form (textarea + submit), not a JS prompt. Removing a chapter / link
    goes through `/deletions/...` (bulk-as-foundation, one-element ids
    list). See `CLAUDE.md` hard rules.
13. **Yes / no boundary.** Every JSON / MCP / form Boolean serializes as
    `"yes"` / `"no"` at the wire (CLAUDE.md + architect.md rule E).
    Internal storage stays Boolean. Convert at every boundary.
14. **Friendly URLs preserved.** `/videos/:youtube_video_id/edit`,
    `/videos/:youtube_video_id/chapters/...`,
    `/videos/:youtube_video_id/end_screens/...`,
    `/videos/:youtube_video_id/links/...`,
    `/videos/:youtube_video_id/checks/:check_key/skip`,
    `/series/:id` (Phase 11 v1 — no FriendlyId slug on series parents
    yet; URLs are integer IDs, locked).
15. **MCP scope.** New MCP tools land under the existing `app` scope (per
    ADR 0004 — `dev` and `app` only; no per-tool scope multiplication).
    CLI half is deferred per the active MCP/TUI pause; see sub-spec `01f`.

---

## Cross-stack scope

| Surface               | In scope this phase                                          |
| --------------------- | ------------------------------------------------------------ |
| Rails web (`/videos`) | YES — edit polish, checklist, post-publish, series, links    |
| Rails MCP             | DOC ONLY — surface captured in `01f`; no dispatch this phase |
| `pito` CLI (Rust)     | DEFERRED — MCP/TUI pause; captured in `01f`                  |
| Cloudflare website    | NO                                                           |

---

## Sequencing

Sub-specs land in this order. `01a` and `01b` share schema reach (chapters /
end-screens land in `01a`; the checklist consumes them in `01b`), so `01a`
ships first. `01c` / `01d` / `01e` are parallel-dispatchable once `01a` is
green. `01f` is a docs-only follow-up registry.

1. **01a — Video edit page polish.** Thumbnail attach, tags input,
   chapters nested-form editor, end-screen configuration. Introduces
   `video_chapters` + `video_end_screens` tables + their models +
   factories + nested-attributes wiring on `Video`. Edit form audit
   confirms the `.pane.pane--standalone` wrap; new sub-sections stack
   inside.
2. **01b — Pre-publish checklist expansion.** Composes the five new
   automatic checks on top of the existing four manual booleans via
   `Videos::PrePublishChecklist`. Adds `video_check_skips` table + model
   + skip-rationale inline form. Publish gate routes failing un-skipped
   videos through the action-screen framework. Depends on `01a` (chapters
   + end-screens have to exist before the checks can read them).
3. **01c — Post-publish workflow.** Two new notification kinds, two new
   `CalendarEntry` types via `CalendarDerivable` extension, AppSetting
   default fields + Channel override fields, a
   `Videos::SchedulePostPublishJob` Sidekiq job enqueued by
   `VideoPublish` on successful publish. Parallel with `01d` / `01e`.
4. **01d — Series / sequel tracking.** Migration adds `series_parent_id`
   + `series_part_number`. Model, scopes, validations (one-level rule),
   `Game`-style typeahead picker on edit. Show-page badge + dedicated
   `/series/:id` show route. Backfill rake task. Parallel with `01c` /
   `01e`.
5. **01e — Video LINKS section polish.** First-class edit UI for the
   existing `video_links` table. Enum-backed `kind`. Grouped display on
   video show page below description. Parallel with `01c` / `01d`.
6. **01f — MCP + CLI parity (docs-only follow-up).** Captures the MCP
   tool surface for each `01a` / `01b` / `01c` / `01d` / `01e` slice.
   CLI half deferred. **No implementation lanes dispatched.**

---

## Checkboxes

### 01a — Video edit page polish

- [x] Audit `app/views/videos/edit.html.erb` — confirm the
      `.pane.pane--standalone` wrap exists (per Wave 4a forms sweep). If
      missing, wrap.
- [x] Active Storage `has_one_attached :thumbnail` on `Video`. Image
      validation (PNG / JPEG only, ≤2 MB).
- [x] Thumbnail upload + preview sub-section in the edit pane.
- [x] Tags input — comma-separated text field bound to `videos.tags`. No
      autocomplete; no chip JS.
- [x] Migration: `video_chapters` (`id, video_id, start_seconds, label,
      position, timestamps`; unique on `(video_id, start_seconds)`).
- [x] Migration: `video_end_screens` (`id, video_id, kind enum,
      target_id, target_label, position, timestamps`).
- [x] Models: `VideoChapter`, `VideoEndScreen`, with associations on
      `Video`. `accepts_nested_attributes_for :video_chapters,
      :video_end_screens, allow_destroy: true`.
- [x] Factories: `video_chapter`, `video_end_screen`.
- [x] Chapters nested-form editor — `[add chapter]` link adds a row;
      `[remove]` link sets `_destroy: 1` and hides the row via
      Stimulus (no JS confirm).
- [x] End-screens nested-form editor — single `kind: none` row toggle;
      otherwise up to 4 rows for `related_video` / `related_channel` /
      `related_playlist` with target ID + label.
- [x] Yes/no boundary applied at every Boolean external input (none in
      v1; reserved guard).
- [x] Friendly URLs preserved on the edit route and on any new nested
      routes.
- [x] Spec pyramid sweep — model (chapter + end-screen), factory smoke,
      request (edit + update), component (nested-form partials), system
      (add chapter / add end-screen / remove chapter via the form).

### 01b — Pre-publish checklist expansion

- [ ] Value object `Videos::PrePublishChecklist` —
      `app/lib/videos/pre_publish_checklist.rb`. Composes nine checks:
      the four existing manual booleans + five new automatic checks
      (`thumbnail_attached`, `tags_min_three`,
      `chapters_or_explicit_none`,
      `description_min_100_or_explicit_minimal`,
      `end_screen_configured_or_explicit_none`).
- [ ] Migration: `video_check_skips` (`id, video_id, check_key NOT NULL,
      rationale text NOT NULL, skipped_by_user_id FK, skipped_at,
      timestamps`; unique on `(video_id, check_key)`).
- [ ] Model `VideoCheckSkip` with associations + validations.
- [ ] Factory `video_check_skip`.
- [ ] Skip inline form per check — POST to
      `/videos/:youtube_video_id/checks/:check_key/skip` with
      `rationale` body. Re-submitting overwrites the prior row.
- [ ] Pre-publish modal extension — render the nine checks as a list
      with status indicators (`[ok]`, `[fail]`,
      `[skipped — <rationale snippet>]`) and a `[skip]` link on each
      failing row.
- [ ] Publish gate — `VideosController#publish` / the action-screen for
      publishing routes failing un-skipped videos through the existing
      action-screen framework (`shared/_action_screen.html.erb` +
      `Confirmable`). Hard block: cannot proceed.
- [ ] Yes/no boundary applied at every Boolean external input.
- [ ] Spec pyramid sweep — lib (checklist value object — every check),
      model (`VideoCheckSkip`), request (skip endpoint + publish gate
      happy / sad / edge), component (checklist rendering), system
      (skip a check, publish blocked then unblocked).

### 01c — Post-publish workflow

- [ ] Migration: add `app_settings.post_publish_comments_window_hours`
      (integer, default 24, NOT NULL) and
      `app_settings.post_publish_analytics_window_days` (integer,
      default 7, NOT NULL).
- [ ] Migration: add `channels.post_publish_comments_window_hours`
      (integer, nullable) and
      `channels.post_publish_analytics_window_days` (integer,
      nullable). Validation: ≥0 when present.
- [ ] AppSetting + Channel model updates — accessors + validation.
- [ ] Notification kinds added to the Phase 16 catalog:
      `video_comments_due`, `video_analytics_due`. Action labels
      `[reply to comments]` and `[review analytics]` per locked
      decision §8.
- [ ] `CalendarDerivable` extension on `Video` — derives
      `:video_comments_due` and `:video_analytics_due` calendar entries
      keyed on the same `video_id`.
- [ ] Sidekiq job `Videos::SchedulePostPublishJob` — enqueued by
      `VideoPublish` after a successful publish (and by the
      `published_at` first-set hook for videos that bypass
      `VideoPublish`). Reads cadence from channel override → AppSetting
      default. Enqueues `Notifications::FireNotificationJob` at
      `published_at + comments_window` and at `published_at +
      analytics_window`. Idempotent — re-enqueue on a re-publish
      replaces prior pending jobs (per `jid` stamping on the
      notification row).
- [ ] Settings UI — new fields on `/settings` (or
      `/settings/notifications`, wherever Phase 16 currently surfaces
      notification config). Per-channel overrides land on
      `/channels/:id/edit`.
- [ ] Yes/no boundary applied at every Boolean external input (none in
      v1; reserved guard).
- [ ] Spec pyramid sweep — model (AppSetting + Channel validations),
      job (`Videos::SchedulePostPublishJob` happy / sad / edge /
      idempotency), service (cadence resolution), request (settings +
      channel edit), system (publish a video, calendar entry appears,
      notification fires at the scheduled time via
      `Sidekiq::Testing.inline!`).

### 01d — Series / sequel tracking

- [ ] Migration: add `videos.series_parent_id` (bigint, nullable, FK
      to `videos.id`, indexed) and `videos.series_part_number`
      (integer, nullable).
- [ ] Foreign key `ON DELETE SET NULL` so destroying a parent leaves
      its members as orphan primaries.
- [ ] Model: `Video.belongs_to :series_parent, optional: true,
      class_name: "Video"`, `Video.has_many :series_members,
      foreign_key: :series_parent_id, dependent: :nullify,
      class_name: "Video"`.
- [ ] Scopes: `Video.series_parents` (rows with members),
      `Video.in_series_of(video)`.
- [ ] Validations: one-level only (a member cannot be a parent;
      chosen parent must itself be `series_parent_id IS NULL`); no
      self-reference.
- [ ] Game-style typeahead picker on video edit — search by title only,
      capped 20 results, members excluded.
- [ ] Show-page badge — `+part N of M` (singular `+part 1 of 1`
      displays as plain `[part 1]` per architect.md rule A).
- [ ] `/series/:id` show page — lists members ordered by
      `series_part_number ASC NULLS LAST, published_at ASC`.
- [ ] Backfill rake task `videos:backfill_series_parents` — title
      regex driven (`/—\s*Part\s*\d+/i`, `/Episode\s*\d+/i`,
      `/Part\s*\d+/i`, `/Pt\.?\s*\d+/i`); idempotent; safe to re-run.
- [ ] Yes/no boundary applied at every Boolean external input.
- [ ] Spec pyramid sweep — model (associations, scopes, validations),
      request (edit picker + show + /series/:id), system (attach via
      picker, detach via edit, badge renders), rake (idempotent
      backfill against a fixture set).

### 01e — Video LINKS section polish

- [ ] Audit `video_links` table — confirm columns
      `id, video_id, url, label, kind, position, timestamps` exist.
      If `kind` is missing, migrate to add (integer enum-backed:
      `related_video / related_channel / external_resource / sponsor`).
- [ ] Model `VideoLink` — enum on `kind` with prefix `kind`.
      Validations (URL format, label ≤100 chars). Scope by kind.
- [ ] First-class edit UI on the video edit pane — nested-attributes
      sub-section with `[add link]` and `[remove]` per row. Sortable
      via the existing position pattern.
- [ ] Show page — grouped display below description: one heading per
      `kind` (skipped when empty), bracketed-link rendering of each
      link.
- [ ] Yes/no boundary applied at every Boolean external input (none in
      v1; reserved guard).
- [ ] Spec pyramid sweep — model (enum, validations, scopes), request
      (edit + update + show), component (grouped display partial),
      system (add a link, kind switches, remove, show page renders).

### 01f — MCP + CLI parity (docs-only follow-up)

- [ ] Capture the MCP tool surface for each `01a` / `01b` / `01c` /
      `01d` / `01e` slice. Suggested names:
      `video_chapters_list / set`,
      `video_end_screens_list / set`,
      `video_links_list / set`,
      `video_checks_skip`,
      `video_series_attach / detach`,
      `video_post_publish_cadence_set`.
- [ ] Note CLI deferral per the active MCP/TUI pause. Cross-link the
      pause note in `docs/orchestration/follow-ups.md`.
- [ ] **No implementation lanes dispatched.** This sub-spec is a
      registry, not a deliverable.

---

## Open questions (surfaced for master agent)

1. **Pre-publish checklist gate behind AppSetting?** Some users may find
   the expanded checklist annoying. Architect leans **no gate** — the
   checklist is the publish gate, and skip-with-rationale is the escape
   hatch. If the user disagrees, surface an
   `AppSetting#pre_publish_strict` Boolean (default `true`) that, when
   `false`, downgrades failing checks to warnings instead of hard blocks.
   Lock before `01b` dispatches.
2. **Default post-publish cadence values.** Architect proposes 24 hours
   for the comments window and 7 days for the analytics window per the
   prompt's suggestion. Surface for user lock before `01c` dispatches.
3. **Series shape — self-FK vs dedicated `Series` model.** Architect
   leans self-FK to mirror Phase 28's `version_parent_id` pattern and
   avoid a second table. A dedicated `Series` model becomes attractive
   if series gain their own metadata (title, description, cover image)
   — surface as a follow-up if the user wants that surface in `01d` v1.
4. **Thumbnail upload bytes — local sync vs YouTube sync.** Phase 11
   stores the thumbnail locally via Active Storage. Pushing it back to
   YouTube via `thumbnails.set` is a follow-up (the existing
   `VideoSyncBack` job handles the writable subset; thumbnails are a
   separate endpoint). Surface for user lock — does the user want the
   YouTube-side sync inside `01a`, or as a follow-up?
5. **Chapter timestamps writing into description.** YouTube derives
   video chapters from `00:00` timestamps in the description. Phase 11
   stores chapters in a dedicated table and does NOT rewrite the
   description. A follow-up would render the chapters into the
   description on sync-back. Surface for user lock — does `01a` close
   the loop end-to-end (write chapters into description on save), or
   strictly local-only in v1?
6. **End-screen target validation.** YouTube end-screens require valid
   video / channel / playlist IDs. Phase 11 v1 accepts free-text — no
   round-trip validation against YouTube. Surface for user lock — is
   the free-text shape acceptable for v1, or do we need an in-form
   lookup?
7. **Backfill scope for series.** Architect leans rake-only against the
   existing dev DB. Surface for user lock — also fold into
   `db/seeds.rb`?

---

## Quality gates

Standard Beta gates (see `beta.md` §"Per-phase quality gates").
Additional phase-specific checks:

- Full spec pyramid sweep per `docs/agents/architect.md` rule D for every
  sub-spec.
- yes/no boundary applied at every external Boolean (URL params, JSON,
  MCP I/O, CLI args, form params).
- No `alert` / `confirm` / `prompt` / `data-turbo-confirm` anywhere. Skip
  with rationale uses an inline form; chapter / link removal goes through
  `/deletions/...`; the pre-publish gate routes through
  `shared/_action_screen.html.erb`.
- Friendly URLs preserved across all touched routes.
- Brakeman + bundler-audit + Dependabot triage clean.
- Idempotent migrations + idempotent backfill rake task.
- Pane primitive: edit form lives in `.pane.pane--standalone`; show page
  reads inside the existing show wrap.

---

## Manual test recipe (high-level)

A detailed recipe per sub-spec lives in the relevant `specs/01*.md` file.
The phase-level smoke test:

1. `bin/setup` → `bin/rails db:migrate` → `bin/rails db:seed`.
2. `bin/dev` → open
   `http://localhost:3000/videos/<some_yt_id>/edit`.
3. Confirm the edit pane wraps in `.pane.pane--standalone`.
4. Upload a thumbnail; preview renders.
5. Type `gaming, dev, pito` into tags; save; reload — tags persist.
6. Click `[add chapter]` twice; enter `0` / `Intro` and `120` / `Setup`;
   save; reload — both chapters present in order.
7. Click `[add end screen]`; choose `related_video`; enter a YouTube ID
   + label; save; reload — end screen persists.
8. Pre-publish: click `[run pre-publish check]` — modal lists nine
   checks with their status. Click `[skip]` on one failing check; enter
   rationale `not applicable for this video`; submit.
9. Confirm the failing-but-skipped check now shows
   `[skipped — not applicable for this video]`.
10. Hit publish — if any check is still failing AND not skipped, the
    action-screen confirmation page renders with the failing list and a
    `[cancel]` link. No JS confirm fires.
11. Once publish succeeds, the calendar shows `video_comments_due` 24 h
    out and `video_analytics_due` 7 d out. Override the channel cadence
    to 1 h / 1 d; re-publish — the calendar entries update.
12. Edit a video and attach a series parent via the typeahead picker;
    save — the show page renders the `[part N of M]` badge.
13. Visit `/series/:id` — every member of the series lists in part
    order.
14. Run `rake videos:backfill_series_parents` against a fixture of
    "Stream — Part 1", "Stream — Part 2", "Stream — Part 3" — confirm
    all three attach under a single parent.
15. Add three links to a video (one of each kind); save — show page
    renders the four-kind grouped section below the description.

Detailed per-step expected values land in the per-spec manual recipes.

---

## Additions / dropped tracking

This phase opens two tracking files lazily:

- `docs/plans/beta/11-video-workflow-features/additions.md`
- `docs/plans/beta/11-video-workflow-features/dropped.md`

Neither is created up front — `pito-docs` opens them on first need.

---

## Phase log

Append-only at:
`docs/plans/beta/11-video-workflow-features/log.md`.

`pito-docs` opens it after the first sub-spec implementation lands.

---

## References

- `docs/plans/beta/beta.md` — master Beta plan.
- `docs/plans/beta/12-*` — original Video schema expansion (writable
  subset, four-boolean checklist).
- `docs/plans/beta/22-*` — pre-publish modal + check (Phase 11 stacks on
  top, does not replace).
- `docs/plans/beta/23-*` — video diff resolution (Phase 11 publish gate
  runs before publish, not on diff resolution).
- `docs/plans/beta/26-*` §01g + §01h — analytics integration +
  timezone-aware scheduled publishing.
- `docs/plans/beta/15-*` — calendar derivation (Phase 11 extends
  `CalendarDerivable` on `Video` for two new entry types).
- `docs/plans/beta/16-*` — notifications pipeline (Phase 11 adds two
  kinds).
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/plan.md`
  — reference for typeahead picker shape (series parent picker mirrors
  it).
- `docs/plans/beta/28-multi-version-game-grouping/plan.md` — reference
  for self-FK shape (series tracking mirrors `version_parent_id`).
- `docs/agents/architect.md` — spec pyramid (D), bracketed-link rule
  (A), pane primitives (C), yes/no boundary (E), tenant-free reminder
  (F).
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — auth
  model.
- `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — MCP scope
  reference (the new MCP tools captured in `01f` land under `app`).
- `docs/design.md` — bracketed-link convention, monospace style, no red
  outside destructive actions.
- `CLAUDE.md` — hard rules (no JS confirm, bulk-as-foundation, secrets
  in credentials, yes/no boundary).
