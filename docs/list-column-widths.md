# Clamp the list Title column so long titles wrap

> Status: Ready — execute on branch `followup-smart-link`.

## Sign-off

- [x] Drafted — 2026-06-10
- [x] Audited — 2026-06-10 (approved by user in chat)

## North star

In `list games` and `list videos`, the **Title** column stops expanding to fit the
widest title. Titles longer than ~34 characters **word-wrap to a second line**, so
short titles no longer leave huge gaps and long titles stay readable. No other
tables are affected.

## Locked decisions

| Topic     | Decision                                                                                                                                                                  |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Mechanism | Clamp the title **cell** (`max-width` + wrap), NOT the shared grid — this caps the column's `max-content` track with zero blast radius on other `.pito-data-grid` tables. |
| Cap       | `34ch` (monospace) — fits "Ghosts 'n Goblins Resurrection" (~30 chars) on one line; longer titles wrap.                                                                   |
| Scope     | The game-list and video-list **title** cells only.                                                                                                                        |
| Branch    | `followup-smart-link` (the PR #68 branch, per user).                                                                                                                      |

## Complexity hints

| Hint       | Meaning                                           |
| ---------- | ------------------------------------------------- |
| `[low]`    | mechanical / single-file / pattern-following edit |
| `[manual]` | operator: verification runs, commits              |

## Phase index

- P0 — Clamp the Title column (games + videos)

## P0 — Clamp the Title column (games + videos)

- [x] T0.1 Add `.pito-cell-title { max-width: 34ch; overflow-wrap: break-word; }` to `app/assets/tailwind/application.css`. complexity: [low]
- [x] T0.2 Append `pito-cell-title` to the game-title cell class in `app/services/pito/message_builder/game/list.rb`. complexity: [low]
- [x] T0.3 Append `pito-cell-title` to the video-title cell class in `app/services/pito/message_builder/video/list.rb`. complexity: [low]
- [x] T0.4 Run `bundle exec rails tailwindcss:build`; confirm `.pito-cell-title` is in `app/assets/builds/tailwind.css`. complexity: [low]
- [x] T0.5 Add specs asserting the title cell carries `pito-cell-title` (game + video list builder specs). complexity: [low]
- [x] T0.6 Run `bundle exec rspec` (list builder specs) + `bin/rubocop`; confirm green. complexity: [manual]
- [x] T0.7 Commit: `clamp list Title column width so long titles wrap`. complexity: [manual]
