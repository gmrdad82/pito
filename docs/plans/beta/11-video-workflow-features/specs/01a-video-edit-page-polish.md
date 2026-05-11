# 01a — Video Edit Page Polish

> Parent: `docs/plans/beta/11-video-workflow-features/plan.md`.
> Read the parent first. This sub-spec is dispatchable on its own once the
> parent's locked decisions are accepted by the master agent.

---

## Goal

Lift the bare video edit page into a workflow-grade surface. Today the edit
form covers the writable YouTube subset (title, description, tags, category,
privacy, publish_at, project) and nothing else. After this sub-spec lands, the
edit pane stacks four new sub-sections inside the existing
`.pane.pane--standalone` wrap: thumbnail (upload + preview), tags (text
input bound to `videos.tags`), chapters (nested-form editor), end-screens
(nested-form editor up to 4 rows or one `kind: none` row).

The thumbnail is stored locally via Active Storage. Chapters live in a new
`video_chapters` table. End-screens live in a new `video_end_screens` table.
No YouTube-side write-back for thumbnails / chapters / end-screens in v1 —
those are open questions §4 + §5 + §6 of the parent plan, surfaced for later
follow-up.

---

## Files touched

### Migrations

- `db/migrate/<TS>_create_video_chapters.rb`
- `db/migrate/<TS>_create_video_end_screens.rb`
- `db/migrate/<TS>_install_active_storage_for_video_thumbnail.rb` — only if
  Active Storage tables don't yet exist (audit `bin/rails
  active_storage:install` output; the project already uses Active Storage
  for game cover variants, per Phase 27 §01e — so this migration is likely
  a no-op).

### Models

- `app/models/video.rb` — add `has_one_attached :thumbnail`,
  `has_many :video_chapters, -> { order(:start_seconds) }, dependent: :destroy`,
  `has_many :video_end_screens, -> { order(:position) }, dependent: :destroy`,
  `accepts_nested_attributes_for :video_chapters, allow_destroy: true,
  reject_if: :all_blank`,
  `accepts_nested_attributes_for :video_end_screens, allow_destroy: true,
  reject_if: :all_blank`.
- `app/models/video_chapter.rb` (new).
- `app/models/video_end_screen.rb` (new).

### Validators

- Thumbnail Active Storage validation — inline via `validate
  :thumbnail_content_type_and_size` on `Video` (no new validator class
  unless the same shape recurs in `01a` and another sub-spec).

### Factories

- `spec/factories/video_chapters.rb` (new).
- `spec/factories/video_end_screens.rb` (new).
- `spec/factories/videos.rb` — extend with traits `:with_thumbnail`,
  `:with_chapters`, `:with_end_screens`.

### Controllers

- `app/controllers/videos_controller.rb` — extend `video_params` to permit
  `:thumbnail`, `video_chapters_attributes`, `video_end_screens_attributes`.

### Views

- `app/views/videos/edit.html.erb` — audit / confirm
  `.pane.pane--standalone` wrap; add four new sub-section partials.
- `app/views/videos/_edit_thumbnail.html.erb` (new).
- `app/views/videos/_edit_tags.html.erb` (new).
- `app/views/videos/_edit_chapters.html.erb` (new).
- `app/views/videos/_edit_end_screens.html.erb` (new).
- `app/views/video_chapters/_fields.html.erb` (new — nested-form row
  partial).
- `app/views/video_end_screens/_fields.html.erb` (new — nested-form row
  partial).

### Stimulus

- `app/javascript/controllers/nested_form_controller.js` — single
  generic controller for `[add row]` / `[remove]` on nested
  attributes. If a comparable controller already exists in the project
  (audit before implementing), reuse it; otherwise add. **No JS confirm
  anywhere.**

### CSS

- `app/assets/tailwind/application.css` (or whichever the Tailwind entry
  is) — only if new utility classes are required. Prefer existing pane +
  list classes; no bespoke layouts.

### Routes

- `config/routes.rb` — no new routes. Nested-form attributes ride the
  existing `PATCH /videos/:youtube_video_id`.

### Specs

- `spec/models/video_chapter_spec.rb` (new).
- `spec/models/video_end_screen_spec.rb` (new).
- `spec/models/video_spec.rb` — extend with thumbnail validation cases +
  nested-attributes acceptance.
- `spec/factories/video_chapters_spec.rb` (factory smoke).
- `spec/factories/video_end_screens_spec.rb` (factory smoke).
- `spec/requests/videos_spec.rb` — extend `edit` + `update` request
  examples (happy / sad / edge) covering the new fields.
- `spec/views/videos/_edit_thumbnail.html.erb_spec.rb` (new).
- `spec/views/videos/_edit_chapters.html.erb_spec.rb` (new).
- `spec/views/videos/_edit_end_screens.html.erb_spec.rb` (new).
- `spec/system/video_edit_polish_spec.rb` (new) — system spec covering
  add / remove chapter, add / remove end-screen, toggle `kind: none`,
  thumbnail upload + preview, save persists.

---

## Acceptance

- [ ] `.pane.pane--standalone` wraps the edit form end-to-end. New
      sub-sections stack inside.
- [ ] `Video.new.thumbnail.attached?` returns `false`. After upload, the
      thumbnail attaches and the preview renders.
- [ ] Thumbnail upload rejects non-PNG / non-JPEG content types with a
      flash error.
- [ ] Thumbnail upload rejects files >2 MB with a flash error.
- [ ] Tags input round-trips a comma-separated value to the
      `videos.tags` text-array column.
- [ ] `[add chapter]` adds a new chapter row (start_seconds + label) via
      Stimulus, no page reload.
- [ ] `[remove]` on a chapter row sets `_destroy: 1`, hides the row;
      submit deletes the chapter on the server.
- [ ] Chapters render in the form ordered by `start_seconds ASC`.
- [ ] Unique constraint on `(video_id, start_seconds)` rejects duplicate
      timestamps with a validation error surfaced inline.
- [ ] `[add end screen]` adds an end-screen row with `kind` dropdown
      (related_video / related_channel / related_playlist).
- [ ] Toggling `kind: none` collapses to a single explicit row marking
      "no end-screen needed"; the other rows are removed on save.
- [ ] End-screens table enforces no more than 4 non-`none` rows per
      video (model-level validation; YouTube cap).
- [ ] `Video#video_chapters_attributes=` accepts a nested-attributes
      payload via `accepts_nested_attributes_for`.
- [ ] `Video#video_end_screens_attributes=` accepts a nested-attributes
      payload via `accepts_nested_attributes_for`.
- [ ] `bundle exec rspec` green on every new + extended spec file
      enumerated above.
- [ ] No `alert` / `confirm` / `prompt` / `data-turbo-confirm` in any
      new or modified template / JS file.
- [ ] Friendly URL preserved on the edit route
      (`/videos/:youtube_video_id/edit`).
- [ ] Yes/no boundary placeholder verified — no Boolean external inputs
      in v1; a comment in `videos_controller.rb` documents the reserved
      guard for future writable Booleans.

---

## Manual test recipe

1. `bin/setup` → `bin/rails db:migrate` → `bin/dev`.
2. Visit `http://localhost:3000/videos/<some_yt_id>/edit`.
3. Confirm the page renders inside one `.pane.pane--standalone`.
4. **Thumbnail.** Click the thumbnail picker; choose a 1280×720 JPEG
   under 2 MB; submit the form. Reload. Preview renders.
5. **Thumbnail — reject path.** Choose a `.txt` file; submit; observe
   the flash error and that the form re-renders with the validation
   message.
6. **Tags.** In the tags field type `gaming, dev, pito`; submit.
   Reload. Tags persist (verify in Rails console:
   `Video.find_by!(youtube_video_id: '<yt_id>').tags
   # => ["gaming", "dev", "pito"]`).
7. **Chapters — add.** Click `[add chapter]` twice. First row:
   `start_seconds = 0`, `label = Intro`. Second row:
   `start_seconds = 120`, `label = Setup`. Submit. Reload. Both
   chapters present in order; the form shows them by `start_seconds`.
8. **Chapters — uniqueness.** Click `[add chapter]`; enter
   `start_seconds = 0`, `label = Duplicate`. Submit. Observe the
   validation error inline; the row stays in the form.
9. **Chapters — remove.** Click `[remove]` on the `Setup` row.
   Submit. Reload. Only `Intro` remains.
10. **End-screens — add.** Click `[add end screen]`; pick
    `related_video` from the dropdown; enter
    `target_id = dQw4w9WgXcQ`, `target_label = Watch next`. Submit.
    Reload. End-screen present.
11. **End-screens — toggle `kind: none`.** Toggle `kind: none` on a
    single row. Submit. Reload. One row remains, marked "no end-screen
    needed"; the prior `related_video` row was removed.
12. **End-screens — 4-row cap.** Add 5 non-`none` rows. Submit. Observe
    the validation error; the form re-renders.
13. **No JS confirm.** Walk through every `[remove]` click; verify no
    browser dialog fires (use the browser console: `window.confirm`
    is never called).
14. **`bundle exec rspec`** — every new and extended spec file is
    green.

---

## Cross-stack scope

| Surface              | Status                                          |
| -------------------- | ----------------------------------------------- |
| Rails web            | IN SCOPE                                        |
| Rails MCP            | DEFERRED — captured in sub-spec `01f`           |
| `pito` CLI (Rust)    | DEFERRED — MCP/TUI pause; captured in `01f`     |
| Cloudflare website   | OUT OF SCOPE                                    |

---

## Open questions

1. **Variant size for the thumbnail preview.** The IGDB cover-art
   pipeline uses `:grid` (150×200) and `:shelf` (98×130) variants per
   Phase 27 §01e. Video thumbnails are 16:9; a sensible v1 preview
   variant is `:thumbnail_sm` (320×180). Lock before dispatch.
2. **Stimulus controller reuse.** Does a generic nested-form controller
   already live in `app/javascript/controllers/`? Audit before adding a
   new one. If a similar one exists (e.g., for Phase 28's editions
   typeahead), reuse it.
3. **End-screen target validation.** Free-text in v1 (parent open
   question §6). Surface again here for the implementation agent — if
   the user wants YouTube-side validation in `01a`, the spec expands by
   ~150 lines (lookup service + caching + error UX).
4. **Thumbnail YouTube push-back.** Parent open question §4 — out of
   scope for `01a`, but the implementation agent should comment the
   reserved hook point in `VideoSyncBack` so the follow-up is cheap.
