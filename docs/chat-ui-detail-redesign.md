# Pito chat-UI detail-message redesign

> Status: draft

## Sign-off

- [x] Drafted — 2026-06-17
- [x] Audited — 2026-06-17

## Context

A batch of chat-UI refinements that converge the **video** and **game** detail
messages onto a consistent two-column layout, resize the channel item to match
the cover art, add a reusable hairline, make the sidebar animation honor
`/config fx`, and richen the `list videos`/`list games` table (colored added
headings, a dynamic addable-columns footer, and width-aware default columns).
Builds directly on this session's earlier work (inline timestamps, P5 cover
regeneration, the video-detail 2-column pass).

## North star

`list channels` / `show game` channel items are 180px wide (matching covers);
the video detail shows a one-line stats row, title + Description label in the
right column, and its intro constrained to the thumbnail column; the game detail
mirrors video with a 480px cover, ordered left-column fields, and Description +
hairline + Score + TTB in the right column; the hairline is one reusable thin
component; and the sidebar animates only when `/config fx` is on.

## Locked decisions

| Topic | Decision |
| --- | --- |
| Bigger game cover | Bump master to 480×640 + regenerate (crisp), add a `DETAIL_COVER_VARIANT [480,640]`; similar-games stay 180px via `COVER_VARIANT`. |
| Hairline | Reuse `Pito::Separator::DividerLineComponent` `hairline: true` mode, tuned thinner/fainter; replace the video detail hand-coded `<hr>`. |
| Video stats row | One row: dim label + value, `·`-separated — `Views 188 · Likes 4 · Comments 0`. |
| Intro in left column | Intro becomes a leading row capped at the left-column width (inline-block max-width = cover/thumbnail 480px) so the timestamp stays inline AND the intro doesn't run under the right column; the two columns sit below it. |
| Channel item width | 180px in both surfaces (avatar stays 120px, title truncates, score bar narrows). |
| fx gating | Mirror `type_fx_controller.js`: read `fxEnabled()` from `pito/settings.js` (`#pito-settings[data-fx]`), gate the sidebar width transition; watch `#pito-settings` for live `/config fx` toggles. |
| List heading color | Added-column headings → `text-cyan`; the 2 defaults (id/title) stay `text-fg-faded`. Applies to any non-default column (whether via `with` or width auto-fill). |
| Addable-columns footer | Italic `Pito::Copy` after the rows, computed in the List builder from `(all − shown)` columns: a naming variant when columns remain, a "nothing left" variant when all shown. Recomputes on `add`/`remove` follow-ups automatically (they re-call `List.call`). |
| Width-aware columns | Composer sends the scrollback width; the list handler derives a column budget that scales with width and auto-fills columns in canonical order when no `with` is given (enough to not look sparse; all on wide viewports). Explicit `with` always wins. |

## Complexity hints

| Hint | Meaning |
| --- | --- |
| `[manual]` | Operator by hand: smoke tests, cover regeneration/purge, commits. |
| `[low]` | Mechanical CSS / markup / single-file edits. |
| `[high]` | Layout restructure, inline-intro/column interaction, fx live-gating. |

## Phase index

- P0 — Reusable thin hairline
- P1 — Channel item → 180px
- P2 — Video detail refinements
- P3 — Bigger game cover (480px)
- P4 — Game detail two-column restructure
- P5 — Sidebar animation respects `/config fx`
- P6 — List table: colored added headings + dynamic addable-columns footer
- P7 — Width-aware default columns

## P0 — Reusable thin hairline

- [x] T0.1 Tune `Pito::Separator::DividerLineComponent` `hairline: true` mode to a 1px faint rule (honor `tone:`; default fainter via `bg-line-faded`). complexity: [low]
- [x] T0.2 Replace `<hr class="pito-video-detail__hairline">` in `video/detail_component.html.erb` with the hairline component; delete the `.pito-video-detail__hairline` CSS. complexity: [low]
- [x] T0.3 Update `divider_line_component_spec.rb` for the tuned hairline. complexity: [low]
- [ ] T0.4 Commit: `Reusable thin hairline via DividerLineComponent`. complexity: [manual]

## P1 — Channel item → 180px

- [x] T1.1 Change `.pito-channel-list__card` width 240px → 180px in `application.css`. complexity: [low]
- [x] T1.2 Change `.pito-game-enhanced-message__channel-grid` `minmax(240px,1fr)` → `minmax(180px,1fr)`. complexity: [low]
- [ ] T1.3 Smoke: `list channels` + `show game` grid at 180px (avatar 120, title truncates, score bar narrows, stats wrap acceptable). complexity: [manual]
- [ ] T1.4 Commit: `Channel item to 180px in list channels and enhanced grid`. complexity: [manual]

## P2 — Video detail refinements

- [x] T2.1 Collapse Views/Likes/Comments into one `·`-separated row (dim labels + values) in `video/detail_component.html.erb`. complexity: [low]
- [x] T2.2 Move the Title field out of the left fields grid into the right column, above the description. complexity: [low]
- [x] T2.3 Add a "Description" label row (`t("pito.video.detail.description")`, `text-fg-dim`) above the description in the right column. complexity: [low]
- [x] T2.4 In `video/detail.rb` builder, render the intro as a leading inline-block capped at the left-column width (480px) so it stays on the timestamp row but doesn't span the right column. complexity: [high]
- [x] T2.5 Update `.pito-video-detail__*` CSS for the revised columns + one-row stats. complexity: [low]
- [x] T2.6 Update `video/detail_component_spec.rb` (title in right column, Description label present, one-row stats). complexity: [low]
- [ ] T2.7 Commit: `Video detail: one-row stats, title + Description in right column, intro in left column`. complexity: [manual]

## P3 — Bigger game cover (480px)

- [x] T3.1 Bump `MASTER_W`/`MASTER_H` in `game/cover_art/normalizer.rb` to 480/640. complexity: [low]
- [x] T3.2 Add `DETAIL_COVER_VARIANT = { resize_to_limit: [480, 640] }` in `app/models/game.rb` (keep `COVER_VARIANT [180,240]`). complexity: [low]
- [x] T3.3 Update `normalizer_spec.rb` master-dimension example to 480×640. complexity: [low]
- [x] T3.4 Run `cover_art:regenerate`; verify covers re-attach at the new master size. complexity: [manual]
- [x] T3.5 Run `cover_art:purge_orphans`; verify 0 orphaned blobs. complexity: [manual]
- [ ] T3.6 Commit: `Regenerate game covers at 480px master for the detail card`. complexity: [manual]

## P4 — Game detail two-column restructure

- [x] T4.1 Add a `detail_cover_url` helper on `Game::DetailComponent` using `DETAIL_COVER_VARIANT`. complexity: [low]
- [x] T4.2 Restructure `game/detail_component.html.erb` into two columns — left: 480px cover then platforms, genres, themes, perspective, developer, publisher, release (this order); right: Description label + description + hairline + ScoreBar + TimeToBeat. complexity: [high]
- [x] T4.3 In `game/detail.rb` builder, constrain the intro+timestamp to the cover column width (leading inline-block, 480px), mirroring T2.4. complexity: [high]
- [x] T4.4 Update `.pito-game-detail__*` CSS for the two-column layout + 480px cover. complexity: [low]
- [x] T4.5 Update `game/detail_component_spec.rb` for the new field order and two-column structure. complexity: [low]
- [ ] T4.6 Commit: `Game detail: two-column layout, 480px cover, description + bars on the right`. complexity: [manual]

## P5 — Sidebar animation respects `/config fx`

- [x] T5.1 Add a small Stimulus controller (or extend `resume_controller.js`) that reads `fxEnabled()` from `pito/settings.js` and toggles the sidebar width-transition class. complexity: [high]
- [x] T5.2 Make the sidebar (`#pito-sidebar`, `transition-[width] duration-200` in `layouts/application.html.erb`) instant (`duration-0`/no transition) when fx is off. complexity: [low]
- [x] T5.3 Watch `#pito-settings` (MutationObserver) so a live `/config fx on|off` flips the sidebar behavior without reload. complexity: [low]
- [x] T5.4 Run `node --check` on the controller; manual smoke fx on=animated / off=snappy. complexity: [manual]
- [ ] T5.5 Commit: `Sidebar open/close respects /config fx`. complexity: [manual]

## P6 — List table: colored added headings + dynamic addable-columns footer

- [x] T6.1 Brighten added-column headings to `text-cyan` in `game/list_columns.rb` + `video/list_columns.rb` `heading_cells` (id/title stay `text-fg-faded`); the base class lives in `system_component.rb#table_heading_cells`. complexity: [low]
- [x] T6.2 Add two ~50-variant witty copy dictionaries per type in `config/locales/pito/copy/en.yml` — an addable-hint (names columns, e.g. "if your brain wants, I can also show you %{columns}") and an all-shown ("nothing left to add"), matching the `list_intro` array style. complexity: [low]
- [x] T6.3 In `game/list.rb` + `video/list.rb`, compute `addable = all_columns − shown` and append an italic footer (via the payload's after-rows `info_lines`) using the addable-hint variant, or the all-shown variant when none remain. complexity: [high]
- [x] T6.4 Confirm the footer recomputes on `add`/`remove` follow-ups (`follow_up/handlers/game_list.rb` + `video_list.rb` re-call `List.call`) — no extra wiring expected. complexity: [low]
- [x] T6.5 Specs: added-column heading is `text-cyan`; footer names the addable columns; footer flips to the "nothing left" variant when all columns are shown. complexity: [low]
- [ ] T6.6 Commit: `List table: colored added-column headings and dynamic addable-columns footer`. complexity: [manual]

## P7 — Width-aware default columns

- [x] T7.1 In `chat_form_controller.js`, read the scrollback/segment width at submit and set a hidden `viewport_width` field. complexity: [low]
- [x] T7.2 Add the `viewport_width` hidden field to the chat form in `conversations/show.html.erb`. complexity: [low]
- [x] T7.3 Thread `viewport_width` through `ChatController#create` → `enqueue_turn` → `ChatDispatchJob` → `Pito::Chat::Dispatcher` → `Pito::Chat::Handler` (new `viewport_width` reader), mirroring the existing `channel`/`period` plumbing. complexity: [high]
- [x] T7.4 In `handlers/list.rb`, when no `with` columns are given, derive a width-scaled column budget and auto-fill canonical-order columns (enough to not look sparse; all on wide viewports); explicit `with` still wins. complexity: [high]
- [x] T7.5 Specs: wide `viewport_width` auto-adds columns; narrow/absent keeps id+title; explicit `with` overrides; budget caps at all columns. complexity: [low]
- [ ] T7.6 Commit: `Width-aware default columns for list videos/games`. complexity: [manual]

## Verification

- Per phase: `bundle exec rspec` green + `bin/rubocop` clean (and `node --check` for P5 JS).
- UI phases need a manual smoke in the running app: `list channels`, `show game <id>` (detail + enhanced/channels), `show video <id>`, and toggling `/config fx on|off` then opening/closing the sidebar.
- P3 regeneration/purge are manual data ops (`cover_art:regenerate` / `cover_art:purge_orphans`) — never drop the DB; only re-attach/purge attachments.

## How to use this plan

Execute phase by phase on the current branch. One Sonnet sub-agent per atomic
task; verify before the next. Stage this plan file with each phase commit. The
intro-in-column tasks (T2.4 / T4.3) and the fx gating (T5.1) are the `[high]`
risk points — render-verify structure and smoke them before declaring done.
