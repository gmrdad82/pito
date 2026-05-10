# Phase 15 §2 — Calendar Views (Month Grid + Schedule)

> **Status:** dispatched 2026-05-10. Single primary lane: **rails**. Builds on
> top of `01-calendar-data-model.md`. MCP tool surface (work unit 9) and Rust
> CLI parity (work unit 10) are deferred.
>
> **Cross-references:**
>
> - `docs/realignment-2026-05-09.md` — work unit 7. Resolved ambiguity #5
>   ("month grid + Schedule view, Google Calendar style; day / week deferred").
> - `docs/notes/2026-05-09-19-14-10-calendar-and-notifications.md` — Mobile
>   note 5. §"Calendar views" lists the reads we expect the UI to need.
> - `docs/plans/beta/15-calendar/specs/01-calendar-data-model.md` — Phase 15 §1.
>   Models + scopes + validators this spec consumes.
> - `docs/design.md` — design system. Lowercase, monospace 13px, bracketed link
>   convention, `cursor: pointer` on every clickable, no animation, no red
>   except destructive.
> - `CLAUDE.md` — hard rules: no `confirm()` / `alert()` / `prompt()` / no
>   `data-turbo-confirm`; bulk-as-foundation URL pattern
>   (`/<action>s/:type/:ids`); `yes` / `no` for external booleans; destructive /
>   significant actions go through the action confirmation page framework
>   (`shared/_action_screen.html.erb` + `DeletionsController` /
>   `SyncsController` + `Confirmable` concern).

## Goal

Ship a Google-Calendar-style month grid and a Schedule view (linear chrono list)
for the calendar entries created in §1. Wire navigation between months / years
(with a "today" anchor); render derived / auto / manual entries with
type-distinct styling; add a quick-add manual entry form; edit + delete via the
action confirmation page framework. No day or week view (deferred per
realignment ambiguity #5). Lowercase, monospace, bracketed-link convention
throughout per `docs/design.md`.

This is realignment work unit 7's UI tier. Built on §1's models + scopes.

## Resolved design decisions (LOCKED — do not re-litigate)

| Q   | Decision                                                                                                                                                                                                                                                                                                                                                                                                            |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | **Two views only.** Month grid + Schedule. NO day, NO week, NO year view. Per realignment ambiguity #5.                                                                                                                                                                                                                                                                                                             |
| Q2  | **URL shape.** `/calendar` redirects to `/calendar/month/<this_year>/<this_month>` (the install's local-tz "now"). `/calendar/month/:year/:month` is the canonical month-grid URL. `/calendar/schedule` is the schedule view (no params; renders an infinite-scroll-style window centered on today, see Q9 for pagination).                                                                                         |
| Q3  | **Empty state.** Both views show a stable empty-state copy + a `[ add entry ]` link. The month grid still renders the grid (cells are visible, just no event chips); the schedule view renders a single "no entries" line above the `[ add entry ]` link.                                                                                                                                                           |
| Q4  | **Quick-add form shape.** A manual entry form rendered at `/calendar/entries/new`. Renders inline as a Turbo Frame (`turbo-frame target="quick_add"` on month / schedule pages) so the user doesn't lose their place. Also reachable as a full page for direct linking. Per `docs/design.md` lowercase + bracketed labels.                                                                                          |
| Q5  | **Edit / delete UX.** Both go through the action-screen framework (`/deletions/calendar_entry/:ids` + `/calendar/entries/:id/edit`). The edit form is the same partial as quick-add, pre-filled. Delete + cancel both route through the confirmation screen. Read-only (`derived` / `auto`) entries do NOT render the `[ edit ]` / `[ delete ]` links — only `[ note ]` for adding `metadata.user_overrides`.       |
| Q6  | **Type-distinct styling.** Each `entry_type` gets a one-character glyph prefix:                                                                                                                                                                                                                                                                                                                                     |
|     | - `channel_published` → `c:`                                                                                                                                                                                                                                                                                                                                                                                        |
|     | - `video_published` → `v:`                                                                                                                                                                                                                                                                                                                                                                                          |
|     | - `video_scheduled` → `v?:`                                                                                                                                                                                                                                                                                                                                                                                         |
|     | - `game_release` → `g:`                                                                                                                                                                                                                                                                                                                                                                                             |
|     | - `purchase_planned` → `$:`                                                                                                                                                                                                                                                                                                                                                                                         |
|     | - `milestone_manual` → `m:`                                                                                                                                                                                                                                                                                                                                                                                         |
|     | - `milestone_auto` → `m*:`                                                                                                                                                                                                                                                                                                                                                                                          |
|     | - `custom` → `~:`                                                                                                                                                                                                                                                                                                                                                                                                   |
|     | NO red. NO color-coding by type (per `docs/design.md` "no decorative red"). State distinction (`scheduled` / `occurred` / `cancelled` / `superseded`) is handled with text style: scheduled is normal weight; occurred is muted; cancelled is strike-through; superseded is muted + strike-through.                                                                                                                 |
| Q7  | **Today highlight.** The current day cell on the month grid carries a class `today` that renders a 1px border (per `docs/design.md` `--color-border` token). NO color flood. Schedule view: a `[ today ]` divider line splits past from future entries.                                                                                                                                                             |
| Q8  | **Navigation controls.** Month grid: `[ prev month ]` / `[ today ]` / `[ next month ]` at the top (left-aligned cluster). Year jump: `[ <year> ]` inline link opens a year picker (12 month-link cluster). NO calendar widget popup — keep it a flat link grid per `docs/design.md`.                                                                                                                                |
| Q9  | **Schedule view pagination.** 50 entries per page, ordered by `starts_at` ascending. `[ next page ]` / `[ prev page ]` at the bottom (bracketed-link convention). NO infinite scroll. The `[ today ]` divider lands on whichever page contains today; the default page is the one with today. URL: `?page=N` or `?after=<iso8601>` for cursor-style. Architect picks `?page=N` for v1; cursor-style is a follow-up. |
| Q10 | **Filters.** Schedule view supports `?type=<entry_type>` (single value) and `?source=<manual\|derived\|auto>` (single value). Month grid: filter cluster at top of page (`[ all types ]` / `[ video ]` / `[ game ]` / `[ milestone ]` / `[ purchase ]` / `[ custom ]`) — clicking re-renders with the filter applied. NO multi-select in v1.                                                                        |
| Q11 | **Multi-day rendering.** Multi-day entries (`ends_at` non-null) render as a continuous bar across grid cells in the month view. The bar carries the title on the leftmost visible cell only; subsequent cells render `↳` (continuation). Per `docs/design.md` monospace lowercase. Schedule view renders multi-day entries with the date range (`mar 14 — mar 21`).                                                 |
| Q12 | **All-day vs. timed display.** All-day entries show no time. Timed entries show `HH:MM` in the install tz (converted from UTC via the entry's `timezone` column). Per Q6, the prefix glyph is unchanged.                                                                                                                                                                                                            |
| Q13 | **Cross-link to source.** Derived entries link their title to the source row: `video_published` → `/videos/:id`; `channel_published` → `/channels/:id`; `game_release` → `/games/:id`; `milestone_auto` → a future milestone-rule detail page (Phase 16); for v1, link to `#` + a `title="rule: <name>"` tooltip.                                                                                                   |
| Q14 | **`purchase_planned` linkage.** The `purchase_planned` chip on the month grid shows the storefront name (e.g., `$: Steam`). Clicking opens the entry detail (`/calendar/entries/:id`) which shows the parent `game_release` link prominently.                                                                                                                                                                       |
| Q15 | **Test posture.** Exhaustive per the brief.                                                                                                                                                                                                                                                                                                                                                                         |

## Migration posture (LOCKED)

**No schema changes.** This spec is purely UI / controller / route work on top
of §1's models. If the implementation agent finds a missing column or constraint
that §1 should have shipped, STOP and surface — do not patch the schema in this
spec.

## Files touched

### Routes

- `config/routes.rb` (light edit) — add the calendar surface inside the existing
  `Rails.application.routes.draw` block. Sketch:

  ```ruby
  get "/calendar",
      to: redirect { |_p, req|
        now = Time.current
        "/calendar/month/#{now.year}/#{now.month}"
      },
      as: :calendar_root
  get "/calendar/month/:year/:month",
      to: "calendar/month#show",
      as: :calendar_month,
      constraints: { year: /\d{4}/, month: /\d{1,2}/ }
  get "/calendar/schedule",
      to: "calendar/schedule#show",
      as: :calendar_schedule
  scope "/calendar" do
    resources :entries,
              controller: "calendar/entries",
              only: %i[new create show edit update] do
      collection do
        # Quick-add Turbo Frame target (renders inline form
        # without leaving the month / schedule view).
        get :quick_add
      end
    end
  end
  ```

  Delete via the existing `/deletions/:type/:ids` framework with type
  `calendar_entry`. Cancel (state flip to `:cancelled`) goes through the same
  framework with a different action — the existing `DeletionsController` is
  per-type-dispatched; the implementation agent extends `DeletionsController` to
  handle a `?soft=cancel` flag for `calendar_entry`, OR adds a sibling
  `cancellations` namespace. Architect's lean: **extend `DeletionsController`**
  with a `cancel_calendar_entry` member that flips `state` to `:cancelled`
  rather than deleting. See Open questions #1.

### Controllers

- `app/controllers/calendar/month_controller.rb` (new) — `show` action. Loads
  `CalendarEntry.in_range(month_start, month_end)` (with state filter on
  `:cancelled` excluded by default — see Open questions #2). Builds the 6×7 grid
  (or 5×7 if the month fits) of `Date` objects. Buckets entries per day. Renders
  `app/views/calendar/month/show.html.erb`.

- `app/controllers/calendar/schedule_controller.rb` (new) — `show` action. Loads
  `CalendarEntry.order(:starts_at).limit(50).offset((page-1)*50)`, filtered by
  `?type=` and `?source=`. Default page is the one containing today (compute on
  first hit; redirect to that page if no `page=` param). Renders
  `app/views/calendar/schedule/show.html.erb`.

- `app/controllers/calendar/entries_controller.rb` (new) — `new`, `create`,
  `show`, `edit`, `update`, `quick_add`. Strong params: `entry_type` (string,
  restricted to `manual` types: `game_release`, `purchase_planned`,
  `milestone_manual`, `custom` — derived / auto types are NOT user-creatable),
  `title`, `description`, `starts_at`, `ends_at`, `all_day` (yes/no),
  `timezone`, `metadata` (jsonb sub-keys per type), `parent_entry_id` (for
  `purchase_planned`), `game_id` (for `game_release` / `purchase_planned` denorm
  pointer), `project_id`. Read-only enforcement: `edit` / `update` redirect with
  flash if the entry is `derived` or `auto` (the `read_only?` predicate from
  §1).

- `app/controllers/deletions_controller.rb` (light edit) — extend the per-type
  dispatcher to handle `calendar_entry`. Soft-delete semantics:
  `DELETE /deletions/calendar_entry/:ids` flips `state` to `:cancelled` rather
  than `destroy`. The existing action-screen copy ("permanently delete?") needs
  a per-type override — see copy questions #4.

### Views (ERB)

- `app/views/calendar/month/show.html.erb` (new) — the month grid. See §"View:
  month grid" for the structure.
- `app/views/calendar/month/_grid.html.erb` (new) — the actual 7-column grid
  markup.
- `app/views/calendar/month/_cell.html.erb` (new) — a single day cell with its
  event chips.
- `app/views/calendar/month/_navigation.html.erb` (new) — the prev / today /
  next cluster + the year-jump link cluster.
- `app/views/calendar/month/_filter_cluster.html.erb` (new) — the type filter
  row.
- `app/views/calendar/schedule/show.html.erb` (new) — the linear list view.
- `app/views/calendar/schedule/_entry.html.erb` (new) — a single entry row.
- `app/views/calendar/schedule/_pagination.html.erb` (new).
- `app/views/calendar/entries/new.html.erb` (new) — full-page quick-add form.
- `app/views/calendar/entries/edit.html.erb` (new).
- `app/views/calendar/entries/show.html.erb` (new) — entry detail (links,
  parent_entry link for purchase_planned, milestone rule link for
  milestone_auto, child entries for game_release).
- `app/views/calendar/entries/_form.html.erb` (new) — the form partial used by
  both `new` and `edit`.
- `app/views/calendar/entries/_chip.html.erb` (new) — the event chip rendered
  inside month-grid cells. Renders the prefix glyph
  - truncated title + state styling.
- `app/views/calendar/_quick_add_frame.html.erb` (new) — Turbo Frame target
  rendered on month + schedule shell so the `[ add entry ]` link can swap in the
  inline form.

### Stimulus controllers

- `app/javascript/controllers/calendar_navigation_controller.js` (new) —
  keyboard shortcuts for `[` (prev month) / `]` (next month) / `t` (today) ON
  the month grid view. NO `confirm()` / `alert()` / `prompt()` per CLAUDE.md
  hard rule. The `?` shortcuts modal (Phase 7.5 spec 04, queued) will pick up
  these bindings later.
- `app/javascript/controllers/calendar_filter_controller.js` (new) — applies the
  `?type=` filter via Turbo navigation.
- `app/javascript/controllers/calendar_entry_form_controller.js` (new) — toggles
  per-type metadata sub-form (e.g., when the user picks
  `entry_type=purchase_planned`, surface storefront + parent_entry picker; when
  they pick `game_release`, surface release_precision + manual_date_override).
  NO `confirm()`. The `unsaved-form` controller (existing) is composed in for
  the `beforeunload` guard per CLAUDE.md exception.
- `app/javascript/controllers/index.js` (light edit) — register the three new
  controllers.

### Helpers

- `app/helpers/calendar_helper.rb` (new) — small helpers:
  - `month_grid_dates(year, month)` returns the 6×7 (or 5×7) array of dates for
    the grid, leading with the previous-month tail needed to align Monday-first.
  - `entry_chip_glyph(entry)` returns the prefix per Q6.
  - `entry_chip_class(entry)` returns the state class (`scheduled` / `occurred`
    / `cancelled` / `superseded`).
  - `entry_time_label(entry)` returns the time portion (or "" for all-day) in
    the install tz.
  - `entry_date_label(entry)` returns the date portion in lowercase monospace
    form (e.g., `mar 14`).
  - `entry_link_target(entry)` returns the cross-link URL per Q13.

### Components (ViewComponent — preferred per `MEMORY.md`)

The implementation agent picks ERB partials OR ViewComponents for the chip +
entry list row. The user's stored preference (per `MEMORY.md`) leans
ViewComponent for HTML. Architect's lean: **ViewComponent for
`EntryChipComponent` and `EntryRowComponent`**; ERB partials for the bigger view
templates (month grid, schedule). See Open questions #5.

### Action-screen integration

- `app/views/deletions/_calendar_entry.html.erb` (new) — type-specific partial
  rendered by `DeletionsController#show` when
  `params[:type] == "calendar_entry"`. Lists the entries about to be cancelled
  (NOT deleted; soft-cancel semantics per Q5). The existing
  `_action_screen.html.erb` shell composes this in.
- `app/controllers/concerns/confirmable.rb` (light edit, possibly none) — verify
  it routes `calendar_entry` correctly. The per-type registration table needs an
  entry for `calendar_entry` → `CalendarEntry`. The implementation agent
  surfaces the current registration shape in §"Files touched (verify)".

### Locale / copy

- `config/locales/en.yml` (light edit) — add the calendar copy strings
  enumerated in §"Copy questions". Lowercase per `docs/design.md`.

### Out of scope (this spec)

- Day / week / year view (deferred per realignment ambiguity #5).
- Notifications integration (Phase 16; this view DOES read
  `Calendar::NotificationDispatchDeclaration` for surfacing "will remind: T-7,
  T-1, T-0" inline copy on `game_release` entries — the read is one-way, no
  insert).
- Recurrence picker UI (deferred per §1 Q9).
- iCal subscribe-to feed (deferred).
- MCP tools (work unit 9).
- CLI parity (work unit 10).
- Drag-to-reschedule on the month grid (deferred follow-up; the v1 surface is
  form-based edits only).
- Bulk-select on the schedule view (deferred follow-up).
- Saved filters / saved views integration (the `SavedView` model exists from
  Phase 4 but isn't extended for `calendar` kind here).

## View: month grid

```
[ prev month ]   [ today ]   [ next month ]      mar 2026     [ year ]   [ schedule ]   [ add entry ]

[ all types ] [ video ] [ game ] [ milestone ] [ purchase ] [ custom ]

mon              tue              wed              thu              fri              sat              sun
─────────────────────────────────────────────────────────────────────────────────────────────────────────
                                                                                                  1
                                                                                                  v: how to ...
2                3                4                5                6                7             8
g: celeste       v?: video x      m: anniversary                    v: weekly...
                                                                    v: bonus
9                10               11               12               13               14            15
                                                                                     today
                                                                                     ─────
─────────────────────────────────────────────────────────────────────────────────────────────────────────
```

- Monday-first week. (Architect picks based on Europe/Madrid default install tz;
  user can override via Open question #6.)
- Each cell has a max-height; if more than N entries on a day, the Nth chip
  becomes `[ +<count> more ]` linking to the schedule view filtered to that
  day's range.
- Today's cell carries a 1px solid `--color-border` outline.
- Month name + year render lowercase (`mar 2026`).
- The header row (`mon tue wed thu fri sat sun`) uses lowercase.
- `[ schedule ]` link routes to `/calendar/schedule`.
- `[ add entry ]` opens the Turbo Frame quick-add form below the navigation
  cluster (see `_quick_add_frame.html.erb`).

## View: schedule

```
[ month ]   [ today ]                                                                  [ add entry ]

[ all types ] [ video ] [ game ] [ milestone ] [ purchase ] [ custom ]

mar 6 thu     09:00     v: weekly devlog                                              published
mar 7 fri     —         v: bonus stream                                               published
mar 14 sat    —         m: 100k subs party                                            scheduled

────────  today  ─────────────────────────────────────────────────────────────────────────────────

mar 18 wed    —         g: celeste                                                    scheduled  [ remind: t-7 t-1 t-0 ]
mar 25 wed    —         g: hollow knight: silksong                                    scheduled
                          $: preorder @ steam — 39.99 EUR                             scheduled
apr 12 sun    18:00     v?: behind the scenes                                         scheduled
apr 14 tue    —         m*: 50k subs reached                                          occurred

[ prev page ]  page 2 / 4  [ next page ]
```

- Date column uses lowercase monospace `mar 14 sat` form.
- Time column shows `HH:MM` for timed entries, `—` for all-day.
- Title column carries the prefix glyph from Q6.
- State column shows the lowercase enum value with the styling per Q6 (occurred
  → muted; cancelled → strike-through; superseded → both).
- For `purchase_planned` entries, the row renders below its parent
  `game_release` indented with `  $:` per the markup above.
- For `game_release` entries, the inline `[ remind: t-7 t-1 t-0 ]` copy is
  rendered when the dispatch declaration returns pre-release reminders (Q13 link
  to §1 `Calendar::NotificationDispatchDeclaration`).

## View: quick-add form

```
[ x ] cancel

  type        ( manual milestone | game release | purchase planned | custom )
  title       [____________________________________________________________]
  starts at   [ yyyy-mm-dd ]   time [ hh:mm ]   timezone [ Europe/Madrid    ]
  all day     ( yes | no )
  ends at     [ yyyy-mm-dd ]   (optional)
  ...

  [ save ]   [ cancel ]
```

- The `type` radio cluster reveals/hides per-type sub-forms via the
  `calendar_entry_form_controller` Stimulus controller.
- For `game_release`: extra fields `release precision`, `manual date override`,
  `tba remind monthly` (yes/no), `game` (autocomplete pointing at existing
  `Game` rows; nullable for pre-IGDB).
- For `purchase_planned`: extra fields `parent entry` (autocomplete pointing at
  existing `game_release` entries), `purchase kind`, `storefront`,
  `storefront name`, `storefront url`, `amount`, `currency`, `ordered at`,
  `confirmation ref`, `notify anyway` (yes/no).
- For `milestone_manual`: just `description`.
- For `custom`: `description` + free-form `tags` (comma-separated).
- Yes/no radios use `"yes"` / `"no"` strings per CLAUDE.md hard rule. Internal
  storage stays Boolean.

## Files touched (verify; no edit unless surfaced)

- `app/controllers/concerns/confirmable.rb` — verify it routes `calendar_entry`
  correctly through the `Confirmable` per-type table. If the table is closed,
  the implementation agent extends it; the spec authorizes the extension.
- `app/views/shared/_action_screen.html.erb` — verify the partial resolution
  path includes `calendar_entry`. If not, add the per-type partial under
  `app/views/deletions/`.

## Test sweep

The implementation agent owns the full sweep. Each spec name below MUST end up
in the repo on green.

- `spec/factories/calendar_entries.rb` (uses §1 traits).
- `spec/requests/calendar/month_spec.rb` (new) — month grid request specs.
- `spec/requests/calendar/schedule_spec.rb` (new) — schedule request specs.
- `spec/requests/calendar/entries_spec.rb` (new) — entries CRUD request specs.
- `spec/requests/deletions/calendar_entry_spec.rb` (new) — soft-cancel flow.
- `spec/system/calendar_month_navigation_spec.rb` (new — Capybara) — prev /
  today / next month flows.
- `spec/system/calendar_quick_add_spec.rb` (new — Capybara) — inline Turbo Frame
  quick-add flow.
- `spec/system/calendar_schedule_filter_spec.rb` (new — Capybara) — type /
  source filter flows.
- `spec/system/calendar_edit_delete_spec.rb` (new — Capybara) — edit +
  soft-cancel flow through the action screen.
- `spec/components/entry_chip_component_spec.rb` (new — if ViewComponent
  picked).
- `spec/components/entry_row_component_spec.rb` (new — same).
- `spec/helpers/calendar_helper_spec.rb` (new).
- `spec/javascript/controllers/calendar_navigation_controller_spec.js` (new, OR
  Capybara coverage in the system spec — implementation agent picks).
- `spec/javascript/controllers/calendar_filter_controller_spec.js` (new, OR
  Capybara).
- `spec/javascript/controllers/calendar_entry_form_controller_spec.js` (new, OR
  Capybara).

### Required test cases (exhaustive)

#### `spec/requests/calendar/month_spec.rb`

- **GET /calendar** redirects to `/calendar/month/<this_year>/<this_month>`
  (compute via `Time.current.in_time_zone(install_tz)`).
- **GET /calendar/month/2026/05 (happy)** renders 200; contains the month name
  `may 2026`; contains 7 weekday headers; contains the prev / today / next
  cluster.
- **GET /calendar/month/2026/13 (sad — invalid month)** redirects to `/calendar`
  with flash alert.
- **GET /calendar/month/abcd/05 (sad — non-numeric year)** routes return 404
  (the route constraint enforces `\d{4}`).
- **GET /calendar/month/2026/05?type=video_published (filter)** renders only
  `video_*` entries.
- **GET /calendar/month/2026/05?type=invalid_kind (sad)** redirects with flash
  alert.
- **Empty state.** GET on a month with zero entries renders the grid + the
  empty-state copy + the `[ add entry ]` link.
- **Today highlight.** The cell whose date matches today carries the `today`
  class.
- **Multi-day rendering.** A `game_release` with `ends_at` 5 days later renders
  6 cells with `↳` continuations.
- **Year navigation.** GET `/calendar/month/2025/12` then click `[ next month ]`
  lands on `/calendar/month/2026/01`. Year rolls correctly. (Capybara system
  spec covers the click; request spec covers the URL build.)
- **DST forward boundary.** Querying the month grid for the spring-forward month
  (e.g., `2026/03` in Europe/Madrid) does NOT show duplicate entries, does NOT
  skip entries on the short day.
- **Year boundary entries.** An entry on Dec 31 23:30 Europe/Madrid appears on
  the Dec grid (NOT shifted to Jan 1 by UTC conversion).

#### `spec/requests/calendar/schedule_spec.rb`

- **GET /calendar/schedule (happy)** renders 200; default page is the one
  containing today; contains the `[ today ]` divider.
- **GET /calendar/schedule?page=1** explicit page renders.
- **GET /calendar/schedule?page=999 (out-of-range)** renders empty list with
  pagination saying "page 999 / N".
- **GET /calendar/schedule?type=game_release** filters.
- **GET /calendar/schedule?source=manual** filters.
- **GET /calendar/schedule?type=invalid (sad)** redirects with flash alert.
- **`[ today ]` divider.** Spans the boundary between past and future entries.
- **Pagination.** With > 50 entries, page 1 has 50 + page 2 has the rest;
  `[ prev page ]` / `[ next page ]` links render correctly at boundaries.
- **`purchase_planned` indentation.** Renders nested under its parent
  `game_release` row.
- **Reminder copy.** A future `game_release` entry without a `purchase_planned`
  child renders `[ remind: t-7 t-1 t-0 ]` per the dispatch declaration.

#### `spec/requests/calendar/entries_spec.rb`

- **GET /calendar/entries/new (happy)** renders the form.
- **GET /calendar/entries/quick_add (happy)** renders the Turbo Frame fragment.
- **POST /calendar/entries (happy — milestone_manual)** persists
  - redirects to the show page.
- **POST /calendar/entries (happy — game_release)** persists with
  `release_precision`, `manual_date_override` from form.
- **POST /calendar/entries (happy — purchase_planned)** persists with
  `parent_entry_id`, `metadata.storefront` etc.
- **POST /calendar/entries (sad — `entry_type=video_published`)** rejected
  (derived types are not user-creatable). Re-renders the form with a flash
  alert.
- **POST /calendar/entries (sad — missing title)** re-renders with validation
  error.
- **POST /calendar/entries (sad — ends_at < starts_at)** re-renders with
  validation error.
- **POST /calendar/entries (sad — `purchase_planned` without
  `parent_entry_id`)** re-renders.
- **POST /calendar/entries (sad — yes/no smuggling)** form posts `all_day=true`
  (the literal string `"true"`); the controller rejects (per CLAUDE.md
  `yes`/`no` boundary rule). Open question #7 — confirm rejection vs. coercion.
- **GET /calendar/entries/:id/edit (happy — manual)** renders.
- **GET /calendar/entries/:id/edit (sad — derived)** redirects with flash "this
  entry is read-only — edit the source instead"
  - a link to the source row (per Q13).
- **PATCH /calendar/entries/:id (happy)** updates.
- **PATCH /calendar/entries/:id (sad — derived)** rejects.
- **PATCH /calendar/entries/:id (happy — derived metadata.user_overrides)** is
  allowed via a separate dedicated endpoint (`PATCH /calendar/entries/:id/note`)
  — see Open questions #8.
- **GET /calendar/entries/:id (happy)** renders detail page with cross-links per
  Q13.
- **GET /calendar/entries/:id/show — purchase_planned** shows parent_entry link.
- **GET /calendar/entries/:id/show — game_release** shows child purchase_planned
  entries.
- **GET /calendar/entries/:id/show — milestone_auto** shows milestone_rule
  name + metric_value_at_fire.

#### `spec/requests/deletions/calendar_entry_spec.rb`

- **GET /deletions/calendar_entry/:id (happy)** renders the action-screen
  partial with calendar-entry copy ("cancel?" not "delete?" per Q5).
- **DELETE /deletions/calendar_entry/:id (happy)** flips state to `:cancelled`,
  redirects to the schedule view with flash.
- **DELETE /deletions/calendar_entry/:id (derived)** allowed? Architect's lean:
  NO — derived entries can't be cancelled manually because they are governed by
  their source row. See Open questions #1.
- **GET /deletions/calendar_entry/:id1,:id2 (bulk)** renders the action-screen
  with the count + sample of titles per the bulk-as-foundation pattern.
- **DELETE /deletions/calendar_entry/:id1,:id2 (bulk)** cancels all listed.

#### `spec/system/calendar_month_navigation_spec.rb`

- Click `[ prev month ]` from May 2026 lands on April 2026 grid.
- Click `[ next month ]` from December 2025 lands on January 2026.
- Click `[ today ]` from any month lands on the current month.
- Press `[` keyboard: prev month.
- Press `]` keyboard: next month.
- Press `t` keyboard: today.

#### `spec/system/calendar_quick_add_spec.rb`

- Click `[ add entry ]` on the month view; the Turbo Frame swaps in the form
  without a full-page reload.
- Fill out a `milestone_manual` form; click `[ save ]`; the Turbo Frame replaces
  with a success message; the new entry appears on the month grid in the right
  cell.
- Click `[ cancel ]`; the frame collapses back; the URL is unchanged.

#### `spec/system/calendar_schedule_filter_spec.rb`

- Click `[ video ]` filter; the schedule re-renders with only video\_\* entries.
- Click `[ all types ]`; reset.
- Combine `?type=` + `?source=`; both apply.

#### `spec/system/calendar_edit_delete_spec.rb`

- Manual entry: click `[ edit ]`, change title, save, see the new title on the
  month + schedule.
- Manual entry: click `[ cancel ]` (delete link); confirmation screen renders;
  click confirm; entry is `:cancelled`.
- Derived entry: no `[ edit ]` / `[ cancel ]` links — only a `[ note ]` link to
  add `metadata.user_overrides`.
- Cancelled entry rendering: appears with strike-through styling on the month +
  schedule until permanently dropped (out of scope: there is no "permanently
  delete" UI in v1).

#### `spec/components/entry_chip_component_spec.rb`

- Renders the prefix glyph per Q6 for every entry_type.
- Renders the state class per Q6 for every state.
- All-day entry omits time; timed entry includes `HH:MM`.
- Truncates title at N chars (architect picks N — see Open questions #9).
- Cross-link target per Q13 (one happy case per derived type).

#### `spec/helpers/calendar_helper_spec.rb`

- `month_grid_dates(2026, 3)` returns dates spanning Feb 23 → Apr 5
  (Monday-first 6×7 grid).
- `month_grid_dates(2026, 2)` for a short February returns the right shape.
- `entry_time_label(entry)` formats `HH:MM` for timed; returns empty string for
  all-day.
- `entry_date_label(entry)` returns lowercase abbreviated form (`mar 14`).
- `entry_chip_class(entry)` per state.

## Acceptance

The reviewer agent (or the user via the manual playbook) verifies each:

### Routes / controllers

- [ ] `GET /calendar` redirects to the current month grid.
- [ ] `GET /calendar/month/:year/:month` renders 200 with the grid.
- [ ] `GET /calendar/schedule` renders 200 with the schedule view.
- [ ] `GET /calendar/entries/new` renders the form.
- [ ] `POST /calendar/entries` creates a manual entry.
- [ ] `GET /calendar/entries/:id/edit` rejects derived entries.
- [ ] `DELETE /deletions/calendar_entry/:ids` flips state to `:cancelled` (does
      NOT destroy the row).
- [ ] Bulk-as-foundation works on the deletions URL.

### Views

- [ ] Month grid renders 6×7 (or 5×7) dates Monday-first.
- [ ] Today's cell has the `today` outline.
- [ ] Multi-day entries render as continuous bars with `↳` continuations.
- [ ] Each entry chip carries the prefix glyph per Q6.
- [ ] State styling per Q6 is correct for every state.
- [ ] Quick-add Turbo Frame swaps in without a full page reload.
- [ ] Schedule view renders the `[ today ]` divider.
- [ ] Pagination renders `[ prev page ]` / `[ next page ]` at boundaries.
- [ ] Filter cluster works on both views.
- [ ] Reminder copy (`[ remind: t-7 t-1 t-0 ]`) renders on future `game_release`
      entries without `purchase_planned`.

### Action screen / deletions

- [ ] `/deletions/calendar_entry/:ids` GET renders the confirmation screen with
      calendar-entry copy.
- [ ] DELETE flips state to `:cancelled`.
- [ ] Bulk variant works.
- [ ] Derived entries cannot reach this surface (the schedule / month views do
      NOT render the link).

### Hard-rule compliance

- [ ] No `alert()` / `confirm()` / `prompt()` / `data-turbo-confirm` anywhere in
      the new files. Verified via `git grep`.
- [ ] Yes/no booleans on every form field that crosses the boundary (`all_day`,
      `manual_date_override`, `tba_remind_monthly`, `notify_anyway`).
- [ ] Bracketed-link convention everywhere (`[ add entry ]`, `[ prev month ]`,
      etc.).
- [ ] `cursor: pointer` on every clickable per `docs/design.md`.

### Tests

- [ ] `bundle exec rspec` passes.
- [ ] Every spec file listed in §"Test sweep" exists.
- [ ] Test count delta logged in `docs/plans/beta/15-calendar/log.md`.

## Manual playbook (post-implementation)

1. **Migrate (no-op for §2).** Confirm `db/schema.rb` matches §1.
2. **Visit `/calendar`.** Confirm redirect to the current month grid.
3. **Visit `/calendar/month/2026/05`.** Confirm the May 2026 grid renders with
   weekday headers, prev/today/next cluster, filter cluster, and any existing
   entries.
4. **Visit `/calendar/schedule`.** Confirm the schedule view renders with the
   today divider in the right place.
5. **Trigger an auto-derive.** Publish a video by setting `publish_at` on a
   `videos` row (via Phase 12's edit form). Confirm the calendar entry appears
   on the month grid + the schedule view.
6. **Trigger a game release derive.** Set `release_date` on a `games` row (via
   Phase 14's edit form). Confirm the `game_release` entry + the four T-30 / T-7
   / T-1 / T-0 reminder copy appears in the schedule view.
7. **Trigger milestone derive.** Create + fire a `MilestoneRule` (via Rails
   console). Confirm the `milestone_auto` entry appears.
8. **Quick-add manual entry.** From the month grid, click `[ add entry ]`. Pick
   `milestone_manual`. Fill title `"podcast appearance"`. Save. Confirm appears
   on the month grid.
9. **Edit manual entry.** Click the chip; click `[ edit ]`; change title; save.
   Confirm renamed.
10. **Cancel manual entry.** Click `[ cancel ]`; confirm the action-screen
    confirmation page renders ("cancel calendar entry?"); confirm. Verify the
    entry now renders with strike-through styling.
11. **Verify derived entry is read-only.** Click on the auto-derived
    `video_published` entry; confirm there is no `[ edit ]` or `[ cancel ]`
    link, only a `[ note ]` link pointing at `/calendar/entries/:id/note`.
12. **Navigate months.** Click `[ next month ]`, `[ prev month ]`, `[ today ]`.
    Confirm correct rendering. Test the keyboard shortcuts (`]`, `[`, `t`).
13. **Schedule pagination.** With > 50 entries, click `[ next page ]` /
    `[ prev page ]`. Confirm correct cursor.
14. **Filters.** Click `[ video ]`, `[ game ]`, `[ milestone ]` on both views.
    Confirm filtered.
15. **Cross-link.** Click a `video_published` chip; confirm landing on
    `/videos/:id`.
16. **Edge: leap year.** Visit `/calendar/month/2024/02`; confirm Feb 29
    renders.
17. **Edge: DST forward.** Visit the install-tz spring-forward month; confirm no
    duplicate / skipped entries.
18. **Edge: year boundary.** Create an entry on Dec 31 23:30 Europe/Madrid;
    confirm it renders in Dec, not Jan.
19. **Run RSpec green; rubocop clean.** `bundle exec rspec` and
    `bundle exec rubocop` both clean.

## Cross-stack scope

| Surface           | Status                                                                                                                              |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Rails web app     | **In scope.** Primary lane.                                                                                                         |
| MCP rack app      | **Skipped.** Realignment work unit 9. The view-equivalent MCP tools (`calendar_list`) land alongside Phase 16's notification tools. |
| `pito` CLI (Rust) | **Skipped.** Realignment work unit 10.                                                                                              |
| Astro / website   | **Skipped.** N/A.                                                                                                                   |

## Copy questions to escalate (master agent asks user before dispatch)

The architect calls these out; the user picks the wording. Do NOT pick copy in
the spec.

1. **Calendar headings.** Architect's draft: month name lowercase abbreviated
   `mar 2026` in the navigation cluster. Confirm.

2. **Year display in the year picker.** Lowercase `2026` flat link cluster of 12
   month links. Confirm.

3. **Entry kind labels in the filter row.** Architect's draft: `[ video ]`
   (covers `video_published` + `video_scheduled`), `[ game ]` (covers
   `game_release`), `[ milestone ]` (covers `milestone_manual` +
   `milestone_auto`), `[ purchase ]` (covers `purchase_planned`), `[ custom ]`
   (covers `custom`). Channel entries are filtered into `[ all types ]` only
   because they're rare. Confirm or alter.

4. **Action-screen copy for `calendar_entry`.** Default deletion copy is
   "permanently delete?". For calendar entries the semantic is soft-cancel
   (state flips to `:cancelled`), so the copy should match. Architect proposes:
   - Title: `"cancel calendar entry?"` (singular) or
     `"cancel <count> calendar entries?"` (bulk).
   - Body:
     `"this will mark the entry as cancelled. it stays on   the calendar with strike-through styling. you can reopen it   later via [ uncancel ] (TBD — see Open questions #3)."`
     User picks final wording.

5. **Quick-add form labels.** Lowercase per `docs/design.md`. Each field
   labeled: `type`, `title`, `starts at`, `time`, `timezone`, `all day`,
   `ends at`, etc. User confirms or shifts.

6. **Empty-state copy.**
   - Month grid: `"no entries this month — [ add entry ]"`.
   - Schedule: `"no entries — [ add entry ]"`. User confirms or shifts.

7. **Navigation labels.** Architect's draft: `[ prev month ]` / `[ next month ]`
   / `[ today ]`. The `[ today ]` link only renders when the user is NOT on the
   current month grid. User confirms.

8. **Reminder inline copy on `game_release` rows.** Architect's draft:
   `[ remind: t-7 t-1 t-0 ]`. User confirms or asks for word-form
   (`[ remind: 7 days, 1 day, on the day ]`).

9. **`[ note ]` link copy on derived entries.** Architect's draft: `[ note ]`
   opens a modal that edits `metadata.user_overrides`. User confirms wording.

10. **State labels on the schedule view.** Architect's draft: the enum strings
    verbatim: `scheduled` / `occurred` / `cancelled` / `superseded`. User
    confirms or shifts.

11. **Recurrence rule selector copy.** Per §1 Q9, recurrence is deferred. The
    form does NOT surface a recurrence selector in v1. If the user wants a
    placeholder copy explaining the deferral, the form footer can render
    `"recurring entries — coming soon"`. Architect's lean: no copy; surface in
    §16 instead. User confirms.

## Open questions (architect cannot decide; master agent surfaces to

user)

1. **Soft-cancel for derived entries.** Architect's lean: derived entries cannot
   be soft-cancelled — they're governed by their source row. But the user might
   want to dismiss a derived entry (e.g., "I don't want this video_scheduled
   showing up because the schedule got reverted"). Open: should derived entries
   gain a `dismissed` state separate from `:cancelled`? Architect's lean: defer;
   v1 has no dismiss.

2. **Default state filter on month / schedule views.** Architect's lean: hide
   `:cancelled` and `:superseded` by default; surface via an explicit
   `?state=all` query param OR an `[ include cancelled ]` toggle. User confirms
   or asks for "show everything always".

3. **`[ uncancel ]` UX.** A cancelled entry is a soft-deleted row with
   `state=:cancelled`. Reopening it is a state flip back to `:scheduled` or
   `:occurred` depending on `starts_at`. Open: does v1 ship the un-cancel UX, or
   is it "manual SQL only" until Phase 16+? Architect's lean: defer to a
   follow-up; v1 ships only the cancel direction.

4. **`[ project ]` link on entries with `project_id`.** A manual entry attached
   to a project shows the project name as a link on the show page. Open: surface
   on the chip too (e.g., `m: anniversary [ project: foo ]`)? Architect's lean:
   detail page only; chips stay terse.

5. **ViewComponent vs. ERB partial for `EntryChipComponent` /
   `EntryRowComponent`.** Architect's lean per `MEMORY.md`: ViewComponent for
   the small repeating units; ERB partial for the larger views. User confirms.

6. **First day of week.** Architect's draft: Monday-first (per the install-tz
   default of Europe/Madrid). User can override via Open question (or via
   `AppSetting.first_day_of_week`, added as a follow-up). Open: ship
   Monday-first hard-coded in v1, or add the setting now? Architect's lean:
   hard-coded Monday-first; setting follow-up.

7. **Yes/no boundary enforcement on form posts.** Architect's lean: the
   controller coerces `"yes"` / `"no"` strings to booleans before assigning to
   the model. Stray `"true"` / `"false"` strings get rejected with a 422 +
   flash. User confirms strict-rejection or lenient-coercion.

8. **`PATCH /calendar/entries/:id/note` endpoint for
   `metadata.user_overrides`.** Architect's lean: add this endpoint to allow
   notes on derived entries without violating the read-only enforcement. User
   confirms ship-now or defer.

9. **Title truncation length on chips.** Architect's lean: 24 chars + `…`. User
   picks final number (or asks for elastic width based on cell width).

10. **Saved view integration.** The `SavedView` model exists from Phase 4 with
    `kind: %w[channels videos]`. Calendar would need a `calendar_month` /
    `calendar_schedule` kind. Architect's lean: defer to a follow-up; v1 ships
    without saved views. Open: include now? User picks.

11. **ICS / iCal export endpoint.** Note 5 §"Future hooks": "iCal export —
    subscribe-to feed for external calendar apps." Open: ship a
    `GET /calendar/feed.ics` returning the full set in v1? Architect's lean:
    defer per note 5 ("Out of scope for v1").

## Master agent decisions (2026-05-10)

Master agent has resolved every copy question and open question above per the
autonomy rule. The decisions below override any "TBD" / "user picks" framing.
Implementation agent treats these as the contract.

### Copy decisions

1. Calendar headings — lowercase abbreviated month-year: `mar 2026`.
2. Year picker — flat 12-month link cluster, lowercase month names.
3. Entry kind filter labels — architect's draft: `[ video ]` (covers
   `video_published` + `video_scheduled`), `[ game ]` (covers `game_release`),
   `[ milestone ]` (covers both milestone types), `[ purchase ]`, `[ custom ]`.
   Channel entries surface only via `[ all types ]`.
4. Action-screen copy for `calendar_entry` (soft-cancel):
   - Title: `cancel calendar entry?` (singular) /
     `cancel <count> calendar entries?` (bulk).
   - Body:
     `this will mark the entry as cancelled. it stays on the calendar with strike-through styling.`
     (Drop the architect's `[ uncancel ]` reference since uncancel is deferred
     to a follow-up per Open question #3 below.)
5. Quick-add form labels — lowercase per design: `type`, `title`, `starts at`,
   `time`, `timezone`, `all day`, `ends at`, etc.
6. Empty-state copy:
   - Month grid: `no entries this month — [ add entry ]`.
   - Schedule: `no entries — [ add entry ]`.
7. Navigation labels — `[ prev month ]` / `[ next month ]` / `[ today ]`. The
   `[ today ]` link renders only when NOT on the current month.
8. Reminder inline copy on `game_release` rows — `[ remind: t-7 t-1 t-0 ]`
   (terse).
9. `[ note ]` link on derived entries — verbatim `[ note ]`.
10. State labels on schedule view — verbatim enum strings: `scheduled` /
    `occurred` / `cancelled` / `superseded`.
11. Recurrence rule selector copy — no copy in v1. Recurrence is deferred per
    Spec 01 Open question #1.

### Open-question decisions

1. **Soft-cancel for derived entries** — defer. v1 has no `dismiss` state.
   Derived entries are governed by their source row.
2. **Default state filter on month / schedule views** — hide `:cancelled` and
   `:superseded` by default. Surface via an explicit `?state=all` query param
   AND an `[ include cancelled ]` toggle on the schedule view.
3. **`[ uncancel ]` UX** — defer to a follow-up. v1 ships only the cancel
   direction.
4. **`[ project ]` link on entry chips** — detail page only; chips stay terse.
5. **ViewComponent vs ERB partial** — ViewComponent for small repeating units
   (`EntryChipComponent`, `EntryRowComponent`); ERB partials for the larger
   views. Per the user-memory note on ViewComponent posture.
6. **First day of week** — hard-coded Monday-first in v1.
   `AppSetting.first_day_of_week` setting is a follow-up.
7. **Yes/no boundary enforcement** — strict rejection. Stray `"true"` /
   `"false"` / `"1"` / `"0"` get rejected with 422 + flash. Per CLAUDE.md hard
   rule on yes/no boundary discipline.
8. **`PATCH /calendar/entries/:id/note` endpoint** — ship in v1. Allows notes on
   derived entries without violating read-only enforcement.
9. **Title truncation length on chips** — 24 chars + `…`.
10. **`SavedView` integration for calendar** — defer to a follow-up. v1 ships
    without saved-view support for calendar.
11. **ICS / iCal export endpoint** — defer per Note 5 ("Out of scope for v1").

## Non-goals (explicit)

- Day / week / year views.
- Drag-to-reschedule.
- Bulk-select on the schedule.
- Recurrence (deferred per §1 Q9).
- iCal export (deferred).
- Saved-view integration (deferred).
- MCP tools (work unit 9).
- CLI parity (work unit 10).
- Notification delivery (Phase 16).
- Email delivery (note 5 explicit non-goal).

## Reviewer checkpoints (post-implementation)

The reviewer agent runs:

1. `bundle exec rspec` — green.
2. `bundle exec rubocop` — clean.
3. `bundle exec brakeman -q` — clean.
4. Manual playbook §1-§19.
5. Spec file count delta logged in `docs/plans/beta/15-calendar/log.md`.
6. `git grep 'alert(\|confirm(\|prompt(\|data-turbo-confirm'` returns ZERO
   matches in the new files.
7. `git grep 'cursor: pointer'` shows the new clickable elements all have it
   (per `docs/design.md`).
8. The new locales under `config/locales/en.yml` are lowercase per the design
   system.
