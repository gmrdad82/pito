# P1 — pito chat shell foundation (v0.dev prompt)

> **How to use this file**
> - Open v0.dev, select **v0 Max**.
> - Paste the prompt block below verbatim.
> - Attach the reference screenshots: the full chat layout, the Tokyo Night palette reference, and the input-with-block-cursor closeup.
> - One-shot. Iterate via Mini-tier edits afterwards.

---

## Prompt

```
# Build: pito chat shell foundation

## What this is
A static mockup of the main chat interface of "pito" — a YouTube/streaming creator analytics tool. This is the foundation screen. Aesthetic must be locked here; later prompts layer on palettes and other screens.

## Critical constraints (read carefully)
- Output: a single React component file, default export, all content statically visible — no state, no useEffect, no interaction handlers. This will be ported by hand to Ruby on Rails ViewComponent+ERB.
- Use Tailwind utility classes only. No shadcn/ui. No Radix. No animation libraries. No icon libraries — use plain Unicode glyphs (•, ─, │, ▏, █) and small inline SVGs only if absolutely needed.
- Plain HTML semantics: <div>, <span>, <pre>, <ul>, <li>. Nothing fancy.
- Single Tailwind config inline at top via arbitrary values (e.g. bg-[#1a1b26]). Do NOT touch tailwind.config.

## Aesthetic — non-negotiable
- Terminal / TUI inspired. Looks like Tokyo Night theme in a real terminal.
- Zero border-radius. Zero shadows. Zero gradients. Zero glass / blur.
- Sharp 1px solid borders only. 2px or 3px left-borders for segment emphasis.
- Dense layout. Monospace everywhere. Line-height ~1.4. No generous padding.
- Looks like OpenCode TUI, not like a modern web chat app.

## Palette (Tokyo Night — use EXACTLY these hex values)
- Root background: #1a1b26
- Surface (input box, panels): #1f2335
- Elevated (tool-output cards): #24283b
- Default border: #292e42
- Primary text: #c0caf5
- Dim text (hints, metadata, "Click to expand"): #565f89
- Faded text (very subtle separators): #414868
- Purple (assistant accent, input cursor): #bb9af7
- Blue (links, info): #7aa2f7
- Cyan (numbers, counts): #7dcfff
- Green (success, connected dot): #9ece6a
- Yellow (highlighted keyword like "high"): #e0af68
- Orange (user accent, "+ Thought:" prefix): #ff9e64
- Red (errors, only if needed): #f7768e

## Typography (strict — one size everywhere, system fonts only)
font-family: ui-monospace, monospace
font-size: 16px — EVERYWHERE. No exceptions.
line-height: 1.4
No letter-spacing tweaks.

IMPORTANT: Do NOT import any web font. No Google Fonts, no @font-face, no <link rel="preconnect" fonts.googleapis>, no font CDN. The system's default monospace (ui-monospace) renders instantly with no FOUT/FOIT jiggle.

This applies to: headings, paragraphs, code, pre, status strip, input, hints, "Click to expand", model labels, footer text — everything. Do not use text-sm, text-lg, text-xl, text-2xl, or any other size utility. Use text-base only, or equivalent arbitrary value.

Visual hierarchy is achieved via:
  - Color (fg vs fg-dim vs accent colors)
  - Weight (regular vs bold) — bold sparingly, for keywords only
  - Prefixes (`#`, `$`, `+`, `>`, `─`)
  - Whitespace (blank lines, vertical gaps)
NEVER via font-size.

## Layout (full viewport, bottom-up)

Row 4 (very bottom, 1 line, ~36px tall) — global status strip:
  Left aligned: `pito` (bold) │ green dot + "connected" │ channels: `[@all]` `[@pito-gaming]` `[@pito-dev]`  │ sidekiq counts `b2 e5 r1 d0`
  Right aligned: `62.8K (31%)` · `$2.10` · `ctrl+p commands` (the "ctrl+p" portion is yellow-bold, "commands" is dim)
  Single top border #292e42 separates from row 3.

Row 3 (input box, ~80px tall) — bordered with sharp 1px #292e42, 3px left-border #bb9af7 (purple):
  Line 1 (input field text): a purple █ block cursor at start, then dim-text placeholder: `Ask anything... "What is the tech stack of this project?"`
  Line 2 (model strip, same 16px size, distinguished by color only): `Build` (purple bold) · `DeepSeek V4 Flash Free OpenCode Zen` (dim) · `high` (yellow bold)
  Bottom-right of input box (fg-dim, same 16px): `tab agents   ctrl+p commands` (the `tab` and `ctrl+p` are white, the rest dim)
  Input box has small horizontal margin from viewport edges (~80px each side, NOT centered narrow — generous width).

Row 2 (scrollable message area) — fills all remaining vertical space, scroll-y auto:
  Contains the segments below, top-to-bottom. Each segment has:
    - 3px solid left-border in the segment's accent color
    - 16px left-padding after the border
    - 12px vertical spacing between segments
    - NO background fill, NO border on the other 3 sides

  Segment A (USER message, accent = orange #ff9e64):
    Body text: "My application is in a wip state and I've decided to return back to Rails 8 roots and defaults while keeping my models intact, clean all RSpecs as I'll revisit after, discard / challenge the gems that are not standard and rethink my approach afterwards in a much cleaner state."
    Plain text, no markdown, fg color #c0caf5.

  Segment B (ASSISTANT thought line, accent = purple #bb9af7):
    Single line: `+ Thought: 8.2s`  — the `+ Thought:` portion is orange (#ff9e64) bold, `8.2s` is fg dim.

  Segment C (TOOL OUTPUT card, accent = purple #bb9af7):
    Title line: `# List project root contents` (fg-dim, prefixed with `#`)
    Empty line
    Command line: `$ ls -la` (cyan #7dcfff)
    Empty line
    Pre-formatted output block — fg color #c0caf5, indented to align:
      total 284
      drwxr-xr-x 1 catalin catalin    892 May 26 15:07 .
      drwxr-xr-x 1 catalin catalin    282 May 25 13:38 ..
      -rw-r--r-- 1 catalin catalin   5989 May 25 22:05 AGENTS.md
      drwxr-xr-x 1 catalin catalin    220 May 25 22:37 app
    Followed by a dim `…` on its own line.
    Followed by a clickable-looking dim text: `Click to expand` (fg-dim #565f89, underlined on hover via Tailwind hover:underline).

  Segment D (ASSISTANT message with markdown, accent = purple #bb9af7):
    Heading: `Written to docs/plan-beta-reboot.md.` — where `docs/plan-beta-reboot.md` is yellow-bold #e0af68. Same 16px size as everything else.
    Body paragraph: "20 phases, ~210 atomic tasks, each with a `model:` hint for agent selection." — backticked `model:` is cyan #7dcfff.
    Empty line
    Body paragraph: "P0 is the \"stop everything and snapshot\" gate — complete it before any other phase so you have a recovery point. Every subsequent phase also ends with a commit, so you can always roll back by reverting a single phase's commit if something goes wrong."
    Empty line
    Closing line: "Start with P0 whenever you're ready. When you have questions about a specific task or want me to execute one, holler."

  Segment E (ASSISTANT status footer, accent = purple #bb9af7):
    Single line (fg-dim): `[icon] Build · Big Pickle · 1m 3s` — `[icon]` is a small monospace square (e.g. `▣` cyan), `Build` is purple bold, the rest dim.

Row 1 (top of viewport — none, the scrollable area extends to the top edge with a fade-to-bg gradient hint at the very top ~24px — implement as a tiny absolutely-positioned div with a linear-gradient from bg to transparent, NOT a shadow).

## Spacing rules
- Outer page padding: 0. Use viewport edges fully.
- Horizontal padding inside scroll area: 80px each side.
- Vertical gap between segments: 12px.
- Input box: margin 16px from bottom status strip, 80px from each side.
- Status strip: padding 8px 16px.

## Do NOT
- Do not add a top header / nav bar.
- Do not add avatars, profile pics, or "User"/"AI" name labels — the colored left-border IS the role indicator.
- Do not add hover-card effects, tooltips, dropdowns.
- Do not use rounded-* utilities anywhere.
- Do not use shadow-* utilities anywhere.
- Do not animate anything.
- Do not import any web font (no Google Fonts, no @font-face, no font CDN links). Use only `ui-monospace, monospace` — the OS-native monospace, zero network fetch.
- Do NOT vary font-size anywhere. text-sm, text-lg, text-xl, etc. are forbidden. Only text-base (16px) or the arbitrary equivalent text-[16px] is allowed.
- Do NOT use Tailwind's prose/typography plugin (it injects size variation).
- Do NOT make the status strip or "ctrl+p commands" smaller — same 16px.

## What I'll judge this on
1. Tokyo Night palette is exact.
2. Left-border segment treatment looks clean and dense.
3. Input box has a visible purple block cursor at the start (use a 8px × 16px purple solid <span> with no border).
4. The "Click to expand" feels like a TUI affordance, not a button.
5. Nothing rounded, nothing shadowed, nothing animated.
6. One font size (16px) everywhere — no exceptions.

Render it.
```

---

## Reference attachments to upload with the prompt

- Full chat layout screenshot
- Tokyo Night palette reference
- Input-with-block-cursor closeup

## After v0 returns

1. Screenshot the result.
2. Bring it back to Claude for review against this spec.
3. If close: write a Mini-tier surgical edit prompt.
4. If aesthetic missed: re-run P1 on Max with the failed screenshot attached as a "do NOT do this" reference.
