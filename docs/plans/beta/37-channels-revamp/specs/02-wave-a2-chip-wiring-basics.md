# Wave A2 — chip → controller wiring + Basics section

## Goal

Wave A1 shipped an inert `/channels` shell. Filter chips toggle URL params but
the controller ignores them, so the page renders the full 6-channel mock list
regardless of which chips are checked. Wave A2 closes that loop for the
**channel-selection** axis (`?channels=`) and introduces the first aggregated
metric block under the ID-card shelf: a **Basics** row that surfaces total
subscribers / views / videos / watch hours across the selected channels.

This is the first wave that gives the page a meaningful interaction story —
toggling a channel chip filters the ID-card shelf AND recomputes the four
totals. Time-window (`?windows=`) and calendar (`?calendar=`) params are wired
into the controller so the surface is ready for Wave B's real query layer, but
their value is not yet consumed in render — Wave A2 ships them as no-op
plumbing.

The user audience is the dashboard operator running multiple YouTube channels:
the long-term goal is "combine my multiple channels into a unified dashboard"
(handoff doc §"Open follow-ups"). The Basics row is the first concrete
expression of that goal — four numbers that fold together however many channels
are currently selected.

## Files touched

### New

- `app/services/channels/aggregator.rb` — pure-function aggregator service.
  Initially exposes four sum-totals across an array of channel hashes
  (subscribers, views, videos, watch hours). Wave C / D / E will extend it.
- `app/components/channels/basics_section_component.rb` +
  `.html.erb` — renders the four-stat horizontal row. No heading row, no
  `ShelfComponent` chrome (see §"Visual specs" for the rationale).
- `app/components/channels/basics_stat_component.rb` +
  `.html.erb` — single-stat cell (number on top, muted label below). Reused
  four times inside `Channels::BasicsSectionComponent`.

### Modified

- `app/controllers/channels_controller.rb` — `#index` reads the three URL
  params (`windows`, `calendar`, `channels`), exposes the parsed values as
  instance variables, and filters `@channels` by `?channels=` membership.
- `app/services/channels/mock_data.rb` — adds a `:video_count` integer key to
  every channel hash so the new "videos" column has a value to render in Wave
  A2. Mirrors the real `Channel#video_count` column (per
  `app/models/channel.rb` L159).
- `app/views/channels/index.html.erb` — adds the
  `Channels::BasicsSectionComponent` render call after the ID-card shelf
  hairline. No styling change to existing sections.

### Untouched

- `app/components/channels/title_bar_component.*` — no change.
- `app/components/channels/avatar_shelf_component.*` /
  `avatar_chip_component.*` — no change. The chips already write the right URL
  values; only the controller needed to start reading them.
- `app/components/channels/id_card_component.*` — no change.
- `app/components/filter_chip_component.*` — no change. The chip already
  supports csv multi-select via `csv: true` (per
  `app/components/filter_chip_component.rb` L48–L84).
- `app/assets/tailwind/application.css` — Wave A2 ships zero new global CSS;
  layout uses inline `style="…"` per the rest of the /channels Wave A1
  components (kept inline until Wave A is signed off and the inline soup gets
  extracted into class selectors as part of the consolidation pass).

## URL contract

### `?channels=` — channel-selection filter (consumed in Wave A2)

- Format: comma-separated channel id strings —
  `/channels?channels=1,3,5`.
- Empty / missing param: render ALL channels from `Channels::MockData.channels`
  (this matches the existing Wave A1 behavior so an un-filtered visit shows the
  full dashboard).
- Param present with empty value (`/channels?channels=`): render ZERO channels
  (the avatar shelf, ID-card shelf, and Basics row all collapse to the empty
  state — see §"Empty state"). This distinguishes "I deselected everything" from
  "default view = everything".
- Unknown ids (a value that doesn't match any mock channel id): silently
  ignored. Robustness over strict validation — the mock data set is small and
  the failure mode for a stale bookmark should be "show what I have" not 404.
- Order: render order matches `Channels::MockData.channels` order, NOT URL
  order. The URL is a SET, not a sequence. (Re-ordering channels in the shelf
  is out of scope for Wave A2.)

### `?windows=` — time-window filter (wired but no-op in Wave A2)

- Format: comma-separated window keys —
  `/channels?windows=7d,28d`. Allowed values:
  `7d`, `28d`, `3m`, `365d`, `alltime`.
- The controller parses + exposes the parsed array as `@selected_windows`
  (Array<String>). No render code consumes it in Wave A2; Wave B's
  `Channels::Stats.*` query layer is the first reader.
- Unknown values: silently ignored at parse time.

### `?calendar=` — year/month filter (wired but no-op in Wave A2)

- Format: comma-separated calendar keys —
  `/channels?calendar=2025,2026,apr,may`. Allowed values: previous + current
  year strings (e.g. `2025`, `2026`) and the lowercase 3-letter month
  abbreviation for previous + current month (e.g. `apr`, `may`), derived by
  `Formatting::CurrentChannelFilterChips`.
- The controller parses + exposes `@selected_calendar` (Array<String>). No
  render code consumes it in Wave A2.
- Unknown values: silently ignored at parse time.

### Parse rules — shared

- All three params use the same `parse_csv_param` helper (or equivalent inline
  parse): `params[:param].to_s.split(",").map(&:strip).reject(&:blank?)`.
- A nil param (missing entirely) and an empty-string param (`?channels=`)
  parse to different array states:
  - missing → `nil` sentinel → "no filter applied, render default"
  - present-but-empty → `[]` → "filter applied to empty set, render zero"
- For `?channels=` only, the empty-array case must be honored as
  "render zero channels" so the UX matches the chip-row visual state ("0 of 6
  checked").

## Mock data contract

Each entry in `Channels::MockData.channels` must carry the following keys after
the Wave A2 patch. (Existing keys from Wave A1 stay; the diff is the addition
of `:video_count`.) Wave B's `Channels::Stats.*` query layer must return the
same keys so the view-layer swap is constant.

| Key                          | Type   | Wave A2 use                                                |
| ---------------------------- | ------ | ---------------------------------------------------------- |
| `:id`                        | Int    | Filter key (matches `?channels=` value).                   |
| `:display_name`              | String | ID card name row.                                          |
| `:handle`                    | String | ID card handle link.                                       |
| `:youtube_channel_id`        | String | ID card Studio URL.                                        |
| `:avatar_url`                | String | Avatar tile (nil = placeholder square).                    |
| `:subscriber_count`          | Int    | ID card row + Basics subscribers total.                    |
| `:view_count`                | Int    | ID card row + Basics views total.                          |
| **`:video_count` (NEW)**     | Int    | Basics videos total. Distinct from `pito`-imported videos. |
| `:watch_hours`               | Int    | ID card row + Basics watch hours total.                    |
| `:subscriber_count_trend`    | Symbol | ID card trend arrow (unchanged).                           |
| `:view_count_trend`          | Symbol | ID card trend arrow (unchanged).                           |
| `:watch_hours_trend`         | Symbol | ID card trend arrow (unchanged).                           |
| `:joined_at`                 | Date   | Dormant (unchanged).                                       |

The new `:video_count` values must spread across diverse `Formatting::*`
branches so the Basics renderer exercises every formatter tier at least once
when ALL 6 channels are selected. Suggested values per current `:id`:

| `:id` | `:display_name`  | `:video_count` |
| ----- | ---------------- | -------------- |
| 1     | Studio Aurora    | 4              |
| 2     | Pixel Forge      | 23             |
| 3     | Long-form Lab    | 87             |
| 4     | Quiet Cinema     | 156            |
| 5     | Field Notes      | 412            |
| 6     | Neon Atlas       | 1_840          |

These are illustrative — the implementation agent may pick equivalent values
that maintain the same property (≥ 1 entry < 10, ≥ 1 entry in `10..999`, ≥ 1
entry ≥ 1_000).

## Aggregator service interface

`Channels::Aggregator` is a stateless module-function service. No instance
state, no I/O, no Rails dependency beyond Ruby integer arithmetic.

### Method signatures (Wave A2)

```ruby
module Channels
  module Aggregator
    module_function

    # @param channels [Array<Hash>] entries from Channels::MockData.channels
    #   (or, in Wave B, from the real query layer producing the same shape).
    # @return [Integer] sum of :subscriber_count across the array.
    #   Returns 0 for an empty array. Skips entries where the key is nil.
    def subscribers_total(channels)
    end

    # @return [Integer] sum of :view_count.
    def views_total(channels)
    end

    # @return [Integer] sum of :video_count.
    def videos_total(channels)
    end

    # @return [Integer] sum of :watch_hours.
    def watch_hours_total(channels)
    end
  end
end
```

### Implementation rules

- Pure sum. `channels.sum { |c| c[:key].to_i }`. `.to_i` on the value coerces a
  nil entry to 0 without raising, matching the mock data's "nil = unknown"
  semantics.
- Empty input: returns `0` (Integer). Never `nil`, never em-dash — the
  renderer is responsible for em-dash semantics if it wants them (see §"Empty
  state" below).
- The service does NOT call `Formatting::*` — that's the renderer's job. Keep
  the aggregator output in raw integer units so it stays composable for
  downstream sections (Wave A4 window summaries, Wave A5 trends, etc.).

### Wave C/D/E methods — STUBBED, NOT SPECCED HERE

The aggregator will eventually grow methods like
`geography_totals(channels)`, `demographics_split(channels)`, and
`trend(metric, channels)`. Those are out of scope for Wave A2. Add a brief
header comment in `aggregator.rb` noting "Wave C/D/E will extend this service"
so the next reader doesn't think the four sum methods are the final surface.

## ViewComponent shapes

### `Channels::BasicsSectionComponent`

Responsibility: render the four-stat horizontal row beneath the ID-card shelf
hairline. Reads from the controller-provided `@channels` (already filtered by
`?channels=`) and delegates aggregation to `Channels::Aggregator`.

Constructor:

```ruby
def initialize(channels:)
  @channels = Array(channels)
end
```

The component DOES NOT take an explicit aggregator dependency — it calls the
module-function service directly. (Future Wave B refactor may introduce a
dependency-injection seam if the real-data path needs a different aggregator
strategy; for Wave A2 the direct call is simpler and equally testable.)

Template responsibilities:

- Render a `<section class="channels-basics">` wrapper.
- Inside the section, render four `Channels::BasicsStatComponent` instances in
  a horizontal flex row.
- After the row, emit a single `<hr class="hairline">` so the bottom edge reads
  as a clean separator — matches the inter-shelf hairline convention used on
  `/games` (per `app/views/games/index.html.erb` L158, L173, L180) and the
  ID-card shelf above (per `app/views/channels/index.html.erb` L110).

NO heading. The four labels under the numbers carry enough context that an
explicit "Basics" heading would be redundant chrome. (Re-confirm at user
validation — see §"Open questions".)

### `Channels::BasicsStatComponent`

Responsibility: render a single stat cell — the formatted number on top, a
muted lowercase label below.

Constructor:

```ruby
def initialize(value:, label:, formatter:)
  @value = value
  @label = label
  @formatter = formatter
end
```

- `value` — raw integer (or nil) from the aggregator.
- `label` — display string (e.g. `"subs"`, `"views"`, `"videos"`, `"hours"`).
  Plain text, lowercase, per the rest of the page's muted-label convention.
- `formatter` — a module that responds to `.call(value)`. The two formatters
  in play:
  - `Formatting::CompactCount` — for subs / views / videos.
  - `Formatting::CompactHours` — for watch hours.
  Passing the formatter in keeps the component generic; the BasicsSection
  parent chooses which formatter each stat gets.

Template:

```erb
<div class="channels-basics__stat"
     style="display: flex; flex-direction: column; align-items: flex-start; gap: 2px;">
  <span class="channels-basics__value"
        style="font-size: 22px; font-weight: bold; font-variant-numeric: tabular-nums; line-height: 1.2;">
    <%= @formatter.call(@value) %>
  </span>
  <span class="channels-basics__label text-muted"
        style="font-size: 11px;">
    <%= @label %></span>
</div>
```

The `font-variant-numeric: tabular-nums` keeps the digits monospaced so the
four numbers visually align even with diverse widths (matches the same rule on
`Channels::IdCardComponent` stat grid — per `id_card_component.rb` L94–L95).

## Visual specs

### Section placement

```
<title bar>
<chip row + avatar shelf>
<hairline>                                  ← existing
<ID-card shelf (6 cards, scrollable row)>
<hairline>                                  ← existing
<NEW: Channels::BasicsSectionComponent>
<hairline>                                  ← emitted by BasicsSection trailing <hr>
```

### Layout — Basics row

A single horizontal flex row spanning the full `.channels-main` width. Four
stat cells distributed evenly:

```
1.3M       47M       2.5K       370.671h
subs       views     videos     hours
```

- Outer wrapper: `display: flex; gap: 32px; align-items: flex-end; margin: 12px 0 0;`.
- Gap between cells: 32px (loose — these are the highest-density numbers on
  the page; they need breathing room).
- `align-items: flex-end` so the baselines of the number row align even if
  individual numbers' rendered heights differ.
- Top margin 12px to match the `.shelf` default margin
  (`app/assets/tailwind/application.css` L982-area `.shelf { margin-top: 16px }`
  minus a couple of pixels because the preceding hairline already adds visual
  separation).

### Typography

- **Number:** 22px bold, monospace (inherits from body), tabular-nums.
  22px is the SAME size used by /games show summary headings (per
  `app/views/games/show.html.erb` L279 `<h2>` rendered via the global
  `h2 { font-size: 14px }` — NOTE this is a deviation: the basics numbers are
  bigger than `<h2>` because they're the section's PRIMARY content, not a
  chrome label). The 22px value is NEW for /channels Wave A2 and is part of the
  design-time decision flagged for user pre-confirm (see §"Open questions"
  Q3).
- **Label:** 11px muted (`var(--color-muted)` via the existing `.text-muted`
  class). Lowercase. Matches the auxiliary-label pattern from
  `/videos` index (per `app/views/videos/index.html.erb` L136
  `font-size: 11px` on the `imported` chip).
- **Number color:** default body `var(--color-text)`. NOT bold-text — the
  `font-weight: bold` makes the size do the emphasis, and bold-text would
  over-power the page.

### Vertical rhythm

The Basics section is the FIRST aggregated-metric block under the ID-card
shelf. Future sections (Top Content, Window summaries, Trends, etc.) will use
the same `<section class="channels-..."> ... <hr class="hairline"> </section>`
pattern so the entire `.channels-main` reads as a stack of separated blocks.

### Empty state — zero channels selected

When `@channels` is empty (user unchecked everything via `?channels=`), the
ID-card shelf above renders zero tiles (existing Wave A1 behavior — the `each`
loop iterates an empty array). The Basics section follows the same approach:
render the four stat cells with the value `0` rather than collapsing the
section entirely.

- `Channels::Aggregator.*_total([])` returns `0` (Integer).
- `Formatting::CompactCount.call(0)` renders `"0"`.
- `Formatting::CompactHours.call(0)` renders `"0h"`.

This keeps the page's vertical layout stable as the user toggles chips — they
don't see shelves materializing and dematerializing. (Re-confirm with user at
validation — see §"Open questions" Q5.)

### Token traceability

- `--color-muted` for the label — canonical via `docs/design.md` L7 ("muted
  `#555`").
- `--color-text` for the number — canonical via the same line ("text
  `#1a1a1a`").
- `tabular-nums` reused from `Channels::IdCardComponent` (per
  `id_card_component.rb` L94–L95).
- 11px label / 13px body alignment reused from `/videos` index +
  `Channels::IdCardComponent`.
- 22px stat value is NEW — flagged as Open Question Q3 for user pre-confirm
  before dispatch.

## Acceptance

- [ ] Visiting `/channels` with no query params renders all 6 mock channels in
      the ID-card shelf AND the Basics row shows totals across all 6:
      subscribers = `1_213_303`, views = `48_245_589`, videos = sum of new
      mock `:video_count` values, watch hours = `370_671`.
- [ ] Visiting `/channels?channels=1,3` renders 2 ID cards (Studio Aurora +
      Long-form Lab) and the Basics row recomputes to their pair-sums.
- [ ] Visiting `/channels?channels=` renders zero ID cards and the Basics row
      shows `0` / `0` / `0` / `0h`.
- [ ] Visiting `/channels?windows=7d,28d&calendar=2025,apr&channels=1` does
      NOT crash; the `?windows=` and `?calendar=` params are parsed into
      `@selected_windows` / `@selected_calendar` (verifiable via a controller
      ivar dump in `bin/rails routes`-style debug — no render diff today).
- [ ] Toggling a chip in the avatar shelf updates the URL `?channels=` value
      AND visually filters the ID-card shelf + Basics row on the resulting
      navigation. (No Stimulus / no live update — the chip is a link, the
      browser navigates, the controller re-renders.)
- [ ] An unknown id in `?channels=` (e.g. `?channels=999`) renders zero cards
      and zero totals without raising.
- [ ] `Channels::Aggregator` has the four documented public methods, all
      module-function, all pure. (Verify by reading the file — no spec writing
      in Wave A2 per the iteration-mode rule.)
- [ ] `Channels::BasicsSectionComponent` renders inside `app/views/channels/
      index.html.erb` after the ID-card shelf's hairline, with no regression to
      the title bar / chip row / avatar shelf / ID-card shelf above.
- [ ] No new global CSS in `application.css`. All layout via inline styles
      (the consolidation pass will extract class selectors later).
- [ ] No emojis in any code, view, or comment (per `CLAUDE.md`
      §"Communication style").

## Manual test recipe

Fresh terminal:

```bash
bin/dev
```

Open `http://localhost:3000/channels` in a browser.

1. **All 6 channels.** With a clean URL (no query params), confirm:
   - The ID-card shelf renders 6 cards.
   - Below the shelf's hairline, the Basics row shows four numbers:
     `1.2M  47M  <videos>  370.671h`
     with labels `subs / views / videos / hours` beneath.
   - The number font is bigger than the page's body text but smaller than the
     h1 (subjectively `~22px`).
   - The labels are muted.
2. **Filter to 2 channels.** Click the avatar chip for "Studio Aurora"
   (id=1), then click "Long-form Lab" (id=3). After each click the page
   navigates; after the second navigation the URL bar reads
   `…/channels?channels=1,3`. Confirm:
   - The ID-card shelf renders 2 cards (Studio Aurora + Long-form Lab).
   - The Basics row updates to that pair's sums.
3. **Filter to zero.** Click all 6 avatar chips off (until each `[ ]` is
   unchecked). URL reads `…/channels?channels=`. Confirm:
   - The ID-card shelf is empty (zero cards rendered).
   - The Basics row shows `0  0  0  0h` (one stat cell per metric, all zero).
   - The chip row + title bar still render normally above (page chrome
     untouched).
4. **Unknown id.** Manually edit the URL to `…/channels?channels=999`. Confirm:
   - Page does not 500.
   - ID-card shelf renders zero cards.
   - Basics row shows `0  0  0  0h`.
5. **Window + calendar params are no-op.** Set
   `…/channels?windows=7d,28d&calendar=2025,apr&channels=1,2`. Confirm:
   - The 7d / 28d / 2025 / Apr chips render as `[x]` (checked).
   - The ID-card shelf renders 2 cards (channels 1 + 2).
   - The Basics row matches the pair-sum.
   - No visible change from the data layer (windows + calendar are wired but
     not yet read by render code — verify by comparing Basics totals against
     step 2's same-channels case: they should be identical regardless of the
     `?windows=` value).

No state to tear down — `/channels` is read-only this phase.

## Cross-stack scope

| Surface  | In scope?         | Notes                                                                                                          |
| -------- | ----------------- | -------------------------------------------------------------------------------------------------------------- |
| Rails    | Yes               | Sole stack for Wave A2.                                                                                        |
| MCP      | No                | `/channels` mocked dashboard is a web-only surface this phase. MCP parity returns in a later wave once data is real. |
| pito CLI | No                | Same as MCP. Paused per `feedback_web_polish_focus` memory entry.                                              |
| Website  | No                | Marketing site is unaffected.                                                                                  |

## Out of scope

- `?windows=` and `?calendar=` consumed in render. Wired into the controller
  only; Wave B's `Channels::Stats.*` query layer is the first reader.
- Trend deltas on the Basics numbers (▲ / – / ▼ glyphs + percent). Deferred to
  Wave E. The Basics section in Wave A2 is FLAT totals only.
- Per-window aggregated summaries (e.g. "subs gained in 7d"). Deferred to Wave
  A4 (Window summaries section).
- The Aggregator's Wave C / D / E methods (geography, demographics, traffic,
  trend). Stubbed only in the file header comment.
- Specs for the new service + components. Per the iteration-mode rule (handoff
  §"Way of work" + `CLAUDE.md` §"Iteration vs consolidation"), specs are a
  Wave F deliverable.
- Live Updates (Turbo Stream re-render on sync completion). Wave B integration
  per handoff §7.
- `[+]` and `[-]` title bar action handlers. Wave A13 / A14 in the plan.
- Class-selector extraction for the new inline styles. Part of the layout-lock
  consolidation pass after Wave A18.

## Implementation dispatches

Five small `pito-rails-impl` dispatches, each targeting a distinct file set so
the architect can fan them in parallel where the dependency graph allows.

The dependency graph:

```
D1 (mock data extension) ── independent
D2 (Aggregator service)  ── independent
D3 (stat component)      ── independent
D4 (section component)   ── depends on D2 + D3
D5 (controller + view)   ── depends on D1 + D4
```

D1 / D2 / D3 fan out in parallel; D4 follows D2+D3; D5 follows D1+D4. Wall-
clock target per dispatch: **≤ 5 minutes** (per `CLAUDE.md` §"Dispatch sizing").

### D1 — Mock data extension

- Add `:video_count` integer key to all 6 entries in
  `app/services/channels/mock_data.rb`.
- Update the module's header docstring to note `:video_count` joined the per-
  channel hash for Wave A2.
- Pick values per the §"Mock data contract" table above (or equivalent spread).
- No render-side change.

### D2 — `Channels::Aggregator` service

- Create `app/services/channels/aggregator.rb` as a module-function service.
- Implement the four public methods documented in §"Method signatures".
- Pure sum implementation. Empty array returns 0.
- Add the header docstring noting "Wave C/D/E will extend this service".

### D3 — `Channels::BasicsStatComponent`

- Create `app/components/channels/basics_stat_component.rb` +
  `.html.erb`.
- Constructor takes `value:`, `label:`, `formatter:`.
- Template renders the number-then-label stack per §"Template" snippet.
- Inline styles only.

### D4 — `Channels::BasicsSectionComponent`

- Create `app/components/channels/basics_section_component.rb` +
  `.html.erb`.
- Constructor takes `channels:`.
- Calls `Channels::Aggregator.*` for the four totals.
- Renders four `Channels::BasicsStatComponent` instances in a flex row.
- Emits a trailing `<hr class="hairline">`.
- Inline styles only.
- Dispatch prompt MUST cite D2 and D3 as upstream dependencies.

### D5 — Controller wiring + view render

- Update `ChannelsController#index` HTML branch:
  - Parse `params[:channels]` into `selected_channel_ids` (array of strings).
    Nil sentinel: param missing → render all. Empty array: param present but
    empty → render zero.
  - Parse `params[:windows]` into `@selected_windows` (array). Allowed values
    only; unknown ignored.
  - Parse `params[:calendar]` into `@selected_calendar` (array). Allowed
    values only; unknown ignored.
  - Filter `Channels::MockData.channels` by id membership into `@channels`.
- Update `app/views/channels/index.html.erb` to render
  `Channels::BasicsSectionComponent.new(channels: @channels)` after the ID-
  card shelf's trailing `<hr class="hairline">`.
- No spec writing per iteration-mode rule.
- Dispatch prompt MUST cite D1 (for the new `:video_count` key) and D4 (for
  the section component) as upstream dependencies.

## Open questions

These need a user-locked decision before the implementation dispatches fan
out. The architect surfaces them so the master agent can ask the user in one
batch rather than discovering them mid-implementation.

1. **Heading or no heading on the Basics section?** The spec defaults to NO
   heading (the four labels carry the context). If the user prefers an
   explicit `<h2>basics</h2>` label above the row, the section grows a heading
   wrapper matching the `/games show` summary heading style
   (per `app/views/games/show.html.erb` L279, 14px bold via the global
   `h2` rule). Either path is one extra `<h2>` line in the template.
2. **Empty-state rendering — `0 / 0 / 0 / 0h` vs collapse vs em-dash?** The
   spec defaults to "render zeros". Alternatives:
   - Collapse the entire section (no row at all when zero channels selected).
   - Render em-dashes (`Formatting::CompactCount.call(nil)` already returns
     `—` — the renderer would have to switch which formatter input it passes
     in the empty case).
3. **Number font size — 22px?** No existing token covers a "section-primary
   stat" size; 22px is an architect-picked value sitting between body 13px and
   h1 18px, leaning bigger than h1 because these are the section's PRIMARY
   content not chrome. User pre-confirm desired before committing the value to
   the inline style.
4. **Stat cell ordering — subs / views / videos / hours?** This is the order
   the ID card uses internally (per `Channels::IdCardComponent` template;
   subs, views, hours — with videos NEW for Basics). Spec inserts `videos`
   between `views` and `hours`. Alternative: subs / videos / views / hours
   (alphabetical noun + verb pair). Pre-confirm.
5. **`render zeros` vs `omit section` on zero-selected.** Cross-references Q2
   — calling it out explicitly here because the answer also affects the
   Basics row's role in the page's vertical rhythm. If the row disappears,
   future Wave A3+ sections inherit the same "appear/disappear on chip toggle"
   behavior. The spec defaults to "always render — content swaps to zeros" so
   the user's visual baseline stays constant as they toggle chips.
