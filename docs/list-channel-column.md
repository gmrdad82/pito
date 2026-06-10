# Channel column: cyan + clamp to longest-handle width

> Status: in progress — branch `followup-smart-link` (PR #68).

## Sign-off

- [x] Drafted
- [x] Audited — approved by user in chat ("yes to all 3").

## North star

In `list games` and `list videos`, the channel column (`channel` for videos,
`channels` for games) is colored cyan and width-capped to the longest @handle +
1 character, so handles never widen the column past what they need.

## Locked decisions

- Cap = **15ch** = longest live @handle (14 chars: `@manfysurvival`/
  `@manfystrategy`/`@manfyfighting`) + 1.
- Cyan via the theme utility class `text-cyan` (already in the Tailwind build;
  used across views/components).
- Clamp via a new custom CSS class `.pito-cell-channel` in `application.css`,
  mirroring the existing `.pito-cell-title`.
- Cells carry both classes together: `"text-cyan pito-cell-channel"`.
- Work stays on `followup-smart-link` (PR #68). Do NOT merge — hold for the
  user's manual validation.

## Phase index

- Phase 1 — Implement (CSS + per-column cell_class for both list_columns).
- Phase 2 — Specs + verify + commit.

## Phase 1 — Implement

- [x] T1.1 Add `.pito-cell-channel { max-width: 15ch; overflow-wrap: break-word; }` to `app/assets/tailwind/application.css` after `.pito-cell-title`. complexity: [low]
- [x] T1.2 In `Video::ListColumns.cells`, honor a per-column `cell_class:` override (fall back to `"text-fg-dim"`). complexity: [low]
- [x] T1.3 Give the video `:channel` COLUMNS entry `cell_class: "text-cyan pito-cell-channel"`. complexity: [low]
- [x] T1.4 In `Game::ListColumns.cells`, honor a per-column `cell_class:` override (fall back to the existing align-based class). complexity: [low]
- [x] T1.5 Give the game `:channels` COLUMNS entry `cell_class: "text-cyan pito-cell-channel"`. complexity: [low]
- [x] T1.6 Run `bin/rails tailwindcss:build`; confirm `.pito-cell-channel` is in the built CSS. complexity: [low]
- [x] T1.7 Commit: `channel column: cyan + clamp to longest-handle width` [manual]

## Phase 2 — Specs + verify

- [ ] T2.1 Update `video/list_columns_spec.rb`: `:channel` cell class is `"text-cyan pito-cell-channel"`. complexity: [low]
- [ ] T2.2 Update `game/list_columns_spec.rb`: `:channels` cell class is `"text-cyan pito-cell-channel"`. complexity: [low]
- [ ] T2.3 Run `bundle exec rspec` (the two list_columns specs) + `bin/rubocop`; green. complexity: [low]
- [ ] T2.4 Commit: `specs: channel column cyan + clamp` [manual]
