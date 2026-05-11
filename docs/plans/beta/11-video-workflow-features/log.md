# Phase 11 — log

## 2026-05-11 — Sub-spec 01a video edit page polish (pito-rails-impl) [skipci]

Implemented Phase 11 sub-spec 01a end-to-end. Locked decisions §1–§14 from
`plan.md` were honored; the four open questions in the sub-spec were resolved
on the architect's lean (per the autonomy memory). No deviations.

### Open-question resolutions

1. Thumbnail preview variant — `:thumbnail_sm` (320×180, `resize_to_limit`)
   per architect lean. Exposed via `Video#thumbnail_preview`; renders only when
   blob content-type is in `THUMBNAIL_ALLOWED_TYPES` so the failure-render
   path doesn't blow up on `ActiveStorage::InvariableError` for a rejected
   non-image blob.
2. Stimulus controller reuse — none existed for nested-attributes editing
   under `app/javascript/controllers/`. Added a single generic
   `nested_form_controller.js` (no JS confirm, target contract documented).
3. End-screen target validation — free-text in v1, per parent open question
   §6. No YouTube round-trip lookup.
4. Thumbnail YouTube push-back — out of scope per parent open question §4.
   Reserved hook point documented in `app/jobs/video_sync_back.rb` (comment
   bookmark above the `update_video` call).

### Migrations applied

- `20260511204435_create_video_chapters.rb` — `id, video_id, start_seconds,
  label (≤100), position, timestamps`; unique on `(video_id, start_seconds)`;
  FK ON DELETE CASCADE.
- `20260511204436_create_video_end_screens.rb` — `id, video_id, kind (int
  enum), target_id, target_label (≤100), position, timestamps`; FK ON DELETE
  CASCADE.

Both applied to dev DB and test DB. Schema dump verified.

### Files touched

- `app/models/video.rb` — `has_one_attached :thumbnail`,
  `has_many :video_chapters / :video_end_screens`,
  `accepts_nested_attributes_for` for both, `thumbnail_preview` helper,
  `thumbnail_content_type_and_size` validator, `end_screens_invariants`
  parent-side validator.
- `app/models/video_chapter.rb` (new) — model + validations + `ordered`
  scope.
- `app/models/video_end_screen.rb` (new) — model + enum + per-row validators
  with deferral to parent when nested-attributes is the save driver.
- `app/policies/video_policy.rb` — extended `EDITABLE_ATTRS` with
  `thumbnail`; added `video_chapters_attributes` and
  `video_end_screens_attributes` to `EDITABLE_ARRAY_ATTRS`.
- `app/controllers/videos_controller.rb` — `edit` and update failure-paths
  populate `@video_chapters / @video_end_screens`; new
  `collapse_end_screens_if_none!` helper enforces the `kind: none`
  collapse semantic on save (drops / `_destroy`s every other submitted
  row + sweeps persisted non-none rows not in the submitted set);
  reserved yes/no boundary guard comment.
- `app/jobs/video_sync_back.rb` — reserved hook comment for thumbnail
  push-back.
- `app/views/videos/edit.html.erb` — pane wrap re-confirmed; renders the
  new sub-section partials via the existing form partial.
- `app/views/videos/_form.html.erb` — `multipart: true`, tags moved into
  its own sub-section partial, four new partials wired in order.
- `app/views/videos/_edit_thumbnail.html.erb` (new) — preview + file input,
  no-thumbnail empty state, PNG/JPEG + 2 MB hint.
- `app/views/videos/_edit_tags.html.erb` (new) — extracted comma-separated
  tags input.
- `app/views/videos/_edit_chapters.html.erb` (new) — nested-form wrapper
  with `[add chapter]` button + hidden row template.
- `app/views/videos/_edit_end_screens.html.erb` (new) — nested-form wrapper
  with `[add end screen]` button + hidden row template.
- `app/views/video_chapters/_fields.html.erb` (new) — row partial.
- `app/views/video_end_screens/_fields.html.erb` (new) — row partial with
  kind select.
- `app/javascript/controllers/nested_form_controller.js` (new) — generic
  add / remove behavior; no JS confirm.

### Specs added / extended

- `spec/models/video_chapter_spec.rb` (new, 5 examples) — associations,
  validations, `ordered` scope.
- `spec/models/video_end_screen_spec.rb` (new, 11 examples) — enum, per-
  row validators (direct-AR path) + parent-driven nested-attributes path,
  `ordered` scope.
- `spec/models/video_spec.rb` — extended with associations, thumbnail
  attachment + validation cases, chapter and end-screen nested-attributes
  coverage (+18 examples).
- `spec/lib/video_chapter_factory_spec.rb` (new) — factory smoke.
- `spec/lib/video_end_screen_factory_spec.rb` (new) — factory smoke + 3
  traits (`:related_channel`, `:related_playlist`, `:none`).
- `spec/factories/videos.rb` — three new traits (`:with_thumbnail`,
  `:with_chapters`, `:with_end_screens`) + `VideoFactoryHelpers` module
  exposing a minimal valid PNG byte sequence.
- `spec/factories/video_chapters.rb` (new) + `spec/factories/video_end_screens.rb`
  (new).
- `spec/requests/videos_spec.rb` — Phase 11 §01a describe block (+15
  examples) covering edit-page rendering, thumbnail upload happy /
  rejection paths, chapters nested-attribute create / destroy /
  duplicate-422, end-screens nested-attribute create / collapse-on-none /
  cap-5-rejection, no JS confirm tokens, friendly-URL preservation.
- `spec/views/videos/_edit_thumbnail.html.erb_spec.rb` (new, 5 examples).
- `spec/views/videos/_edit_chapters.html.erb_spec.rb` (new, 5 examples).
- `spec/views/videos/_edit_end_screens.html.erb_spec.rb` (new, 5 examples).
- `spec/system/video_edit_polish_spec.rb` (new, 7 examples, rack_test) —
  pane wrap + thumbnail upload + tags round-trip + nested-attribute
  submit simulating Stimulus add for chapters + end-screens + kind:none
  collapse + no JS confirm assertion.

Note on factory smoke specs: `spec/factories/` is auto-loaded by FactoryBot's
railtie, so `*_spec.rb` files placed there are parsed as factory definitions
and break boot. The Phase 11 factory smokes therefore live in `spec/lib/`,
mirroring the existing `spec/lib/factories_smoke_spec.rb` convention.

### Spec runs

```
bundle exec rspec spec/models/video_chapter_spec.rb \
  spec/models/video_end_screen_spec.rb spec/models/video_spec.rb \
  spec/lib/video_chapter_factory_spec.rb \
  spec/lib/video_end_screen_factory_spec.rb \
  spec/requests/videos_spec.rb \
  spec/views/videos/_edit_thumbnail.html.erb_spec.rb \
  spec/views/videos/_edit_chapters.html.erb_spec.rb \
  spec/views/videos/_edit_end_screens.html.erb_spec.rb \
  spec/system/video_edit_polish_spec.rb
# 276 examples, 0 failures
```

Adjacent specs (video_calendar_derivation, video_diff, video_friendly_url,
video_sync_back) ran clean alongside. Three pre-existing failures in
`spec/requests/videos_spec.rb` (`renders the privacy_status column`,
`renders the name column header as a server-side sort link`,
`keyboard-row markup`) are unrelated to Phase 11 — confirmed by running
them against `HEAD` without any of this session's diffs in scope.

### Rubocop

```
bundle exec rubocop <touched .rb files>
# 21 files inspected, no offenses detected
```

### Open issues / follow-ups

- `[skip]` rationale form + checklist composition land in sub-spec 01b
  (depends on 01a; checklist will read chapters + end-screens count
  among the auto-checks).
- Thumbnail YouTube push-back via `thumbnails.set` — parent open
  question §4. Hook point reserved in `VideoSyncBack`.
- Chapter timestamps writing into `videos.description` — parent open
  question §5. Local-only in v1.
- End-screen target lookup against YouTube — parent open question §6.
  Free-text in v1.
