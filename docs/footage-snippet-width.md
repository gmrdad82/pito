# Footage snippet: hug-content width + muted copy hint

> Status: in progress — branch `footage-snippet-width`.

## Sign-off

- [x] Drafted
- [x] Audited — approved by user in chat (screenshot + "tweak the length of the code block… alt+c copy align to its end… 'to copy' has to be muted").

## North star

The footage probe-command block hugs the command text (no trailing whitespace)
but never overflows the message — when the command is wider than the message it
caps at the message width and scrolls horizontally (as today). The `alt+c to
copy` hint aligns to the block's right edge, and `to copy` renders muted
(`text-fg-dim`) while `alt+c` stays the canonical yellow shortcut.

## Locked decisions

| Topic       | Decision                                                                                            |
| ----------- | --------------------------------------------------------------------------------------------------- |
| Block width | `.pito-footage-import { width: fit-content; max-width: 100% }` — hug content, cap at message width. |
| Overflow    | Move `overflow-x-auto pito-hide-scrollbar` from `<code>` onto the padding div (block scroller).     |
| Hint align  | Hint stays `text-right` inside the now-shrunk wrapper → aligns to the block's right edge.           |
| Muted hint  | Render via `Pito::Keybinding::HintComponent` (shortcut `alt+c` yellow + description `to copy` dim). |
| i18n        | Split `copy_hint: "alt+c to copy"` → `copy_shortcut: "alt+c"` + `copy_hint: "to copy"`.             |
| Branch      | New branch `footage-snippet-width`; PR, hold for the user's validation.                             |

## Phase index

- P0 — Width + muted-hint fix (CSS, template, i18n) + spec.

## P0 — Snippet width + muted hint

- [x] T0.1 Add `.pito-footage-import { width: fit-content; max-width: 100%; }` to the footage block in `app/assets/tailwind/application.css`. complexity: [low]
- [x] T0.2 In `probe_command_component.html.erb`, move `overflow-x-auto pito-hide-scrollbar` from the `<code>` to the `.py-2 px-3` padding div (keep `whitespace-nowrap` on the code). complexity: [low]
- [x] T0.3 In the same template, replace the `text-yellow` hint `<div>` with a `text-right mt-1` div rendering `Pito::Keybinding::HintComponent.new(shortcut: …copy_shortcut, description: …copy_hint)`. complexity: [low]
- [x] T0.4 Split the i18n in `config/locales/pito/footage/en.yml`: add `copy_shortcut: "alt+c"` and change `copy_hint` to `"to copy"`. complexity: [low]
- [x] T0.5 Run `bin/rails tailwindcss:build`; confirm the build still has the footage rule. complexity: [low]
- [x] T0.6 Update `spec/components/pito/footage/probe_command_component_spec.rb`: hint renders `alt+c` (shortcut) + a `text-fg-dim` `to copy`; assert no all-yellow hint. complexity: [low]
- [x] T0.7 Run `bundle exec rspec` (component spec) + `bin/rubocop` + `node --check` if any JS; green. complexity: [low]
- [x] T0.8 Commit: `footage snippet: hug-content width + muted copy hint`. complexity: [manual]
