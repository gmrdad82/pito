# P4 — pito right sidebar mode (v0.dev prompt)

> **How to use this file**
>
> - Same v0.dev project. Creates a NEW route `/sidebar` for visual review.
> - Model: **v0 Max** — new route + two-column layout + new content structure. Worth the credits.
> - Attach this file and paste the one-liner below in the chat input.

---

## What to type in the v0 chat input (along with attaching this file)

> Build the pito right sidebar mode described in `ui-p4.md` on a NEW route `/sidebar` (file `app/sidebar/page.tsx`). Do NOT modify `/`, `/start`, `/palettes`, or any shared component — those screens must render identically. Sidebar appears/disappears instantly with no slide-in or fade animation (TUI-style snappy toggle).

---

## Prompt

```
# Build: pito right sidebar mode (P4)

## What this is
A right-side detail panel that shows contextual info about an entity (game, channel, video, session). For this mockup we render the **game detail** variant. The sidebar sits side-by-side with the chat shell — both visible at once — when opened.

The sidebar appears and disappears INSTANTLY. No slide-in animation, no fade, no transition. Terminal-style snappy toggle. The user's eye should not perceive any motion — the sidebar is either present in the layout (taking its column) or absent (the chat shell occupies the full width).

## CRITICAL — scope
- Create a NEW route at `/sidebar` (file `app/sidebar/page.tsx`).
- Do NOT modify `/`, `/start`, `/palettes`, or any component imported by them.
- Chat shell, start screen, and palettes preview must continue to render identically.

## Reuse from P1.5 (do NOT reinvent)
- Tokyo Night palette, exact hex values
- 16px font-size everywhere; `ui-monospace, monospace`; no web fonts
- Zero rounded corners, zero CSS shadows, zero gradients
- All chat shell components (Chatbox, Segment, MiniStatus) — reuse for the left column

## Page layout
Full viewport, two columns side-by-side via flex:

LEFT column (chat shell, flex: 1):
- Render the same chat shell content as `/` — the P1.5 design with sample segments (user message `/channels overview`, assistant prose, tool-output card, in-progress segment, chatbox at bottom, mini-status row).

RIGHT column (sidebar):
- width: 35% of viewport, min-width 360px, max-width 480px
- 1px left border #292e42 separating from the chat shell
- Same root background #1a1b26 (NO elevation fill, NO shadow)
- Internal padding: 16px on all sides
- Scrollable independently if content overflows vertically (overflow-y: auto)

## Sidebar content (game detail variant)

### Header row (flex justify-between)
- Left: title block (two lines)
   - Line 1: `Hollow Knight` in cyan #7dcfff, bold
   - Line 2: `Game · imported 2026-05-18` in dim #565f89
- Right (aligned with Line 1): `esc` in dim #565f89

24px gap below header.

### Section: Overview
Section label (orange-bold #ff9e64): `Overview`
4px gap below label.
Rows — label left dim, value right fg, flex justify-between, 2px vertical padding per row:

  Genre            Metroidvania
  Released         2017-02-24
  Steam reviews    97% positive
  Imported         8 days ago

24px gap.

### Section: Channels covering this game
Section label: `Channels covering this game`
Rows — channel handle left in cyan #7dcfff, video count right in fg #c0caf5:

  @gmrdad82           3 videos
  @gmrdad82-vlog      1 video
  @gmrdad82-shorts    12 videos

24px gap.

### Section: Top videos
Section label: `Top videos`
Rows formatted as: date + title (left) + views (right). Date in dim, title in fg, views in cyan. Use flex justify-between:

  2026-05-24  How to play Hollow Knight       12k views
  2026-05-21  Hollow Knight charms tier list   8k views
  2026-05-19  Speedrun guide                  45k views

Long titles truncate with ellipsis if they overflow.

24px gap.

### Section: Tags
Section label: `Tags`
Single row of comma-separated tags in fg #c0caf5 (NOT chips, just text):

  metroidvania, indie, souls-like, 2D platformer

24px gap.

### Section: Recommendation
Section label: `Recommendation`
A single short paragraph in fg #c0caf5:

  Based on neighbor channel analysis, consider a Hollow Knight: Silksong preview video for @gmrdad82-shorts — audience overlap is 72%.

24px gap.

### Section: Quick commands
Section label: `Quick commands`
Three rows, each prefixed with `·` (in dim) followed by the command (in cyan #7dcfff):

  · /import-game-videos Hollow Knight
  · /channels-for-game Hollow Knight
  · /export-game-data Hollow Knight

24px gap at the bottom of the sidebar.

## Do NOT
- Do not add ANY animation, transition, slide-in, or fade. The sidebar appears/disappears instantly. No `transition-*`, `animate-*`, `duration-*`, `ease-*` utilities anywhere.
- Do not add Tailwind hover effects on any sidebar element.
- Do not add backdrop dim or overlay — sidebar is side-by-side, not modal.
- Do not use any web fonts.
- Do not add rounded corners or shadows.
- Do not modify `/`, `/start`, or `/palettes`.

Render it.
```

---

## After v0 returns

1. Navigate the preview to `/sidebar` to view the side-by-side layout.
2. Verify `/`, `/start`, and `/palettes` still render identically (no regressions).
3. Screenshot the result.
4. Bring it back for review.
5. Once locked, save the final snapshot to `~/Dev/pito/tmp/v0-snapshots/p4.zip` — this is the **complete v0 deliverable** before the Rails port begins.
