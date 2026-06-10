# Unify duration formatting + add `footage` column

> Status: in progress — branch `followup-smart-link` (PR #68).

## Sign-off

- [x] Drafted
- [x] Audited — approved by user in chat (full task list shown and confirmed: "write the md file and proceed").

## North star

Video durations and game footage totals render through one formatter,
`Pito::Formatter::Duration`, producing a `DD:HH:MM:SS` string with leading
zero-units trimmed and inner units zero-padded (`9:34`, `2:00:00`,
`1:03:05:09`). `list games with footage` shows a right-aligned **Footage**
column (total of the game's footage durations); `list videos with duration`
shows a right-aligned **Duration** column. Both columns are `tabular-nums` and
capped at 11ch (`00:00:00:00`, covers `99:23:59:59`).

## Locked decisions

| Topic                | Decision                                                                                  |
| -------------------- | ----------------------------------------------------------------------------------------- |
| Format               | `DD:HH:MM:SS`, trim leading zero-units, pad inner units to 2 digits (e.g. `1:03:05:09`).  |
| Minimum unit         | Always at least `M:SS` (e.g. 34s → `0:34`). Seconds always 2 digits.                      |
| Blank/negative input | Formatter returns `nil`.                                                                  |
| Formatter home       | `Pito::Formatter::Duration` — replaces `Pito::Video::DurationFormat` (single formatter).  |
| Footage source       | `game.footages.sum(:duration_seconds)`; `—` when a game has no footage.                   |
| Column width         | Both columns capped at 11ch via `.pito-cell-duration`; right-aligned; `tabular-nums`.     |
| games footage place  | Trailing fixed column (after Release/Year), included in `fixed_trailing`.                 |
| videos duration      | Right-aligned + clamped within its existing (`1fr`) column slot; heading right-aligned.   |
| Branch               | `followup-smart-link` (PR #68). Do NOT merge — hold for the user's manual validation.     |

## Phase index

- P0 — Unified duration formatter (`Pito::Formatter::Duration`).
- P1 — `list games` footage column.
- P2 — `list videos` duration column alignment + clamp.

## P0 — Unified duration formatter

- [x] T0.1 Create `app/services/pito/formatter/duration.rb` — `call(seconds)` returns `DD:HH:MM:SS` (trim leading zero-units, pad inner units to 2, min `M:SS`); `nil` for blank/negative. complexity: [low]
- [x] T0.2 Point the `:duration` value proc in `app/services/pito/message_builder/video/list_columns.rb` at `Pito::Formatter::Duration.call`. complexity: [low]
- [x] T0.3 Point `app/components/pito/video/detail_component.rb` (duration helper) at `Pito::Formatter::Duration.call`. complexity: [low]
- [x] T0.4 Delete `app/services/pito/video/duration_format.rb`. complexity: [low]
- [x] T0.5 Add `spec/services/pito/formatter/duration_spec.rb` — port existing `M:SS`/`H:MM:SS` cases + add days and padding cases. complexity: [low]
- [x] T0.6 Delete `spec/services/pito/video/duration_format_spec.rb`. complexity: [low]
- [x] T0.7 Run `bundle exec rspec` (duration_spec + video list_columns + video detail) and `bin/rubocop`; green. complexity: [low]
- [x] T0.8 Commit: `unify duration formatting into Pito::Formatter::Duration (DD:HH:MM:SS)`. complexity: [manual]

## P1 — `list games` footage column

- [ ] T1.1 Add `.pito-cell-duration { max-width: 11ch; overflow-wrap: break-word; }` to `app/assets/tailwind/application.css` after `.pito-cell-channel`. complexity: [low]
- [ ] T1.2 Add `footage` entry to `Game::ListColumns::COLUMNS` (aliases `%w[footage]`, heading "Footage", `align: :right`, `cell_class: "text-fg-dim text-right tabular-nums pito-cell-duration"`, value = `Pito::Formatter::Duration.call` of footages-sum or `—`), placed after `year`. complexity: [low]
- [ ] T1.3 Add `footage` to `Game::ListColumns` `SORT_SPECS` (key = footages duration sum, `requires_with: true`) and `SORT_VOCAB` (`"footage" => :footage`). complexity: [low]
- [ ] T1.4 Eager-load `:footages` in `app/services/pito/chat/handlers/list.rb` when `columns.include?(:footage)`. complexity: [low]
- [ ] T1.5 Add `:footage` to the `fixed_trailing` set in `app/services/pito/message_builder/game/list.rb`. complexity: [low]
- [ ] T1.6 Add `col_footage_desc` under `pito.copy.list.games_help` in `config/locales/pito/copy/en.yml`. complexity: [low]
- [ ] T1.7 Run `bin/rails tailwindcss:build`; confirm `.pito-cell-duration` is in the built CSS. complexity: [low]
- [ ] T1.8 Update `spec/services/pito/message_builder/game/list_columns_spec.rb` + `game/list_spec.rb` for footage (cells/heading/vocabulary/sort/canonical-order/fixed_trailing). complexity: [low]
- [ ] T1.9 Run `bundle exec rspec` (game list specs) + `bin/rubocop`; green. complexity: [low]
- [ ] T1.10 Commit: `list games: footage column (total footage duration, right-aligned)`. complexity: [manual]

## P2 — `list videos` duration column alignment + clamp

- [ ] T2.1 Add `heading_cells(cols)` to `Video::ListColumns` (mirrors game: `align: :right` → `{ "text" =>, "class" => "text-right" }`, else plain String). complexity: [low]
- [ ] T2.2 Add `align: :right` + `cell_class: "text-fg-dim text-right tabular-nums pito-cell-duration"` to the video `:duration` COLUMNS entry. complexity: [low]
- [ ] T2.3 Switch the extra-columns heading in `app/services/pito/message_builder/video/list.rb` from `ListColumns.headings(cols)` to `ListColumns.heading_cells(cols)`. complexity: [low]
- [ ] T2.4 Update `spec/services/pito/message_builder/video/list_columns_spec.rb` + `video/list_spec.rb` for duration heading/cell alignment. complexity: [low]
- [ ] T2.5 Run full `bundle exec rspec` + `bin/rubocop`; green. complexity: [low]
- [ ] T2.6 Commit: `list videos: right-align + clamp duration column`. complexity: [manual]
