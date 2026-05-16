# 01e — Video LINKS Section Polish

> Parent: `docs/plans/beta/11-video-workflow-features/plan.md`.
> Parallel-dispatchable with `01c` and `01d` once `01a` lands.

---

## Goal

`video_links` already exists in the schema (alpha-era surface) but has no
first-class UI. The edit page does not expose it; the show page does not render
it. Phase 11 lifts the table into a workflow-grade surface:

- A `kind` enum (`related_video`, `related_channel`, `external_resource`,
  `sponsor`) — added by migration if not already present.
- A first-class nested-form editor in the video edit pane (the same
  `nested_form` Stimulus controller used in `01a` for chapters / end-screens).
- A grouped display on the video show page below the description: one heading
  per `kind` (sections with zero rows are skipped).

---

## Files touched

### Migrations

- `db/migrate/<TS>_audit_and_extend_video_links.rb` — audit step. If
  `video_links.kind` is missing, add as integer enum-backed column (default `0`
  → `related_video`, NOT NULL). If `video_links.position` is missing, add as
  integer (default `0`). If `video_links.label` is missing, add as string. The
  audit is idempotent —
  `add_column :video_links, :kind, :integer, default: 0, null: false unless column_exists?(:video_links, :kind)`
  etc.

### Models

- `app/models/video_link.rb` (audit existing; new if absent) — enum
  `kind: { related_video: 0, related_channel: 1, external_resource: 2, sponsor: 3 }`,
  `prefix: :kind`. Validations:
  `url presence + format matching %r{\Ahttps?://}`, `label length <= 100`,
  `kind presence`. Scope by kind:
  `scope :related_videos, -> { kind_related_video }` etc.
- `app/models/video.rb` —
  `has_many :video_links, -> { order(:kind, :position) }, dependent: :destroy`,
  `accepts_nested_attributes_for :video_links, allow_destroy: true, reject_if: :all_blank`.

### Factories

- `spec/factories/video_links.rb` (audit existing; new traits per kind).

### Controllers

- `app/controllers/videos_controller.rb` — extend `video_params` to permit
  `video_links_attributes: [:id, :_destroy, :kind, :url, :label, :position]`.

### Views

- `app/views/videos/_edit_links.html.erb` (new) — sub-section in the edit pane.
  Stack rows by `kind`; `[add link]` link adds a new row with a kind dropdown.
- `app/views/video_links/_fields.html.erb` (new) — single nested-form row
  partial.
- `app/views/videos/_show_links.html.erb` (new) — grouped display below the
  description on the video show page. One heading per kind (skip empty kinds).
  Each link renders as a bracketed `[label]` link.
- `app/views/videos/show.html.erb` — include the new partial below the
  description.

### Routes

- `config/routes.rb` — no new routes. Edit + update ride the existing
  `PATCH /videos/:youtube_video_id`.

### Specs

- `spec/models/video_link_spec.rb` (new — or extend existing if a legacy file
  exists). Validations, enum, scopes by kind.
- `spec/factories/video_links_spec.rb` — factory smoke.
- `spec/requests/videos_spec.rb` — extend `edit` + `update` to cover the new
  nested-form attributes.
- `spec/views/videos/_edit_links.html.erb_spec.rb` (new).
- `spec/views/videos/_show_links.html.erb_spec.rb` (new).
- `spec/system/video_links_section_spec.rb` (new) — system spec: add a link of
  each kind via the form, observe the four-section grouped display on the show
  page, remove a link.

---

## Acceptance

- [ ] Migration audit lands the four-value `kind` enum on `video_links` if not
      already present. Re-runs are no-ops.
- [ ] `VideoLink#kind` returns the symbolic value (`:related_video`,
      `:related_channel`, `:external_resource`, `:sponsor`).
- [ ] `VideoLink#url` validated as `https?://...`.
- [ ] `VideoLink#label` length validated `<= 100`.
- [ ] `VideoLink#kind` validated as present.
- [ ] Scope `Video.video_links.related_videos` returns rows with
      `kind: :related_video`. Same shape for the other three kinds.
- [ ] `Video#video_links_attributes=` accepts a nested-attributes payload via
      `accepts_nested_attributes_for`.
- [ ] Edit pane sub-section renders one row per existing link, grouped by kind,
      ordered by `position`.
- [ ] `[add link]` adds a new row with a kind dropdown; submit persists.
- [ ] `[remove]` on a row sets `_destroy: 1`, hides the row; submit deletes.
- [ ] Show page renders the grouped display below the description.
- [ ] Show page skips kind sections that have zero rows.
- [ ] Yes/no boundary placeholder — no Boolean external inputs in v1; reserved
      guard documented inline.
- [ ] Friendly URL preserved on the edit + show routes.
- [ ] `bundle exec rspec` green on every new + extended spec file.

---

## Manual test recipe

1. `bin/rails db:migrate` (audit migration; no-op if `kind` already exists).
2. `bin/dev` → visit `http://localhost:3000/videos/<some_yt_id>/edit`.
3. Scroll to the new "Links" sub-section.
4. Click `[add link]`; choose `related_video` from the kind dropdown; enter
   `url = https://youtube.com/watch?v=abc123`, `label = Watch next`. Submit.
5. Click `[add link]` again; choose `sponsor`; enter
   `url = https://sponsor.example.com`, `label = Buy the thing`. Submit.
6. Reload the edit page; confirm both links render in their groups.
7. Visit the video show page; scroll below the description; confirm the grouped
   display shows:
   - **Related videos** heading with the `[Watch next]` link.
   - **Sponsors** heading with the `[Buy the thing]` link.
   - The other two kind headings (`Related channels`, `External resources`) are
     NOT rendered (zero rows).
8. Edit the video; click `[remove]` on the sponsor row; submit. Reload the show
   page; the **Sponsors** heading is gone.
9. **Validation — URL.** Add a link with `url = not a url`. Submit. Observe the
   validation error inline.
10. **Validation — label length.** Add a link with a 200-char label. Submit.
    Observe the validation error inline.
11. `bundle exec rspec` — green.

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

1. **`video_links` legacy schema.** The table predates Phase 11 (alpha-era). The
   implementation agent must audit the live schema before writing the migration
   — `kind`, `label`, `position` may already exist with different semantics. If
   they exist, this sub-spec collapses to "wire up the UI"; if not, the
   migration lands the new columns.
2. **Sponsor link special-casing.** Should the show-page sponsor section carry a
   "disclosure" prefix line per FTC guidance? Architect leans yes for v2; out of
   scope for v1. Surface for user lock.
3. **External URL safety.** Should the show-page render external links with
   `rel="noopener noreferrer"`? Architect leans yes; bake into the show partial.
4. **Per-kind ordering vs flat position.** Today's spec orders by
   `(kind, position)` so links within a kind respect their position; kinds
   themselves render in enum order. If the user wants a global `position` across
   all kinds, the implementation agent can flip the order; surface for user lock
   before dispatch.
