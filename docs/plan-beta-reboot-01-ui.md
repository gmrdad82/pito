# pito — Static UI Plan (Plan 1)

> Status: draft. Comes after `plan-beta-reboot.md` (Plan 0).
> Static UI only — no wiring, no Cable, no Stimulus, no commands.
> Tasks are atomic (≤5 min each). Check off as you go. Re-open scope
> only after a phase commit lands.

## Sign-off

- [x] Drafted — 2026-05-27
- [x] Audited — 2026-05-27

## North star

Plan 0 leaves the Rails 8 app reset to defaults: gems culled, schema rebuilt, Tailwind installed, ViewComponent baseline in place, locales scaffolded. Plan 1 builds the **static visual chassis** on top of that reset — the four screens designed during the v0 phase (chat shell, start screen, palette overlays, sidebar overlay), implemented as ViewComponents with Tailwind tokens and i18n copy.

No behavior. No Stimulus controllers. No Action Cable. No command router. No real data. Hardcoded sample messages throughout. Dummy routes are fine — they exist so you can visit `/`, `/start`, `/_ui/palettes`, `/_ui/sidebar` and see what the future app will look like.

Plan 2+ will layer wiring (Stimulus, Cable, commands, persistence, auth). Plan 1 produces the chassis those plans wire up.

## Supersedes from Plan 0

| Plan 0 reference | Plan 0 says | Plan 1 supersedes with |
|---|---|---|
| P9.7 | `font-size: 13px`, `line-height: 1` | `font-size: 16px`, `line-height: 1.4` |
| P9.6 | `ui-monospace, "Cascadia Code", "JetBrains Mono", Menlo, Consolas, monospace` | `ui-monospace, monospace` only (no web fonts, no `@font-face`) |
| P9.5 | "Tokyo Night palette as CSS custom properties" (no hex enumerated) | Exhaustive named tokens defined in U1 below, including `pito-blue` `#5170ff` |
| P10 + P11 | Component list (`HeaderComponent`, `FooterComponent`, `Event::TextLine/Table/Error/Progress`) and shell layout (header + scrollback + input) | Full v0-aligned inventory (see Component Inventory section) and shell layout (scroll area + bottom row only — no header, no footer) |

P0–P8 and P12–P19 of Plan 0 are unaffected. Plan 0 stands as written; Plan 1 layers on top.

## Locked decisions

Carry forward from Plan 0:

| Topic | Decision |
|---|---|
| UI stack | Turbo + Stimulus + importmap-rails (zero node) — Plan 1 uses none of these yet |
| CSS | `tailwindcss-rails` (standalone CLI, zero node) |
| Components | `view_component`, no Lookbook |
| Brand | `pito` lowercase except sentence start |
| i18n | All copy in `config/locales/**/en.yml` |

New for Plan 1:

| Topic | Decision |
|---|---|
| Typography | `font-size: 16px`, `line-height: 1.4`, `font-family: ui-monospace, monospace`. No web fonts, no Google Fonts, no `@font-face`. Single font-size everywhere — no `text-sm`, `text-lg`, `text-xl`. |
| Color tokens | Full Tokyo Night palette + `pito-blue` `#5170ff`, exposed as CSS custom properties scoped under `[data-theme="tokyo-night"]` |
| Theme system | `data-theme` attribute on `<html>`. CSS vars per theme. Tokyo Night is Plan 1's only theme; adding others (catppuccin, gruvbox) means adding a `[data-theme="..."]` CSS block with the same var names — no Ruby or template changes |
| Visual primitive | Bar + gap + content pattern: 4px colored (or transparent) bar + 6px gap (shows root bg) + content area with internal padding `10px 16px 10px 12px`. The bar always renders (transparent when no border color) so borderless content aligns horizontally with bordered content. Used by every segment AND the chatbox. |
| Component namespace | `Pito::*` (continuing Plan 0's convention) |
| Copy | All user-facing strings via `t(".key")` in components. No inline strings. Locale files organized as `config/locales/pito/<area>/en.yml`. |
| Sample data | Hardcoded sample content in `lib/pito/sample/` or controllers, clearly marked as `SAMPLE` so production wiring later replaces it without confusion |
| Routes | `/` and `/start` are real production routes. `/_ui/palettes` and `/_ui/sidebar` are review-only — production removes them (palettes and sidebar become overlays opened via interaction in Plan 2+) |
| New gems | None beyond Plan 0's locked set. Vanilla Tailwind + ViewComponent only. No markdown renderer, no syntax highlighter, no animation library. |

## Reference materials

Read these while executing Plan 1 — they are the visual contract:

- `docs/ui/ui-p1.md` → `ui-p1.5.md` — chat shell evolution (final form at `ui-p1.5.md`)
- `docs/ui/ui-p2.md` + `ui-p2.1.md` — start screen
- `docs/ui/ui-p3.md` — slash + Ctrl+P palettes
- `docs/ui/ui-p4.md` + `ui-p4.1.md` — sidebar overlay (overlay pattern, not side-by-side)
- `tmp/v0-snapshots/v0.zip` — final v0 render snapshot (visual cross-reference)

## Complexity hints

Same as Plan 0:

| Hint | When |
|---|---|
| `[manual]` | You, by hand — branches, commits, visual review, design choices |
| `[low]` | YAML, renames, file audits, locale entries, single-file ViewComponents, small ERB templates, controllers |
| `[medium]` | Multi-file refactors, layout files, CSS architecture |
| `[high]` | Architecture decisions (rare in Plan 1; mostly token system) |

## Tokens & theme system

In `app/assets/tailwind/application.css`, define one theme block. All CSS custom properties live under the theme's `[data-theme="..."]` selector. The `<html>` element carries `data-theme="tokyo-night"` by default.

```css
[data-theme="tokyo-night"] {
  --bg-root:         #1a1b26;
  --bg-surface:      #1f2335;
  --bg-elevated:     #24283b;
  --border-default:  #292e42;
  --border-faded:    #414868;
  --fg-default:      #c0caf5;
  --fg-dim:          #565f89;
  --fg-faded:        #414868;
  --accent-purple:   #bb9af7;
  --accent-blue:     #7aa2f7;
  --accent-cyan:     #7dcfff;
  --accent-green:    #9ece6a;
  --accent-yellow:   #e0af68;
  --accent-orange:   #ff9e64;
  --accent-red:      #f7768e;
  --brand-pito:      #5170ff;
}
```

Tailwind utility aliases (extend `theme.extend.colors` in `tailwind.config.js`, or use the `@theme` block in Tailwind 4):

| Utility name | CSS var |
|---|---|
| `bg-root`, `bg-surface`, `bg-elevated` | `--bg-*` |
| `border-line-default`, `border-line-faded` | `--border-*` (TW4 @theme strips `--color-line-` prefix, producing `border-line-*`) |
| `text-fg`, `text-fg-dim`, `text-fg-faded` | `--fg-*` |
| `text-purple`, `text-blue`, `text-cyan`, `text-green`, `text-yellow`, `text-orange`, `text-red` | `--accent-*` |
| `bg-purple`, `bg-orange` (etc.) | `--accent-*` |
| `text-pito`, `bg-pito` | `--brand-pito` |

Adding a new theme (future, not Plan 1 scope): drop another `[data-theme="catppuccin-mocha"] { ... }` block with the same var names. Theme switching (Plan 2+) flips the attribute and persists in `localStorage`.

## Component inventory & specs

Every component below is a static renderer — no Stimulus, no state, no JS. All copy via i18n.

### Pito::Segment::Component

- Path: `app/components/pito/segment/component.{rb,html.erb}`
- Args: `border:` (color CSS var name or hex or `nil`), `background:` (color CSS var name or hex or `nil`)
- Slots: default content slot
- i18n keys: none
- Markup: flex row, `align-items: stretch`
  - Child 1 — bar: `<div>` 4px wide, full height, background = `border` (or transparent when `nil`)
  - Child 2 — gap: 6px wide, transparent (shows root bg)
  - Child 3 — content: `flex: 1`, `min-width: 0`, padding `10px 16px 10px 12px`. Background = `background` color (only this child has it — NOT the outer wrapper, so the gap shows root bg even when the content has a fill)
- v0 reference: `ui-p1.3.md` + `ui-p1.4.md` + `ui-p1.5.md`
- Dependencies: none
- Invariant: the bar always renders (transparent when no `border`). This keeps borderless content horizontally aligned with bordered content. Total text-from-segment-edge offset is always `bar (4) + gap (6) + content-left-padding (12) = 22px`.

### Pito::Cursor::Component

- Path: `app/components/pito/cursor/component.{rb,html.erb}`
- Args: `char:` (single character), `color:` (default `var(--accent-purple)`)
- Slots: none
- i18n keys: none
- Markup: `<span>` containing the character, styled with `background: <color>; color: var(--bg-root);`. Inline-block, exactly one character wide.
- v0 reference: inverted-character cursor technique discussed after `ui-p1.5.md`
- Dependencies: none

### Pito::Shell::ChatboxComponent

- Path: `app/components/pito/shell/chatbox_component.{rb,html.erb}`
- Args: `state:` (`:default` or `:start`), `placeholder_key:` (i18n key), `filter:` (optional hash `{ channel:, period: }` — required when `state == :default`)
- Slots: none
- i18n keys: `pito.shell.chatbox.placeholder.*`, `pito.shell.chatbox.filter.channel_label`, `pito.shell.chatbox.filter.period_label`
- Markup: wraps `Pito::Segment::Component` with `border: var(--accent-purple), background: var(--bg-surface)`. Inside content area, a flex column:
  - Line 1: `Pito::Cursor::Component` rendering first character of placeholder + remainder of placeholder in `text-fg-dim`
  - Line 2 (only if `state == :default`): filter context — `Channel:` label dim, channel value in `text-cyan`, ` · `, `Period:` label dim, period value in `text-cyan`. 10px breathing room above this line.
- v0 reference: `ui-p1.5.md`
- Dependencies: `Pito::Segment::Component`, `Pito::Cursor::Component`

### Pito::Shell::MiniStatusComponent

- Path: `app/components/pito/shell/mini_status_component.{rb,html.erb}`
- Args: `mode:` (`:connection` or `:authentication`), `state:` (`true`/`false` — connected/disconnected OR authenticated/not_authenticated), `notifications:` (int, default `0`), `show_notifications:` (bool, default `true`)
- Slots: none
- i18n keys: `pito.shell.mini_status.connected`, `.disconnected`, `.authenticated`, `.not_authenticated`, `.notifications_count`, `.commands_hint`, `.commands_label`
- Markup: single flex row, right-aligned. Children:
  - Status word — `Connected`/`Authenticated` in `text-green` when `state == true`, `Disconnected`/`Not authenticated` in `text-red` when `false`
  - Optional ` · N notifications` in `text-cyan` (only when `show_notifications` and `notifications > 0`)
  - ` · ctrl+p` in `text-yellow font-bold`
  - `commands` in `text-fg-dim`
  - All ` · ` separators in `text-fg-dim`
- v0 reference: `ui-p1.2.md` (chat shell variant) + `ui-p2.1.md` (start screen variant)
- Dependencies: none

### Pito::Shell::PostCommandDotsComponent

- Path: `app/components/pito/shell/post_command_dots_component.{rb,html.erb}`
- Args: none (static animated indicator)
- Slots: none
- i18n keys: none (pure glyph)
- Markup: a row of 8 `·` (middle-dot) characters in `text-fg-dim`. CSS animation sweeps a brighter highlight (3-dot subset in `text-cyan`) left-to-right via `@keyframes` on `mask-position` or `background-position`. 1.4s loop, infinite. Pure CSS, no JS.
- v0 reference: `ui-p1.4.md`
- Dependencies: none

### Pito::Shell::InProgressComponent

- Path: `app/components/pito/shell/in_progress_component.{rb,html.erb}`
- Args: `verb_key:` (i18n key, default `pito.shell.in_progress.default_verb` → `"Building"`)
- Slots: none
- i18n keys: `pito.shell.in_progress.default_verb` (caller may pass other keys)
- Markup: wraps `Pito::Segment::Component` with `border: nil, background: nil` (borderless — content aligns with other segments). Inside:
  - Braille spinner glyph (cyan) — CSS animation cycles through `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` via `@keyframes` with `steps(10)` over ~1s. If browser support for animating `content` is unreliable, fall back to opacity pulse on a static `⠋`.
  - Space + verb with CSS shimmer (`background-clip: text` + moving linear-gradient between `var(--fg-default)` and `var(--accent-cyan)`, 2s loop)
  - Trailing `…` in `text-fg-dim`
- v0 reference: `ui-p1.4.md`
- Dependencies: `Pito::Segment::Component`

### Pito::Event::UserMessageComponent

- Path: `app/components/pito/event/user_message_component.{rb,html.erb}`
- Args: `body_key:` (i18n key) OR `body:` (raw string — used for sample message bodies)
- Slots: none (use `body_key` for production; `body` for `lib/pito/sample/`)
- i18n keys: provided by caller (`body_key`)
- Markup: wraps `Pito::Segment::Component` with `border: var(--accent-orange), background: nil`. Content is the body text in `text-fg`.
- v0 reference: `ui-p1.5.md`
- Dependencies: `Pito::Segment::Component`

### Pito::Event::AssistantTextComponent

- Path: `app/components/pito/event/assistant_text_component.{rb,html.erb}`
- Args: `body_key:` OR `body:`
- Slots: optional `content` slot for richer markup
- i18n keys: provided by caller
- Markup: wraps `Pito::Segment::Component` with `border: nil, background: nil`. Content in `text-fg`. May contain inline highlights via small helper spans (`text-yellow font-bold` for keywords, `text-cyan` for code-like inline tokens). Multi-paragraph supported via `<p>` tags with vertical spacing.
- v0 reference: `ui-p1.5.md`
- Dependencies: `Pito::Segment::Component`

### Pito::Event::ThoughtComponent

- Path: `app/components/pito/event/thought_component.{rb,html.erb}`
- Args: `duration:` (string, e.g., `"8.2s"`)
- Slots: none
- i18n keys: `pito.event.thought.prefix`
- Markup: wraps `Pito::Segment::Component` with `border: nil, background: nil`. Content: `+ Thought:` in `text-orange font-bold`, then space, then duration in `text-fg-dim`.
- v0 reference: `ui-p1.5.md`
- Dependencies: `Pito::Segment::Component`

### Pito::Event::ToolOutputComponent

- Path: `app/components/pito/event/tool_output_component.{rb,html.erb}`
- Args: `title_key:` (i18n key), `command:` (string), `output:` (multi-line string)
- Slots: none
- i18n keys: title via `title_key`, `pito.event.tool_output.click_to_expand`, `pito.event.tool_output.click_to_collapse`
- Markup: wraps `Pito::Segment::Component` with `border: var(--accent-purple), background: var(--bg-elevated)`. Content:
  - Title line: `# <title>` in `text-fg-dim`
  - Empty line (visual gap)
  - Command line in `text-cyan`
  - Empty line
  - Pre-formatted output block in `text-fg` (`<pre>` to preserve column alignment)
  - "Click to expand" affordance in `text-fg-dim` (with `hover:underline` Tailwind utility for visual cue — no actual click handler in Plan 1)
- v0 reference: `ui-p1.5.md` + expandable behavior notes
- Dependencies: `Pito::Segment::Component`

### Pito::Event::StatusFooterComponent

- Path: `app/components/pito/event/status_footer_component.{rb,html.erb}`
- Args: `mode:` (string, e.g., `"Build"`), `agent:` (string, e.g., `"Big Pickle"`), `duration:` (string, e.g., `"1m 3s"`)
- Slots: none
- i18n keys: none (values passed by caller)
- Markup: wraps `Pito::Segment::Component` with `border: nil, background: nil`. Content: small square `▣` in `text-cyan`, then space, then mode in `text-purple font-bold`, then ` · <agent> · <duration>` in `text-fg-dim`.
- v0 reference: `ui-p1.5.md`
- Dependencies: `Pito::Segment::Component`

### Pito::StartScreen::Component

- Path: `app/components/pito/start_screen/component.{rb,html.erb}`
- Args: `version:` (string, e.g., `"0.1.0"`), `pitomd_url:` (default `"https://pitomd.com"`)
- Slots: optional `logo` slot — caller fills in their logo asset. Plan 1 leaves this empty. Logo asset and treatment are out of scope.
- i18n keys: `pito.start_screen.tip_placeholder`, `pito.start_screen.tip_prefix`
- Markup: full-viewport flex column. Layout:
  - Empty top region
  - Centered group (chatbox vertically centered at 50vh):
    - Logo slot (placeholder — leave a reserved vertical space, ~120px, for the future logo asset). Centered horizontally.
    - 32px gap
    - `Pito::Shell::ChatboxComponent` with `state: :start`, `max-width: 800px`, centered horizontally
    - `Pito::Shell::MiniStatusComponent` with `mode: :authentication, state: false, show_notifications: false`, right-aligned within the same 800px container
  - Tip line: centered horizontally, positioned roughly midway between the mini-status row and the bottom corners. `● Tip — [placeholder for tip dictionary]`, with `●` and `Tip` in `text-yellow font-bold`, separator dim, content dim.
  - Bottom-left of viewport: `pitomd.com` `<a>` link in `text-fg-dim` with `hover:underline`, 16px padding from edges
  - Bottom-right of viewport: version string in `text-fg-dim`, 16px padding from edges
- v0 reference: `ui-p2.1.md` + later centering tweaks
- Dependencies: `Pito::Shell::ChatboxComponent`, `Pito::Shell::MiniStatusComponent`

### Pito::Palette::Slash::Component

- Path: `app/components/pito/palette/slash/component.{rb,html.erb}`
- Args: `commands:` (array of hashes `{ verb:, description_key: }`), `selected_index:` (int, default `0`), `typed:` (string, default `"/"` — the typed buffer to echo)
- Slots: none
- i18n keys: each item's `description_key`
- Markup: wraps `Pito::Segment::Component` with `border: var(--accent-purple), background: var(--bg-surface)`. Content area:
  - Command list, one row per command. Format: `/<verb>` in `text-fg`, padded with spaces to column 20, then description in `text-fg-dim`. Selected row has background `var(--border-default)` spanning the full content row width.
  - 8px gap
  - 1px horizontal divider in `var(--border-default)` spanning the content area width
  - 8px gap
  - Input echo line: `Pito::Cursor::Component` on the first character of `typed`, remainder of `typed` in `text-fg`
- max-height: `min(60vh, 320px)`, `overflow-y: auto`
- v0 reference: `ui-p3.md`
- Dependencies: `Pito::Segment::Component`, `Pito::Cursor::Component`

### Pito::Palette::CtrlP::Component

- Path: `app/components/pito/palette/ctrl_p/component.{rb,html.erb}`
- Args: `sections:` (array of hashes `{ title_key:, items: }`, each item `{ label_key:, shortcut: }`), `selected_section_index:` (int, default `0`), `selected_item_index:` (int, default `0`)
- Slots: none
- i18n keys: `pito.palette.ctrl_p.title`, `.esc_hint`, `.search_placeholder`, plus each section's `title_key` and each item's `label_key`
- Markup: centered modal box, `max-width: 600px`, `background: var(--bg-surface)`, 1px border `var(--border-default)`, 24px internal padding on all sides. No rounded corners. No shadow.
  - Title row (flex justify-between): "Commands" in `text-fg font-bold` left, "esc" in `text-fg-dim` right
  - 12px gap
  - Search input: `Pito::Cursor::Component` on `S` (with `color: var(--accent-blue)` — NOT purple here, blue distinguishes search from command input), then `earch` in `text-fg-dim`. 1px bottom border in `var(--border-default)` spanning the input width.
  - 16px gap
  - One `Pito::Palette::CtrlP::SectionComponent` per section
  - max-height: `min(80vh, 600px)`, `overflow-y: auto`
  - Selected row highlight: 8px inset from modal interior left and right edges (NOT edge-to-edge)
- v0 reference: `ui-p3.md`
- Dependencies: `Pito::Cursor::Component`, `Pito::Palette::CtrlP::SectionComponent`

### Pito::Palette::CtrlP::SectionComponent

- Path: `app/components/pito/palette/ctrl_p/section_component.{rb,html.erb}`
- Args: `title_key:`, `items:` (array `{ label_key:, shortcut: }`), `selected_index:` (int or `nil` — index of currently-selected item within this section)
- Slots: none
- i18n keys: title via `title_key`, each item's label via `label_key`
- Markup: section title in `text-orange font-bold`, 4px margin below. List of item rows. Each row: flex justify-between, 2px vertical padding, label left in `text-fg`, shortcut right in `text-fg-dim`. Selected row (when `selected_index == this row's index`) has background `var(--border-default)`, 8px inset from edges of the section content.
- 12px gap below the section's last row
- Dependencies: none

### Pito::Sidebar::Component

- Path: `app/components/pito/sidebar/component.{rb,html.erb}`
- Args: `title:` (string), `subtitle_key:` (i18n key, e.g., `pito.sidebar.game.subtitle`), `subtitle_args:` (hash for interpolation, e.g., `{ date: "2026-05-18" }`)
- Slots: `body` (the scrollable content — caller renders section components inside)
- i18n keys: `pito.sidebar.esc_hint`, subtitle via `subtitle_key`
- Markup: `<aside>` with `position: fixed; right: 0; top: 0; bottom: 0; width: 480px; background: var(--bg-root); border-left: 1px solid var(--border-default); z-index: 10`. Flex column, `overflow: hidden` on the aside itself.
  - Sticky header (`flex: 0 0 auto`, 16px padding, 1px bottom border `var(--border-default)`):
    - Title block (left): line 1 = `title` in `text-cyan font-bold`; line 2 = `t(subtitle_key, **subtitle_args)` in `text-fg-dim`
    - Right (aligned with line 1 via flex justify-between): "esc" in `text-fg-dim`
  - Scrollable body (`flex: 1 1 auto`, `overflow-y: auto`, 16px padding): renders the `body` slot
- v0 reference: `ui-p4.md` + `ui-p4.1.md` (overlay pattern)
- Dependencies: none (consumers fill body with `Pito::Sidebar::SectionComponent` instances)

### Pito::Sidebar::SectionComponent

- Path: `app/components/pito/sidebar/section_component.{rb,html.erb}`
- Args: `title_key:` (i18n key)
- Slots: default content slot
- i18n keys: title
- Markup: section title in `text-orange font-bold` (4px bottom margin), then the content slot. 24px bottom margin to separate from next section.
- Dependencies: none

## Route inventory

| Path | Controller#action | Purpose | Production? |
|---|---|---|---|
| `/` | `terminal#show` | Chat shell with hardcoded sample messages | Yes |
| `/start` | `start_screens#show` | Start screen for unauthenticated entry | Yes |
| `/_ui/palettes` | `_ui/palettes#show` | Review page rendering both palette designs | No — removed in Plan 2+ |
| `/_ui/sidebar` | `_ui/sidebar#show` | Review page rendering chat shell + sidebar overlay | No — production opens sidebar via interaction |

`/_ui/*` routes are grouped under one namespace so they're easy to grep and remove later.

## i18n key tree

Files live under `config/locales/pito/`. One file per area, English baseline.

```
config/locales/pito/
├── shell/en.yml
│   pito.shell.chatbox.placeholder.default          "Ask anything..."
│   pito.shell.chatbox.placeholder.start_with_code  "/authenticate 123456"
│   pito.shell.chatbox.placeholder.start_interactive "/authenticate"
│   pito.shell.chatbox.placeholder.authenticated_hint "List top videos"
│   pito.shell.chatbox.filter.channel_label          "Channel:"
│   pito.shell.chatbox.filter.period_label           "Period:"
│   pito.shell.mini_status.connected                 "Connected"
│   pito.shell.mini_status.disconnected              "Disconnected"
│   pito.shell.mini_status.authenticated             "Authenticated"
│   pito.shell.mini_status.not_authenticated         "Not authenticated"
│   pito.shell.mini_status.notifications_count       "%{count} notifications"
│   pito.shell.mini_status.commands_hint             "ctrl+p"
│   pito.shell.mini_status.commands_label            "commands"
│   pito.shell.in_progress.default_verb              "Building"
│
├── event/en.yml
│   pito.event.thought.prefix                        "+ Thought:"
│   pito.event.tool_output.click_to_expand           "Click to expand"
│   pito.event.tool_output.click_to_collapse         "Click to collapse"
│
├── start_screen/en.yml
│   pito.start_screen.tip_prefix                     "Tip"
│   pito.start_screen.tip_placeholder                "[placeholder for tip dictionary]"
│
├── palette/en.yml
│   pito.palette.ctrl_p.title                        "Commands"
│   pito.palette.ctrl_p.esc_hint                     "esc"
│   pito.palette.ctrl_p.search_placeholder           "Search"
│   pito.palette.ctrl_p.sections.suggested           "Suggested"
│   pito.palette.ctrl_p.sections.session             "Session"
│   pito.palette.ctrl_p.sections.channel             "Channel"
│   pito.palette.ctrl_p.sections.output              "Output"
│   pito.palette.ctrl_p.commands.new_session         "New session"
│   pito.palette.ctrl_p.commands.switch_session      "Switch session"
│   pito.palette.ctrl_p.commands.switch_channel      "Switch channel"
│   pito.palette.ctrl_p.commands.switch_period       "Switch period"
│   pito.palette.ctrl_p.commands.open_editor         "Open editor"
│   pito.palette.ctrl_p.commands.rename_session      "Rename session"
│   pito.palette.ctrl_p.commands.jump_to_message     "Jump to message"
│   pito.palette.ctrl_p.commands.fork_session        "Fork session"
│   pito.palette.ctrl_p.commands.compact_session     "Compact session"
│   pito.palette.ctrl_p.commands.share_session       "Share session"
│   pito.palette.ctrl_p.commands.export_transcript   "Export transcript"
│   pito.palette.ctrl_p.commands.refresh_channels    "Refresh channels"
│   pito.palette.ctrl_p.commands.add_channel         "Add channel"
│   pito.palette.ctrl_p.commands.remove_channel      "Remove channel"
│   pito.palette.ctrl_p.commands.toggle_channel_filter "Toggle channel filter"
│   pito.palette.ctrl_p.commands.copy_last_assistant_message "Copy last assistant message"
│   pito.palette.ctrl_p.commands.copy_session_transcript     "Copy session transcript"
│   pito.palette.ctrl_p.commands.show_tool_details   "Show tool details"
│   pito.palette.ctrl_p.commands.toggle_sidebar      "Toggle sidebar"
│   pito.palette.ctrl_p.commands.show_timestamps     "Show timestamps"
│   pito.palette.slash.descriptions.authenticate     "Authenticate to access pito"
│   pito.palette.slash.descriptions.channels         "List your YouTube channels"
│   pito.palette.slash.descriptions.videos           "List videos for a channel"
│   pito.palette.slash.descriptions.import           "Import channel or video metadata"
│   pito.palette.slash.descriptions.export           "Export session transcript"
│   pito.palette.slash.descriptions.help             "Show help and command reference"
│   pito.palette.slash.descriptions.clear            "Clear the current session"
│   pito.palette.slash.descriptions.new              "Start a new session"
│
├── sidebar/en.yml
│   pito.sidebar.esc_hint                            "esc"
│   pito.sidebar.game.subtitle                       "Game · imported %{date}"
│   pito.sidebar.game.sections.overview              "Overview"
│   pito.sidebar.game.sections.channels              "Channels covering this game"
│   pito.sidebar.game.sections.top_videos            "Top videos"
│   pito.sidebar.game.sections.tags                  "Tags"
│   pito.sidebar.game.sections.recommendation        "Recommendation"
│   pito.sidebar.game.sections.quick_commands        "Quick commands"
│
└── sample/en.yml
    (Hardcoded sample message bodies. Every key prefixed with `pito.sample.` and
     accompanied by an inline comment: `# SAMPLE — replace when Plan 2+ wires real data`)
```

## Phase index

- U0 — Pre-flight (verify Plan 0 lands)
- U1 — Tokens + Tailwind config
- U2 — Application layout shell
- U3 — Primitive components (Segment, Cursor)
- U4 — Shell components (Chatbox, MiniStatus, dots, in-progress)
- U5 — Event content components
- U6 — Chat shell page (`/`) with hardcoded sample messages
- U7 — Start screen page (`/start`)
- U8 — Palette components + review page (`/_ui/palettes`)
- U9 — Sidebar overlay + review page (`/_ui/sidebar`)
- U10 — i18n locale files (consolidate, audit)
- U11 — Verification & cleanup

---

## U0 — Pre-flight

> Verify Plan 0 finished. Don't start U1 until every box here is checked.

- [x] T0.1 Confirm every Plan 0 phase (P0–P19) is checked off. complexity: [manual]
      → P0–P8 complete; P9.1–P9.4 + P10.1–P10.4 done as U0 prereqs;
        P9.5+, P10.5+, P11 superseded by this plan; P12–P19 deferred
        to plan-beta-reboot-02+. See Plan 0 Status block.
- [x] T0.2 `bin/rails runner "puts Rails.version"` prints the expected Rails 8.x version. complexity: [manual]
      → Rails 8.1.3.
- [x] T0.3 `bin/dev` starts cleanly — Puma + Tailwind watcher up, no errors. complexity: [manual]
      → Procfile.dev now has `css: bin/rails tailwindcss:watch`
        (installer added it). Rails boot verified via tailwindcss:build
        + runner; full `bin/dev` run deferred to first U1+ visit.
- [x] T0.4 `bin/rails tailwindcss:build` succeeds. complexity: [manual]
      → "Done in 234ms".
- [x] T0.5 `ApplicationComponent` exists under `app/components/`; render `ApplicationComponent.new` in a console without error. complexity: [manual]
      → `ApplicationComponent < ViewComponent::Base` (view_component 4.11.0).
- [x] T0.6 Create branch `plan-01-ui` from `reboot/beta` (or main, post-Plan-0 merge). complexity: [manual]
      → Skipped — staying on `blank-home-v1`.
- [x] T0.7 Tag the current state as `v0.0.3-pre-static-ui`. complexity: [manual]
      → Skipped — no tags in this repo's workflow.

## U1 — Tokens + Tailwind config

> Define every named color/spacing token. Tokyo Night palette as CSS variables; Tailwind utility aliases on top.

- [x] T1.1 In `app/assets/tailwind/application.css`, add a `[data-theme="tokyo-night"]` selector block containing every CSS variable from the Tokens & theme system section above. complexity: [low]
- [x] T1.2 Extend Tailwind config (`tailwind.config.js` for TW3 or `@theme` block in `application.css` for TW4) to alias the CSS vars as utility names: `bg-root`, `bg-surface`, `bg-elevated`, `border-default`, `border-faded`, `text-fg`, `text-fg-dim`, `text-fg-faded`, `text-purple/blue/cyan/green/yellow/orange/red`, `bg-purple/orange/...`, `text-pito`, `bg-pito`. complexity: [medium]
- [x] T1.3 In `app/views/layouts/application.html.erb`, add `data-theme="tokyo-night"` to the `<html>` element. complexity: [low]
- [x] T1.4 Create a temporary smoke partial at `app/views/_smoke/tokens.html.erb` that renders one `<div>` per utility with a label. Route at `get "/_smoke/tokens", to: "_smoke#tokens"`. Controller stub. complexity: [low]
- [x] T1.5 Run `bin/dev`; visit `/_smoke/tokens`; verify every color renders correctly per the hex values in the spec. complexity: [manual]
- [x] T1.6 Delete the smoke partial, controller, and route. complexity: [low]
- [x] T1.7 Add a comment block at the top of `application.css` documenting the theme system (how to add a new theme: drop a `[data-theme="<name>"]` block with the same var names). complexity: [low]
- [x] T1.8 Commit: `U1: design tokens + tokyo night palette + pito brand`. complexity: [manual]

## U2 — Application layout shell

> Lock typography and base layout. Single font size, monospace, dark bg.

- [x] T2.1 Reset `app/views/layouts/application.html.erb` to: `<html data-theme="tokyo-night">` + `<head>` (title, csrf, viewport, csp, stylesheet, importmap_tags) + `<body class="bg-root text-fg font-mono">` with `<%= yield %>`. complexity: [low]
- [x] T2.2 In Tailwind config, set `theme.fontFamily.mono = ["ui-monospace", "monospace"]`. Override default mono stack — no web fonts, no fallbacks beyond `monospace`. complexity: [low]
- [x] T2.3 In Tailwind config, set `theme.fontSize.base = ["16px", "1.4"]` (size + line-height). Plan 1 uses ONLY `text-base` everywhere. complexity: [low]
- [x] T2.4 Add a body-level rule (in `application.css` or as Tailwind base layer): `* { font-size: inherit; }` — defensive guard against `text-sm`/`text-lg` from accidental use. complexity: [low]
- [x] T2.5 Boot `bin/dev`, visit `/` (still 404 fine), verify the page background is `#1a1b26` and any visible text is monospace 16px. complexity: [manual]
- [x] T2.6 Commit: `U2: application layout shell + typography lock`. complexity: [manual]

## U3 — Primitive components (Segment, Cursor)

> Build the two visual primitives every other component depends on.

- [x] T3.1 Create `app/components/pito/segment/component.rb`. Initialize with `border:` and `background:` keyword args, both nilable. Render block content via `content` slot. complexity: [low]
- [x] T3.2 Create `app/components/pito/segment/component.html.erb` with the bar+gap+content flex markup. Bar 4px wide, gap 6px transparent, content `flex-1` with padding `10px 16px 10px 12px` and the background fill applied ONLY to the content child. complexity: [medium]
- [x] T3.3 Smoke render in `rails console`: `ApplicationController.renderer.render(Pito::Segment::Component.new(border: "var(--accent-orange)", background: nil)) { "test" }`. Inspect output. complexity: [manual]
- [x] T3.4 Create `app/components/pito/cursor/component.rb` with `char:` and `color:` kwargs (default `var(--accent-purple)`). complexity: [low]
- [x] T3.5 Create `app/components/pito/cursor/component.html.erb` — inline `<span>` with `background: <color>; color: var(--bg-root);` containing the character. complexity: [low]
- [x] T3.6 Smoke render the cursor; verify the character appears inverted (purple bg, dark fg). complexity: [manual]
- [x] T3.7 Visual review: both primitives match `ui-p1.5.md` patterns. complexity: [manual]
- [x] T3.8 Commit: `U3: Pito::Segment + Pito::Cursor primitives`. complexity: [manual]

## U4 — Shell components

> Chatbox, mini-status, post-command dots, in-progress indicator.

- [x] T4.1 Create `Pito::Shell::ChatboxComponent` (rb + erb). Args: `state:`, `placeholder_key:`, `filter:`. complexity: [medium]
- [x] T4.2 In the erb, use `Pito::Segment::Component` with purple border + surface background. Inside, render line 1 (Cursor + placeholder) and conditionally line 2 (filter context). complexity: [medium]
- [x] T4.3 Create `Pito::Shell::MiniStatusComponent` (rb + erb). Args: `mode:`, `state:`, `notifications:`, `show_notifications:`. complexity: [medium]
- [x] T4.4 Create `Pito::Shell::PostCommandDotsComponent` (rb + erb). Add CSS keyframes for the sweep animation in a co-located stylesheet (e.g., `app/components/pito/shell/post_command_dots_component.css` or inline `<style>` in the template — pick one and commit to it). complexity: [medium]
- [x] T4.5 Create `Pito::Shell::InProgressComponent` (rb + erb). Args: `verb_key:`. Wrap in `Pito::Segment::Component` (borderless). Inside: braille spinner span + shimmer-text span + dim ellipsis. complexity: [medium]
- [x] T4.6 Add CSS keyframes for braille spinner cycle and text shimmer. Co-locate in component CSS or `application.css` under a clearly-namespaced selector. complexity: [medium]
- [x] T4.7 Smoke render each shell component in isolation (via console or a temporary `/_smoke/shell` route). complexity: [manual]
- [x] T4.8 Delete any temporary smoke routes/views after verification. complexity: [low]
- [x] T4.9 Visual review: each matches its v0 spec (`ui-p1.4.md`, `ui-p1.5.md`, `ui-p1.2.md`). complexity: [manual]
- [x] T4.10 Commit: `U4: Pito::Shell components (chatbox, mini-status, dots, in-progress)`. complexity: [manual]

## U5 — Event content components

> The five segments that appear in the chat message stream. All static renderers; all use Pito::Segment under the hood.

- [x] T5.1 Create `Pito::Event::UserMessageComponent` (rb + erb). Orange border, no background, body text in `text-fg`. complexity: [low]
- [x] T5.2 Create `Pito::Event::AssistantTextComponent` (rb + erb). Borderless, supports optional rich content slot. complexity: [low]
- [x] T5.3 Create `Pito::Event::ThoughtComponent` (rb + erb). Borderless, `+ Thought:` prefix orange-bold + duration dim. complexity: [low]
- [x] T5.4 Create `Pito::Event::ToolOutputComponent` (rb + erb). Purple border + elevated background. Title, command, pre-formatted output, "Click to expand" affordance (purely visual — no click handler). complexity: [medium]
- [x] T5.5 Create `Pito::Event::StatusFooterComponent` (rb + erb). Borderless, `▣` glyph + mode + agent + duration. complexity: [low]
- [x] T5.6 Smoke render each event component in isolation. complexity: [manual]
- [x] T5.7 Visual review: each matches `ui-p1.5.md`. Pay attention to the alignment invariant — text in any event should sit 22px from the segment's left edge regardless of whether the segment has a border. complexity: [manual]
- [-] T5.8 Commit: `U5: Pito::Event content components`. complexity: [manual]

## U6 — Chat shell page (`/`)

> The main route. Hardcoded sample messages rendered through Event components.

- [ ] T6.1 Generate `TerminalController` with `#show` action. complexity: [low]
- [ ] T6.2 Create `lib/pito/sample/chat_shell.rb` — a module returning an ordered array of sample message records (each with `kind:` symbol + relevant fields). Mark every body string with comment `# SAMPLE — replace when wiring real data in Plan 2+`. complexity: [medium]
- [ ] T6.3 In `TerminalController#show`, assign `@events = Pito::Sample::ChatShell.events` and render the view. complexity: [low]
- [ ] T6.4 Create `app/views/terminal/show.html.erb`. Layout: full-viewport flex column. Top region: scroll area (`flex: 1, overflow-y: auto`) iterating over `@events` and rendering the right Event component for each kind. Bottom region: chatbox row (default state) + mini-status row beneath (with post-command dots on left, mini-status on right). complexity: [medium]
- [ ] T6.5 Pass hardcoded filter `{ channel: "@gmrdad82", period: "7d" }` to the chatbox. Pass `mode: :connection, state: true, notifications: 3, show_notifications: true` to the mini-status. complexity: [low]
- [ ] T6.6 In `config/routes.rb`, add `root "terminal#show"`. complexity: [low]
- [ ] T6.7 Visit `/`, verify the render matches `ui-p1.5.md` final state (segments aligned, chatbox at bottom, mini-status right-aligned). complexity: [manual]
- [ ] T6.8 Commit: `U6: chat shell page (/) with sample messages`. complexity: [manual]

## U7 — Start screen page (`/start`)

> The unauthenticated landing screen. Centered chatbox, no logo asset yet (out of scope).

- [ ] T7.1 Generate `StartScreensController` with `#show` action. complexity: [low]
- [ ] T7.2 Create `Pito::StartScreen::Component` (rb + erb). Args: `version:`, `pitomd_url:`. Slot: `logo` (default empty). complexity: [medium]
- [ ] T7.3 In the erb, build the full-viewport layout: empty top region, centered group (logo slot — reserve ~120px vertical space, empty for now — then 32px gap, chatbox `state: :start` `max-width: 800px`, mini-status row), tip line midway between mini-status and bottom corners, bottom corners (pitomd link + version). Chatbox's vertical center at 50vh. complexity: [medium]
- [ ] T7.4 In `StartScreensController#show`, pass `version: "0.1.0"` and render. Caller does NOT fill the logo slot in Plan 1 — leave it empty. complexity: [low]
- [ ] T7.5 In `config/routes.rb`, add `get "/start", to: "start_screens#show"`. complexity: [low]
- [ ] T7.6 Visit `/start`. Verify: chatbox at 50vh, centered, single-line placeholder showing `/authenticate 123456` with cursor on `/`. Mini-status reads "Not authenticated · ctrl+p commands" with "Not authenticated" in red. Tip line centered, dim. pitomd.com link bottom-left, version bottom-right. complexity: [manual]
- [ ] T7.7 Commit: `U7: start screen (/start)`. complexity: [manual]

## U8 — Palette components + review page (`/_ui/palettes`)

> Both palettes rendered statically on a review-only page. Production rendering happens later as overlays inside the chat shell.

- [ ] T8.1 Create `Pito::Palette::Slash::Component` (rb + erb). Args: `commands:`, `selected_index:`, `typed:`. complexity: [medium]
- [ ] T8.2 In the erb, wrap in `Pito::Segment::Component` (purple border + surface bg). Render the command list (rows with `/<verb>` left, description right, fixed-width padding so descriptions align at column 20). Highlight selected row with `bg-border-default`. Divider line. Input echo line with cursor. complexity: [medium]
- [ ] T8.3 Create `Pito::Palette::CtrlP::Component` (rb + erb). Args: `sections:`, `selected_section_index:`, `selected_item_index:`. complexity: [medium]
- [ ] T8.4 In the erb, render the centered modal (surface bg, 1px border, 24px padding). Title row + search input + sections. Apply `max-height: min(80vh, 600px); overflow-y: auto`. Selected row inset 8px from interior edges. complexity: [medium]
- [ ] T8.5 Create `Pito::Palette::CtrlP::SectionComponent` (rb + erb). Renders the section title + a list of item rows. complexity: [low]
- [ ] T8.6 Generate `_Ui::PalettesController` (controller class name `Ui::PalettesController`, file at `app/controllers/_ui/palettes_controller.rb`). Action `#show`. complexity: [low]
- [ ] T8.7 In the controller, hardcode the slash commands array (8 commands) and the Ctrl+P sections array (Suggested / Session / Channel / Output) using the i18n keys from the spec. complexity: [medium]
- [ ] T8.8 Create `app/views/_ui/palettes/show.html.erb`. Stack both palettes vertically inside an 800px centered container, each with a small subheading above (`"Slash command palette · opens above chatbox when / is typed"`, `"Ctrl+P command palette · centered modal overlay"`). complexity: [low]
- [ ] T8.9 In `config/routes.rb`, add `namespace :_ui do get "palettes", to: "palettes#show" end`. complexity: [low]
- [ ] T8.10 Visit `/_ui/palettes`. Verify both palettes match `ui-p3.md`. complexity: [manual]
- [ ] T8.11 Commit: `U8: palette components + review page`. complexity: [manual]

## U9 — Sidebar overlay + review page (`/_ui/sidebar`)

> Sidebar rendered as `position: fixed` overlay on top of the chat shell. Review-only route; production opens via interaction.

- [ ] T9.1 Create `Pito::Sidebar::Component` (rb + erb). Args: `title:`, `subtitle_key:`, `subtitle_args:`. Slot: `body`. complexity: [medium]
- [ ] T9.2 In the erb, render the `<aside>` with `position: fixed; right: 0; top: 0; bottom: 0; width: 480px; background: var(--bg-root); border-left: 1px solid var(--border-default); z-index: 10; overflow: hidden`. Inside, sticky header (title block + esc) and scrollable body slot. complexity: [medium]
- [ ] T9.3 Create `Pito::Sidebar::SectionComponent` (rb + erb). Args: `title_key:`. Renders title + content slot + 24px bottom margin. complexity: [low]
- [ ] T9.4 Generate `_Ui::SidebarController` with action `#show`. Hardcode game-detail sample data (Hollow Knight) in the controller or in `lib/pito/sample/game_detail.rb`. complexity: [medium]
- [ ] T9.5 Create `app/views/_ui/sidebar/show.html.erb`. Two children of a root wrapper with `overflow: hidden`:
  - `<main>` containing the SAME content as `TerminalController#show` (reuse the sample messages module from U6). No max-width, no padding-right. Chat shell renders at full viewport width.
  - `<aside>` rendered via `Pito::Sidebar::Component` with `title: "Hollow Knight"`, `subtitle_key: "pito.sidebar.game.subtitle"`, `subtitle_args: { date: "2026-05-18" }`. Inside the body slot, render each game-detail section via `Pito::Sidebar::SectionComponent`.
  
  Note: the chat shell extends full width on purpose — the sidebar is an overlay that covers the right ~480px by design. Some chat content goes behind the sidebar; that's the intended behavior. complexity: [medium]
- [ ] T9.6 In `config/routes.rb`, add `namespace :_ui do get "sidebar", to: "sidebar#show" end`. complexity: [low]
- [ ] T9.7 Visit `/_ui/sidebar`. Verify: no horizontal page scroll, chat shell renders at full viewport width (identical to `/`), sidebar floats fixed on the right at 480px, sticky header, scrollable body inside the sidebar. complexity: [manual]
- [ ] T9.8 Commit: `U9: sidebar overlay component + review page`. complexity: [manual]

## U10 — i18n locale files

> Consolidate all user-facing strings into locale files. Audit components to ensure no inline strings remain.

- [ ] T10.1 Create `config/locales/pito/shell/en.yml` with the keys listed in the i18n key tree (chatbox + mini-status + in-progress sections). complexity: [low]
- [ ] T10.2 Create `config/locales/pito/event/en.yml` with the keys for thought + tool output. complexity: [low]
- [ ] T10.3 Create `config/locales/pito/start_screen/en.yml`. complexity: [low]
- [ ] T10.4 Create `config/locales/pito/palette/en.yml` with all slash command descriptions + Ctrl+P section labels + command labels. complexity: [low]
- [ ] T10.5 Create `config/locales/pito/sidebar/en.yml` with the game-detail section labels + esc hint + subtitle. complexity: [low]
- [ ] T10.6 Create `config/locales/pito/sample/en.yml` containing every sample message body string used by the chat shell page. Prefix every key with `pito.sample.` and add a top-of-file comment `# SAMPLE — every key in this file will be replaced when real data is wired in Plan 2+`. complexity: [medium]
- [ ] T10.7 Audit each component template under `app/components/pito/**` and each view under `app/views/**` — run `git grep -nE '">[A-Z]'` and `git grep -nE 'translate\\b'`. Goal: every user-facing string is `t(".key")`. Fix any stragglers. complexity: [medium]
- [ ] T10.8 Boot `bin/dev`; visit each route and confirm no `translation missing` placeholders appear. complexity: [manual]
- [ ] T10.9 Commit: `U10: i18n locale files; all copy externalized`. complexity: [manual]

## U11 — Verification & cleanup

> Final pass before tagging. Make sure the plan delivered exactly what it promised.

- [ ] T11.1 Visit `/`, `/start`, `/_ui/palettes`, `/_ui/sidebar` in a real browser at full width (not the v0 narrow preview). Compare each side-by-side with its v0 spec (`docs/ui/ui-pX.md`) and the v0 snapshot. Note any visual deltas; fix or document. complexity: [manual]
- [ ] T11.2 `git grep -nE '#[0-9a-fA-F]{6}'` in `app/views/**` and `app/components/**` — should return zero hex values (everything goes through Tailwind utilities or CSS vars). complexity: [manual]
- [ ] T11.3 `git grep -n 'text-sm\\|text-lg\\|text-xl\\|text-2xl\\|text-3xl\\|text-4xl\\|text-5xl'` in `app/views/**` and `app/components/**` — should return zero hits (Plan 1 uses only `text-base`). complexity: [manual]
- [ ] T11.4 `git diff --stat reboot/beta...HEAD -- Gemfile Gemfile.lock` — should show NO new gems beyond what Plan 0 introduced. complexity: [manual]
- [ ] T11.5 Update `docs/architecture.md` to mention the static UI baseline lives at `/`, `/start`. Note the `/_ui/*` review routes will be removed in Plan 2+. complexity: [low]
- [ ] T11.6 Commit: `U11: static ui verification + architecture notes`. complexity: [manual]
- [ ] T11.7 Tag: `git tag v0.1.0-static-ui`. complexity: [manual]

---

## Open follow-ups (Plan 2+)

These are explicitly NOT in Plan 1. They live in subsequent plans:

- Logo asset + treatment on start screen (logo is intentionally out of scope here)
- Stimulus controllers (autoscroll, slash palette toggle on `/`, TAB channel cycling, Ctrl+P modal open/close, sidebar toggle, theme switcher, expand/collapse on tool-output cards)
- Action Cable channels + Turbo Streams for message streaming
- Command router + handler registry (`lib/pito/command/router.rb`)
- Persistence layer (Session, Message models — Plan 0 P7 covers schema)
- Authentication (`/authenticate <code>` command + TOTP flow, `before_action :require_login`)
- YouTube OAuth flow (handled by `omniauth-google-oauth2` from Plan 0 P14)
- Real data sources (channels, videos, games)
- Voyage.AI recommendation pipeline
- Tip dictionary (rotating tips on start screen — replaces the placeholder string)
- Theme switcher UI + additional theme variants (Catppuccin, Gruvbox, etc.)
- Removing the `/_ui/*` review routes once palettes and sidebar are wired as interaction-driven overlays
- Markdown rendering of streamed content (defer; ASCII suffices today)
- Component spec coverage (RSpec component tests via `view_component/test_helpers`)
- Lookbook (deferred; possibly never per Plan 0 lock)

## How to use this plan

Same as Plan 0:

1. Pick the next unchecked task in phase order.
2. Read the `complexity:` hint; pick the cheapest model that fits the tier.
3. Dispatch as a sub-agent (in OpenCode, Claude Code, etc.) OR do by hand.
4. Verify (read the diff, run `bin/dev`, visit the affected route, compare against the referenced v0 spec).
5. Check the box. Move on.
6. Commit at the end of each phase using the suggested title.
7. If a task feels bigger than 5 minutes, split it.
