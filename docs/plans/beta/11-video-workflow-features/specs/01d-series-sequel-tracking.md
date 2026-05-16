# 01d — Series / Sequel Tracking

> Parent: `docs/plans/beta/11-video-workflow-features/plan.md`.
> Parallel-dispatchable with `01c` and `01e` once `01a` lands. Mirrors the Phase
> 28 `version_parent_id` pattern on `Game` — read
> `docs/plans/beta/28-multi-version-game-grouping/plan.md` first for the
> reference shape.

---

## Goal

Today a "series" exists only in the title regex of related videos ("Stream —
Part 1", "Stream — Part 2"). Phase 11 introduces a self-referential parent /
member relationship on `Video` (`series_parent_id`, `series_part_number`),
exposes the relationship on the edit + show + dedicated `/series/:id` route, and
ships a backfill rake task to seed `series_parent_id` from a conservative title
regex.

The shape mirrors Phase 28's `Game.version_parent_id` pattern. One level of
nesting only — a video that is itself a series member cannot be the parent of
another series.

---

## Files touched

### Migrations

- `db/migrate/<TS>_add_series_parent_to_videos.rb` — adds
  `videos.series_parent_id` (bigint, nullable, FK to `videos.id`
  `ON DELETE SET NULL`, indexed) and `videos.series_part_number` (integer,
  nullable).

### Models

- `app/models/video.rb` —
  `belongs_to :series_parent, class_name: "Video", optional: true`,
  `has_many :series_members, foreign_key: :series_parent_id, class_name: "Video", dependent: :nullify`.
  Scopes: `Video.series_parents`, `Video.in_series_of(video)`. Validations:
  one-level only (`validate :series_parent_must_be_primary`,
  `validate :no_self_series_reference`).

### Controllers

- `app/controllers/videos_controller.rb` — extend `video_params` to permit
  `:series_parent_id` and `:series_part_number`.
- `app/controllers/series_controller.rb` (new) — single `show` action
  (`GET /series/:id`). Reads `Video.find(params[:id])`, raises if the video is
  not a primary (`series_parent_id.present?` → redirect to the actual primary).

### Views

- `app/views/videos/_edit_series.html.erb` (new) — sub-section on the edit pane.
  Typeahead picker for `series_parent_id` (search by title, capped 20 results,
  members excluded — only primaries shown). Plain number input for
  `series_part_number`. `[detach]` link sets `series_parent_id = nil` via the
  same edit form submit.
- `app/views/videos/_series_badge.html.erb` (new) — renders `+part N of M` on
  tiles + show pages for series members. Plural rule: `+part 1 of 1` renders as
  plain `[part 1]` per architect.md rule A (no inner padding spaces; minimum
  text).
- `app/views/series/show.html.erb` (new) — lists members ordered by
  `series_part_number ASC NULLS LAST, published_at ASC`. Each row is a bracketed
  link to the video show page.

### Routes

- `config/routes.rb` — add `resources :series, only: [:show]`. Integer ID URL
  (no FriendlyId in v1; parent locked decision §14).

### Rake

- `lib/tasks/videos.rake` — `videos:backfill_series_parents`. Regex list:
  `/—\s*Part\s*\d+/i`, `/Episode\s*\d+/i`, `/Part\s*\d+/i`, `/Pt\.?\s*\d+/i`.
  Pre-resolves the parent title (strip the matched segment; collapse
  whitespace), creates the parent video if missing (or finds the existing parent
  by stripped title), stamps `series_parent_id` + `series_part_number`.
  Idempotent — re-running the task does not create duplicates.

### Specs

- `spec/models/video_spec.rb` — extend with association tests, scope tests,
  one-level validation tests, backfill helpers.
- `spec/requests/videos_spec.rb` — extend `edit` / `update` to cover the picker
  submission.
- `spec/requests/series_spec.rb` (new) — show happy / sad / edge (non-primary
  redirect).
- `spec/system/video_series_tracking_spec.rb` (new) — attach via picker, detach
  via edit, badge renders on tile + show page.
- `spec/tasks/videos_backfill_series_parents_spec.rb` (new) — idempotent
  backfill against a fixture set covering each regex.

---

## Acceptance

- [ ] Migration adds `series_parent_id` (FK) + `series_part_number` (integer) to
      `videos`. Both nullable. FK is `ON DELETE SET NULL`.
- [ ] `Video.belongs_to :series_parent` returns the parent row when set, nil
      otherwise.
- [ ] `Video.has_many :series_members` returns the rows pointing at `self.id`.
- [ ] `Video.series_parents` scope returns rows that have members.
- [ ] `Video.in_series_of(video)` returns the parent's members + the parent
      itself (for ordering consistency on the series show page).
- [ ] Validation rejects setting `series_parent_id` on a video that already has
      members (one-level rule).
- [ ] Validation rejects setting `series_parent_id` to a video that is itself a
      member.
- [ ] Validation rejects self-reference (`series_parent_id == self.id`).
- [ ] Edit form typeahead returns up to 20 primaries by title; members are
      excluded.
- [ ] Submitting `series_parent_id = nil` via the edit form detaches.
- [ ] Series show page (`/series/:id`) lists members ordered by
      `series_part_number ASC NULLS LAST, published_at ASC`.
- [ ] Non-primary `/series/:id` access redirects to the actual primary.
- [ ] Badge renders `+part N of M` (plural `+part 1 of 1` → `[part 1]`).
- [ ] Backfill rake task attaches members to a stripped-title parent; idempotent
      on re-run.
- [ ] Yes/no boundary placeholder — no Boolean external inputs in v1; reserved
      guard documented inline.
- [ ] Friendly URL preserved on the video edit / show routes; `/series/:id` is
      integer (per parent locked decision §14).
- [ ] `bundle exec rspec` green on every new + extended spec file.

---

## Manual test recipe

1. `bin/rails db:migrate`.
2. `bin/dev` → visit `http://localhost:3000/videos/<some_yt_id>/edit`.
3. Use the typeahead picker to attach a series parent. Pick a different video by
   title. Enter `series_part_number = 1`. Submit.
4. Visit the show page — `[part 1]` badge renders next to the title.
5. Visit `/series/<parent_id>` — the show page lists the just-attached member
   ordered by part.
6. Attach a second member with `series_part_number = 2`. Confirm the
   `/series/<parent_id>` page lists both in order.
7. Detach the second member via the edit form (clear the picker). Confirm the
   badge disappears and the member no longer lists on the parent's series page.
8. **Validation — one-level.** Attempt to attach a series parent to a video that
   has members; confirm the form shows a validation error.
9. **Validation — self-reference.** Attempt to attach a video to itself; confirm
   the form shows a validation error.
10. **Backfill.** Create three videos titled "Stream — Part 1", "Stream — Part
    2", "Stream — Part 3". Run:
    ```bash
    bin/rails videos:backfill_series_parents
    ```
    Confirm all three attach to a single parent (stripped title "Stream").
    Re-run the task; confirm no duplicates appear.
11. **Backfill — Episode/Pt/GOTY variants.** Repeat for "Show Episode 1" /
    "Episode 2", "Halo Pt. 1" / "Pt 2", etc. — each regex tier attaches as
    expected.
12. `bundle exec rspec` — green.

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

1. **Series vs dedicated `Series` model.** Parent open question §3 — architect
   leans self-FK. If the user wants a dedicated model with its own title /
   description / cover, surface as a follow-up (`11/02-series-model.md`).
2. **Badge link target.** Click on `+part N of M` — does it go to the parent
   (`/videos/<parent_yt_id>`) or to the series show page
   (`/series/<parent_id>`)? Architect leans the series show page; surface for
   user lock.
3. **Backfill scope — seeds?** Parent open question §7 — architect leans
   rake-only. Surface for user lock.
4. **Typeahead source.** Search by title only — `LOWER(title) ILIKE '%query%'`
   capped at 20 results. If performance becomes an issue on a large library,
   swap to Meilisearch (Phase 10) as a follow-up.
5. **Detach side-effects.** Detaching a member that is the last member of a
   parent leaves the parent as a primary with no members. Architect leans no
   special-casing — the parent stays a primary, the badge logic just sees
   `series_members.count == 0` and renders nothing. Mirror Phase 28's locked
   decision §7.
