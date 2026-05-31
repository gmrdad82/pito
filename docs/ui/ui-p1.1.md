# P1.1 — pito chat shell revisions (v0.dev edit prompt)

> **How to use this file**
>
> - Open the same v0.dev project where P1 was rendered.
> - Model: **v0 Auto** (recommended) — Mini may struggle with the segment refactor + animations; Max isn't needed since aesthetic is locked.
> - Paste the prompt block below verbatim as a follow-up message on the existing component (v0 keeps the prior code in context).
> - No new reference images needed — the changes are deltas against the previous output.

---

## Prompt

```
# Revise: pito chat shell foundation (P1 → P1.1)

The component you produced previously is close. Apply these changes against it.

## 1. Refactor all segments through ONE component
Create a `<Segment>` component used for every message row. Props:
  - border:    hex string | null   — when set, render a 3px solid left border in that color
  - background: hex string | null  — when set, fills the segment with that color
  - children:  ReactNode
Internal padding: 12px 16px when no border, 12px 16px 12px 12px when border is set (the 3px border + 12px inner gap ≈ 16px total visual indent).
Use this component for EVERY message row. No bespoke wrappers per type.

## 2. Border + background table

| Segment                      | border    | background |
|------------------------------|-----------|------------|
| User message                 | #ff9e64   | null       |
| Tool-output card             | #bb9af7   | #24283b    |
| In-progress segment (new)    | #bb9af7   | null       |
| `+ Thought: 8.2s`            | null      | null       |
| Assistant prose paragraphs   | null      | null       |
| Status footer                | null      | null       |

## 3. Delete the bottom status strip ENTIRELY
Remove the bottom row that contained `pito · connected · channels · sidekiq counts · token meta`. Gone. No replacement at the bottom.

## 4. Restructure the chatbox (input area)
- Taller — ~140px total height.
- Keep purple #bb9af7 3px left-border. Surface bg #1f2335. Other-side borders 1px #292e42.
- Internal layout, top to bottom:
  - Line 1 — input area: purple block cursor + dim "Ask anything…" placeholder. Reserve 2 lines of vertical space for typed text (visually empty for the mockup).
  - Empty space.
  - Line 2 — filter context: `Channel: @gmrdad82 · Period: 7d`
      - `Channel:` and `Period:` in dim #565f89
      - `@gmrdad82` in cyan #7dcfff
      - `7d` in cyan #7dcfff
  - Bottom-left of the chatbox interior: post-command indicator. Render as a sequence of 8 dots `........` in dim #565f89, with a CSS shimmer/sweep animation — a brighter highlight (cyan #7dcfff) slides left-to-right across the dots in a 1.4s loop. Use `mask-image: linear-gradient(...)` + `@keyframes` on background-position, or any pure-CSS technique. No JS.

## 5. Mini status — right of the chatbox, same row
Plain text, no border, no background. Vertically center against the chatbox. Single line:
  `● Connected · 3 notifications · ctrl+p commands`
  - `●` and `Connected` in green #9ece6a
  - `3 notifications` in cyan #7dcfff
  - `ctrl+p` in yellow-bold #e0af68
  - `commands` in dim #565f89
  - All separators ` · ` in dim
For the disconnected state (do NOT render this state in the mockup, just include it as a commented-out variant in the code): `● Disconnected` in red #f7768e.

## 6. Add the in-progress segment (new)
This is a special segment that appears at the very bottom of the message list, above the chatbox, while the backend is doing real work. In the mockup, render it visibly so we can see the styling.
Content: `⠋ Building…`
  - `⠋` in cyan #7dcfff. Animate by cycling through braille frames `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` at 100ms per frame via CSS `steps(10)` + `@keyframes`. If you can't cycle the glyph itself in CSS reliably, fall back to opacity-pulse on a static `⠋`.
  - `Building` — apply a horizontal shimmer animation using `background-clip: text` + a moving linear-gradient (`#c0caf5` ↔ `#7dcfff`), 2s loop, infinite.
  - `…` in dim #565f89.

## 7. Replace ALL sample content with generic placeholder content
Drop everything related to "docs/plan-beta-reboot.md" and the Rails 8 reboot text. Use this story instead:

  USER message:
    /channels overview

  ASSISTANT prose (replaces the "Written to…" segment):
    "Pulling stats for your 3 active channels over the last 7 days."

  TOOL-OUTPUT card (replaces the `ls -la` card):
    Title:   # Channel rollup
    Command: $ pito channels overview --period 7d
    Output (pre-formatted, aligned columns):
      Channel             Subs       Views       Watched
      @gmrdad82           1,240      48,310      612h
      @gmrdad82-vlog        890      14,107      188h
      @gmrdad82-shorts    3,712     192,840      241h
    Followed by dim "Click to expand" on its own line.

  ASSISTANT prose paragraph (replaces the "P0 is the stop everything…" paragraph):
    "Your @gmrdad82-shorts channel is your highest watch-time growth driver this week — 38% week-over-week. Consider doubling shorts cadence."

  STATUS footer (replaces "Build · Big Pickle · 1m 3s"):
    ▣ Build · Big Pickle · 1m 3s
    (Keep the same — it's already generic.)

  IN-PROGRESS segment (new, at the very bottom of the message list):
    ⠋ Building…

## Keep unchanged
- Tokyo Night palette (exact hex values)
- 16px font-size everywhere, ui-monospace + monospace only, no web fonts
- Zero rounded corners, zero shadows, zero gradients (except inside the shimmer/sweep animations)
- All horizontal padding, vertical gap, and layout rules from P1

Render it.
```

---

## After v0 returns

1. Screenshot the result.
2. Bring it back to Claude for review against this spec.
3. If close: write a Mini-tier surgical edit prompt.
4. If aesthetic missed: escalate to v0 Max Fast with the failed screenshot attached as a "do NOT do this" reference.
