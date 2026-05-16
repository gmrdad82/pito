# 08 — Game detail page revamp (two-pane layout, ratings heat bar,
> ownership, sync banner, drop edit page)

> Phase 27 v2 spec. Rebuilds `/games/:id` from the existing three-row
> read-only layout (cover+meta pane / sync pane / linked-videos pane) to
> a two-pane (LEFT / RIGHT) layout that consolidates ratings into a
> single 0-100 heat-bar synthesis, exposes ownership / played / recorded
> as compact chip rows, and drops the standalone `/games/:id/edit`
> route entirely. The breadcrumb's `[edit]` action becomes `[resync]`
> (per spec 03's sync mechanism) and the `[-]` icon becomes a
> per-game `[delete]` confirm modal.

---

## Goal

The detail page tells the user, at a glance: "what this game is
(left pane), what I think of it (synthesized rating), what I own /
have played / have recorded on, when it last synced, and what's
free-form about it (summary, time-to-beat, future sections — right
pane)." Every interaction surface (resync, delete) lives on the page
itself via per-game confirm-modal flows; the standalone edit page
goes away.

---

## Scope in

- Two-pane layout via the existing `.pane-row` primitive: LEFT pane
  ≈ 280 px (cover-led), RIGHT pane ≈ wide-fill. Use
  `pane-row--game-show` modifier (already exists) for nowrap.
- LEFT pane content (top to bottom):
  1. Cover (existing IGDB cover render at the show-page size).
  2. Title (`<h1>`).
  3. Genres: ONE main genre bold (per spec 01) + up to 2 secondary
     genres in normal weight. Cap at 3 visible. The "secondary"
     list = `game.genres - [game.primary_genre]`, sliced to 2.
  4. `released:` + date (MM-DD-YYYY).
  5. `dev:` + comma-joined developer names.
  6. `pub:` + comma-joined publisher names.
  7. Platform logos at 56 px (per spec 07), horizontal flex row.
  8. Hairline.
  9. **Ratings heat bar** — single synthesized 0-100 score rendered
     via new `Games::RatingHeatBarComponent`. See Behavior for
     synthesis formula and component contract.
  10. Hairline.
  11. **Ownership section** — three chip rows + footage placeholder:
      - `platforms [ ] PS5 [ ] Switch2 [ ] Steam [ ] GoG [ ] Epic`
        — bracketed chips for every platform the game is RELEASED
        ON (intersection with the 5-platform set). Owned ones render
        `[x] PS5`; not-owned render `[ ] PS5`. Labels use the
        `PLATFORM_LABELS` map from spec 06 (`Switch2` no space).
        Clicking toggles ownership (POSTs to the existing
        `Games::PlatformOwnershipsController#update`).
      - `played` — **a single `[x] played` / `[ ] played` chip**
        bound to the existing `played_at` column. NOT per-platform.
        Clicking sets / clears `played_at` on the game row.
      - `recorded` — **a single `[x] recorded` / `[ ] recorded`
        chip** bound to the existing `recorded` boolean (or
        `videos.exists?` surrogate — pin at implementation; see
        Behavior). NOT per-platform.
      - `footage` — placeholder line. Reads `footage` followed by
        the `StatusTbdBadgeComponent` rendering `[TBD]` in bright
        orange.
  12. Hairline.
  13. **Sync banner** — reads `synced ~22m ago` (the project's
      short relative-time format — see Behavior). During sync,
      replace with the `=---` dot-loader (matches Voyage reindex
      pattern per spec 03). The banner subscribes to the
      `game_resync:<id>` Turbo Stream (per spec 03).
- RIGHT pane content (top to bottom):
  1. Summary — pre-line wrapped paragraph.
  2. Hairline.
  3. **Time-to-beat** — 2-column table:
     - Column 1: row label (`main`, `extras`, `completionist`).
     - Column 2: value, right-aligned, rounded to whole hours
       (drop minutes — `9h`, `14h`, `22h`).
  4. (No reserved third column; no future-section placeholder
     beyond an implicit hairline.)
- Breadcrumb actions strip: replace `[edit]` with `[resync]` (POST
  to existing `/games/:id/resync`, muted styling while sync in
  flight). Replace `[-]` with `[delete]` opening a single-confirm
  modal via `ConfirmModalComponent`.
- **DROP the `stores` link section entirely.** No `[steam]` / `[gog]`
  / `[epic]` link list anywhere on the detail page. Store URLs are
  not surfaced. The platform logos (LEFT pane) communicate platform
  availability visually; the actionable "open in store" UX is OUT.
- **DROP the standalone edit page entirely.**
  - Routes: remove `get '/games/:id/edit'` AND `patch/put
    '/games/:id'` from `resources :games`. Use `resources :games,
    except: [:edit, :update]` (or explicit `only:`).
  - Controller: remove `#edit` and `#update` actions, the
    `local_only_params` permit method, and the `ALLOWED_SORTS` /
    sort-key wiring (sort UI is gone with the list mode in spec 05).
  - View: delete `app/views/games/edit.html.erb`.
  - The per-platform ownership editor at
    `/games/:slug/platform_ownerships/edit` STAYS — it's a
    dedicated nested resource and not the legacy edit page.
- **Per-game delete confirm modal** via `ConfirmModalComponent`.
  - The breadcrumb `[delete]` opens a modal:
    - Title: `delete <title>?`
    - Body: muted text explaining cascade (linked videos detach,
      collection composites regenerate).
    - Buttons: `[delete]` (danger-colored, POSTs DELETE to
      `/games/:id`) + `[cancel]` (`BracketedMutedLinkComponent`).
  - On delete success: `Game#destroy` cascades the existing
    `dependent: :destroy` associations and the
    `Collections::CompositeRebuildQueue.enqueue_for_game_destroy`
    hook (per spec 02) fires for every collection the game was in.
- Linked videos section heading: `linked videos` → `videos` (shorter).
- When the videos list is empty, render `videos` heading + the
  `StatusTbdBadgeComponent` inline (`[TBD]` orange) instead of the
  prose `no linked videos yet.`.

## Scope out

- **Per-platform played-on / recorded-on data model — DEFERRED
  PERMANENTLY.** The user plays AND records on ONE platform per
  game; the existing single `played_at` / single `recorded` (or
  `videos.exists?`) surrogate is the final shape for this surface.
  No `game_platform_plays` join table, no `game_platform_recordings`
  join table, no per-platform chip rows under `played` or
  `recorded`. The data model MUST NOT enable future per-platform
  tracking as an unstated affordance — it's an explicit non-goal.
- Stores section — DROPPED entirely (no store URLs surfaced).
- Multi-version "editions" section — keep as-is (Phase 28 §01a
  surface).
- Edition-parent breadcrumb pointer — keep as-is.

---

## Files to change

### Routes + controller

- `config/routes.rb` — `resources :games, except: [:edit, :update]`
  (preserve `resources :games do member { post :resync } end`).
  Confirm the `version_parent_search` route still resolves (it's a
  collection action, not member).
- `app/controllers/games_controller.rb`
  - Remove `def edit`.
  - Remove `def update`.
  - Remove `local_only_params` private method.
  - Remove `ALLOWED_SORTS`, `ALLOWED_DIRS`, `DEFAULT_SORT`,
    `DEFAULT_DIR`, `sanitized_sort_key`, `sanitized_dir`,
    `sort_clause` (list-mode sort UI is gone).
  - Update the JSON branch of `#index` to drop the `@json_sort`
    payload.

### View

- `app/views/games/edit.html.erb` — DELETE.
- `app/views/games/show.html.erb` — REWRITE per the layout above.
  - Top: breadcrumb action strip with `[resync]` (muted while
    `@game.resyncing?`) + `[delete]` (opens modal).
  - `turbo_stream_from "game_resync:#{@game.id}"` permanent
    subscription (per spec 03).
  - `<div class="pane-row pane-row--game-show">` with two children:
    `.pane.pane--game-detail-left` (≈ 280 px) and
    `.pane.pane--game-detail-right` (wide-fill).
  - Per the LEFT / RIGHT content above.
  - **NO `<h3>stores</h3>` section anywhere.** Drop the existing
    block that renders `[steam]` / `[gog]` / `[epic]` external
    link list.
  - Delete modal renders at the bottom of the view via
    `ConfirmModalComponent`.
- `app/views/games/_sync_status.html.erb` (per spec 03) — embedded
  in the LEFT pane's sync banner slot.
- `app/views/games/_videos_section.html.erb` (NEW, optional
  extraction) — renders the `videos` heading + the linked videos
  list OR the `[TBD]` badge.

### ViewComponents (NEW)

- `app/components/games/rating_heat_bar_component.rb` (NEW)
  - `initialize(igdb_rating:, igdb_votes:, aggregated_rating:,
    aggregated_votes:, total_rating:, total_votes:)`.
  - Computes the synthesized score:
    ```ruby
    numerator   = igdb_rating * igdb_votes
                + aggregated_rating * aggregated_votes
                + total_rating * total_votes
    denominator = igdb_votes + aggregated_votes + total_votes
    score       = (numerator / denominator).round
    ```
    Each rating × votes pair contributes ZERO when either side is
    nil. When `denominator == 0` → no synthesized score → muted
    bar with em-dash label.
  - Renders a horizontal bar: 100 px wide, 8 px tall, filled to
    `score%` of the width with the per-tier color from
    `Games::RatingBadgeComponent::TIERS`. Right-aligned label
    showing `<score>` (no `/100` suffix — matches the badge
    pattern).
  - When score is nil: bar renders muted (full width, low-opacity
    fill), label `—`.
  - Public API: `#score -> Integer | nil`, `#tier -> String`,
    `#color_css -> String`, `#muted? -> Boolean`.
  - Reuses the existing `--color-rating-*` CSS variables.
- `app/components/status_tbd_badge_component.rb` (NEW)
  - Renders a bracketed bright-orange `[TBD]` glyph for "this
    surface is reserved but not implemented."
  - Color: bright orange `#cc6600` (new `--color-status-tbd` CSS
    variable). Distinct from danger red `#cc0000`.
  - Slot-less — `initialize(label: "TBD")` with default.
  - Single CSS class `.status-tbd-badge` for styling.
  - **Reused by** (spec 08 owns the component definition; usage
    sites declared in their respective specs):
    - Footage placeholder row on the game detail page (this spec).
    - Videos-empty row on the game detail page (this spec).
    - Search-placeholder modal on `/games` and `/games/:id` (spec
      09 — keybindings `/` opens the placeholder modal).

### CSS

- `app/assets/tailwind/application.css`
  - Add `--color-status-tbd: #cc6600;` and
    `.status-tbd-badge { color: var(--color-status-tbd); font-weight:
    bold; }`.
  - Add `.pane--game-detail-left { flex: 0 0 280px; }` and
    `.pane--game-detail-right { flex: 1 1 auto; }` (or reuse
    existing equivalents from the current `pane-row--game-show`).
  - Add `.rating-heat-bar` styles (track + fill + label).
  - Add `.hairline` if not already a project class (it is, per
    show.html.erb usage).

### Helpers

- `app/helpers/games/time_formatting_helper.rb` (NEW, or extend an
  existing helper)
  - `ttb_hours(seconds) -> String` — rounds seconds to whole hours,
    returns `"9h"`, `"14h"`, `"22h"`, `"—"` when nil.
  - `short_synced_ago(timestamp) -> String` — pito's short
    relative-time format. Confirm there's an existing helper; if
    so, reuse. Expected output: `"22m ago"`, `"3h ago"`, `"2d ago"`,
    `"never"` when nil.

### Confirm modal wiring

- The breadcrumb `[delete]` button is wired to open the
  `ConfirmModalComponent` instance rendered at the bottom of
  show.html.erb. Wire via the existing `modal-trigger` Stimulus
  controller (the same pattern the IGDB add-game modal uses).

### Tests cleanup

- `spec/views/games/edit.html.erb_spec.rb` — DELETE.
- `spec/requests/games_spec.rb` — delete the `#edit` + `#update`
  request examples; add a regression that `GET /games/:id/edit`
  returns 404 (route gone).
- Drop any existing test that asserts the `stores` section
  rendering on the show page.

---

## Behavior contracts

### LEFT-pane sections (rendering rules)

- **Genres**: `<strong>#{primary_genre.name}</strong>`, then the
  secondary list. Wrap in a single `<p>` with `, ` separators
  between primary and secondaries. When `primary_genre` is nil,
  render `genre: —`.
- **Released**: `released: MM-DD-YYYY` when `release_date` is
  present; line omitted when blank (no `released: —`).
- **Dev / Pub**: lines omitted when the associated arrays are
  empty (no `dev: —` placeholder).
- **Platform logos**: rendered via spec 07's helper at 56 px;
  zero logos when none apply (no placeholder).
- **Ratings heat bar**:
  - Score synthesized per the formula in the component contract.
  - Bar fills to `score%`. Color is the per-tier color from
    `Games::RatingBadgeComponent`.
  - Label: `<score>` bold, right of the bar. Muted em-dash when
    `score` is nil.
- **Ownership chips**:
  - `platforms [ ] PS5 [x] Switch2 [ ] Steam [ ] GoG [ ] Epic` —
    chips for every platform in the 5-set intersected with
    `game.platforms_available`. Click toggles the ownership row.
    The click target POSTs to
    `Games::PlatformOwnershipsController#update` (existing route);
    no JS confirm. Labels use `Platform.display_label`.
  - `played [ ] played` or `played [x] played` — **single chip-or-
    blank**. Clicking toggles `played_at` on the game (sets to
    `Time.current` on check, nils on uncheck). NOT per-platform.
  - `recorded [ ] recorded` or `recorded [x] recorded` — **single
    chip-or-blank**. Clicking toggles `recorded` boolean (or
    triggers the videos-presence surrogate — pin at
    implementation). NOT per-platform.
  - `footage [TBD]` — line reads `footage` + the
    `StatusTbdBadgeComponent` rendering `[TBD]` orange. The
    placeholder is deliberate; future footage integration lands
    in a separate spec.
- **Sync banner**:
  - `synced 22m ago` (short format) when `igdb_synced_at` present.
  - `not synced yet.` when nil.
  - During sync (`@game.resyncing?` true), the `=---` dot-loader
    (per spec 03) renders in place of the time + `[resync]`
    button. The wrapping `<div id="game_sync_status_<id>">`
    matches the Turbo Stream target.

### RIGHT-pane sections

- **Summary**: `<p style="white-space: pre-line">`. When blank,
  the whole section is omitted (no heading either).
- **Time to beat**: 2-column `<table>`:
  - `<tr><td>main</td><td class="ttb-value">9h</td></tr>` etc.
  - Values right-aligned via class.
  - Rounds to whole hours. Nil → `—`.

### Breadcrumb actions

- `[resync]` POSTs to `/games/:id/resync` (existing route).
  Renders muted (via `BracketedMutedLinkComponent`) while
  `@game.resyncing?` is true.
- `[delete]` opens the confirm modal. The modal's confirm
  `<button>` POSTs DELETE to `/games/:id` (existing destroy
  action).
- The Phase 28 edition-parent pointer (`↳ <parent title>`) stays
  above the breadcrumb action strip when the game is an edition.

### Delete cascade

- `Game#destroy` (existing) cascades:
  - `game_genres` (dependent: :destroy)
  - `game_platform_ownerships` (dependent: :destroy)
  - `game_platforms`, `game_developers`, `game_publishers`,
    `bundle_members`, `video_game_links` (dependent: :destroy)
  - `calendar_entries` (dependent: :destroy)
  - `footages` (dependent: :nullify) — footage rows survive
    with `game_id` nil.
- The model's `after_destroy_commit` hook (per spec 02) fires
  `Collections::CompositeRebuildQueue.enqueue_for_game_destroy(
  self, was_in: <pre-destroy collections>)`.

### "videos" section (renamed from "linked videos")

- Heading: `videos`.
- When `@game.video_game_links.exists?`: render the existing
  `<ul>` of links.
- When empty: render `videos` heading + `StatusTbdBadgeComponent`
  (`[TBD]` orange) inline. NOT the prose `no linked videos yet.`.

### Stores section — REMOVED

- The previous `<h3>stores</h3>` block with `[steam]` / `[gog]` /
  `[epic]` external link list is DELETED from the view. No
  replacement. The LEFT-pane platform logos communicate platform
  availability; store URLs are not exposed.

### Rating heat-bar synthesis (LOCKED formula)

- See the component contract above. The vote-weighted average
  rationale: a 100-rating with 5 votes should NOT dominate a
  70-rating with 5000 votes; the synthesis weighs by vote count.
- Rounded to integer. No decimal display.
- Per-tier color from `Games::RatingBadgeComponent::TIERS`.

### `StatusTbdBadgeComponent` — cross-cutting placeholder

- Defined here (spec 08 introduces it).
- Used by:
  - Detail page footage row (this spec).
  - Detail page empty-videos row (this spec).
  - Search-placeholder modal opened by `/` keybinding (spec 09).
- Color `#cc6600` (bright orange). Distinct from danger red.
- Bracketed glyph `[TBD]`. Optional `label:` override (default
  `"TBD"`).

---

## Migrations

None. The existing `games.resyncing` Boolean (per spec 03) +
`games.played_at` + `games.recorded` (if present) + ownership
join cover the v2 surface. **No new per-platform columns or
join tables**; the data model is explicitly NOT extended to
support per-platform played-on / recorded-on tracking.

---

## ViewComponents

- `Games::RatingHeatBarComponent` (NEW).
- `StatusTbdBadgeComponent` (NEW) — defined here, used here +
  in spec 09 (search-placeholder modal).

---

## Stimulus controllers

- `modal-trigger` (existing) — reused for the delete modal open.
- No new controllers.

---

## Spec coverage required

### Component specs

- `spec/components/games/rating_heat_bar_component_spec.rb`
  - Score synthesis: vote-weighted average rounded to integer.
  - All three rating sources nil → `#score` returns nil,
    `#muted?` true.
  - One source nil + others present → that source contributes
    zero to numerator AND zero to denominator.
  - All votes zero (but ratings present) → muted (denominator
    zero).
  - Score 95 → `#tier` returns `"excellent"`, color from CSS var.
  - Score 0 → `#tier` returns `"bad"`.
  - Rendered output contains the bar fill width and the
    integer label.
- `spec/components/status_tbd_badge_component_spec.rb`
  - Renders `[TBD]` (default label) with the orange class.
  - Custom label arg works.
  - No `<a>` tag (badge is non-interactive).
  - The rendered HTML applies the `.status-tbd-badge` class so
    CSS color `#cc6600` lands.

### View specs (`spec/views/games/show.html.erb_spec.rb`)

Extend the existing file:

- LEFT pane renders: cover, title, genres (primary bold + up to
  2 secondaries), released/dev/pub lines, platform logos
  (per spec 07), hairline, rating heat bar, hairline,
  ownership chips (single `played` chip, single `recorded`
  chip, NOT per-platform), `footage [TBD]` row, hairline, sync
  banner.
- RIGHT pane renders: summary (when present), hairline, ttb
  2-column table (rounded hours).
- Breadcrumb action strip: `[resync]` + `[delete]`, no `[edit]`.
- Delete modal is rendered in the DOM (collapsed by default).
- Videos section heading reads `videos` (singular shortening).
- Empty videos → `videos` heading + `[TBD]` badge, NOT the
  prose `no linked videos yet.`.
- **NO `stores` section rendered.** Regression assert: page
  contains no `<h3>stores</h3>` and no anchor with
  `href="https://store.steampowered.com/..."` or equivalent
  GOG / Epic URLs.
- No `data-turbo-confirm`, no `window.confirm`, no `<form
  method="post" action="/games/:id" data-method="delete">`
  inline outside the confirm modal.

### Request specs

- `GET /games/:id/edit` → 404 (route gone).
- `PATCH /games/:id` → 404 (route gone).
- `DELETE /games/:id` (the modal's confirm POST) → destroys,
  redirects to `/games`, flash `game deleted.`.
- `POST /games/:id/resync` → unchanged from spec 03; verify the
  show page re-renders with the muted `[resync]` link.

### System spec (`spec/system/games_show_revamp_spec.rb`, NEW)

- ONE end-to-end scenario:
  1. Seed a game with cover, primary genre, secondary genres,
     ratings, ownership rows.
  2. `visit game_path(game)`.
  3. Assert the two-pane layout structure.
  4. Assert NO stores section.
  5. Assert single `played` chip + single `recorded` chip (no
     per-platform breakdown).
  6. Assert `footage [TBD]` row present.
  7. Click `[delete]` → modal opens (no JS confirm fired).
  8. Click `[cancel]` in the modal → modal closes, page
     unchanged.
  9. Re-open modal, click `[delete]` → game destroyed, redirect
     to `/games`, flash visible.

### Helper specs

- `ttb_hours(0)` → `"0h"`.
- `ttb_hours(3600)` → `"1h"`.
- `ttb_hours(3599)` → `"1h"` (round to nearest hour) OR `"0h"`
  (floor — pick rule; architect lean: round).
- `ttb_hours(nil)` → `"—"`.
- `short_synced_ago(22.minutes.ago)` → `"22m ago"`.
- `short_synced_ago(nil)` → `"never"`.

---

## Manual test recipe

1. `bin/dev` → open `http://localhost:3000/games/<slug>`.
2. Confirm two-pane layout (LEFT cover-led, RIGHT summary-led).
3. LEFT pane: cover renders; title; bold primary genre + up to
   2 secondary genres normal weight; release / dev / pub lines
   present; 56 px platform logos for applicable platforms;
   hairline; rating heat-bar fills proportionally and shows
   integer score; hairline; ownership chips (single `played`
   chip, single `recorded` chip, NOT per-platform); `footage
   [TBD]` row with orange badge; hairline; sync banner.
4. RIGHT pane: summary (if any); hairline; time-to-beat 2-column
   table in whole hours.
5. **Confirm NO `stores` section anywhere on the page.** No
   `[steam]` / `[gog]` / `[epic]` link list. The platform logos
   are decorative.
6. Breadcrumb actions show `[resync]` + `[delete]`.
7. Click `[resync]` → muted style flips on; `=---` dot-loader
   replaces the sync banner; live ActionCable broadcast (per
   spec 03) flips back to `synced just now` when the job ends.
8. Click `[delete]` → confirm modal appears; `[delete]` button
   in danger color; `[cancel]` muted. Click `[cancel]` → modal
   closes. Click `[delete]` → game destroyed, redirect to
   `/games`, flash visible. (Verify in DB that any collection
   the game was in had its cover regen enqueued per spec 02.)
9. `GET /games/<slug>/edit` → 404. `GET /games/<slug>` →
   200 (show still works).
10. Linked videos: when empty → `videos` heading + orange
    `[TBD]` badge inline. When non-empty → `videos` heading +
    the list.

---

## Open questions

1. **`recorded` chip data source — boolean column vs
   `videos.exists?` surrogate.** The model may already carry a
   `recorded` boolean from earlier work; if not, `videos.exists?`
   is the surrogate. Pin at implementation; preferred:
   `recorded` boolean if it exists, surrogate otherwise. Either
   way, ONE chip, not per-platform.
2. **Rating heat-bar — color the fill OR the label OR both?**
   Architect lean: fill colored per tier, label bold black /
   white per theme (not colored), to keep the text readable
   against the colored bar in both themes.
3. **`videos` section — drop the heading entirely when empty?**
   Architect lean: keep the heading + render the `[TBD]` badge
   inline so the user knows the slot exists.
4. **Edition-parent pointer + breadcrumb action strip — do they
   stack vertically as today, or merge into one line?** Keep
   stacked (cleaner separation between "navigate up" and "do
   something to this row").
