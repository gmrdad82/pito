# P3 — pito command palettes (v0.dev prompt)

> **How to use this file**
> - Same v0.dev project. Creates a NEW route `/palettes` for visual review.
> - Model: **v0 Max** — new route + two new structural components. Worth the credits to land it cleanly.
> - Attach this file and paste the one-liner below in the chat input.

---

## What to type in the v0 chat input (along with attaching this file)

> Build the pito command palettes described in `ui-p3.md` on a NEW route `/palettes` (file `app/palettes/page.tsx`). Do NOT modify `app/page.tsx` (`/`) or `app/start/page.tsx` (`/start`) or any shared component imported by them — the chat shell and start screen must render identically after this change.

---

## Prompt

```
# Build: pito command palettes (P3)

## What this is
Two command palette designs rendered as static mockups on a NEW route `/palettes`. We will wire them into the chat shell during the Rails port; for now we just need the visual contract.

## CRITICAL — scope
- Create a NEW route at `/palettes` (file `app/palettes/page.tsx`).
- Do NOT modify `/`, `/start`, or any component imported by them. Chat shell and start screen must render exactly as they are.
- If you need to extract a shared sub-component (e.g., a SegmentBar pattern), keep it local to `/palettes` instead of refactoring shared files.

## Reuse from P1.5 / P2 (do NOT reinvent)
- Tokyo Night palette, exact hex values
- 16px font-size everywhere; `ui-monospace, monospace`; no web fonts
- Zero rounded corners, zero CSS shadows, zero gradients
- Bar + gap + content pattern from the chatbox: 4px bar + 6px gap (root bg) + content with #1f2335 fill, content padding `10px 16px 10px 12px`

## Page layout (`/palettes`)
Single column, centered, max-width 800px:
- Page title (dim #565f89, 16px monospace, 16px padding from top): "pito — command palettes preview"
- 24px gap
- Subheading "Slash command palette  ·  opens above chatbox when `/` is typed" (dim, 16px)
- 12px gap
- Render the slash palette (see spec below)
- 48px gap
- Subheading "Ctrl+P command palette  ·  centered modal overlay" (dim, 16px)
- 12px gap
- Render the Ctrl+P palette (see spec below)
- 48px gap at the bottom

## Slash command palette spec

Structure: same bar+gap+content pattern as chatbox.
- 4px purple #bb9af7 bar on the left
- 6px gap (root bg #1a1b26)
- Content area with #1f2335 surface fill, padding 10px 16px 10px 12px
- Width: stretch to 100% of the 800px container

Content of the slash palette, top to bottom:

1. Command list (8 rows). Each row formatted as:
     /command       Description
   where `/command` is in fg #c0caf5 and the description is in dim #565f89. Pad with spaces so all descriptions left-align at the same column (e.g., column 16). Render these 8 rows exactly:

     /authenticate   Authenticate to access pito
     /channels       List your YouTube channels
     /videos         List videos for a channel
     /import         Import channel or video metadata
     /export         Export session transcript
     /help           Show help and command reference
     /clear          Clear the current session
     /new            Start a new session

   The FIRST row (`/authenticate`) is the SELECTED row. Render it with background #292e42 spanning the full content width (inside the surface fill — so background sits on top of #1f2335). Fg stays #c0caf5.

2. 8px gap

3. A 1px horizontal divider line in #292e42 spanning the content width.

4. 8px gap

5. Input echo line — shows what the user has typed:
   - Inverted-character cursor on `/` (background #bb9af7, color #1a1b26)
   - Nothing else after it (user has only typed `/`)

## Ctrl+P command palette spec (modal overlay)

Visual: render in its open state. Skip backdrop blur — just show the modal box on the page bg.

Modal box:
- Centered horizontally inside the 800px container
- Width: 600px
- Background: #1f2335
- 1px solid border in #292e42 around the entire box
- NO rounded corners, NO shadow
- Internal padding: 16px

Content of the modal, top to bottom:

1. Title row:
   - Left: `Commands` (fg #c0caf5, bold)
   - Right: `esc` (dim #565f89)
   - One single line, flex justify-between

2. 12px gap

3. Search input area:
   - Inverted-character cursor on `S` (background #bb9af7, color #1a1b26)
   - Followed by `earch` in dim #565f89 (reads "Search" with cursor on S)
   - 1px bottom border #292e42 spanning the width (gives the input a "field" baseline)
   - Vertical padding 4px

4. 16px gap

5. Section "Suggested" (label in orange-bold #ff9e64, 4px bottom margin)
   Rows (command name left fg, shortcut right dim, flex justify-between, 2px vertical padding per row):
     New session              ctrl+x n
     Switch session           ctrl+x l
     Switch channel            tab
     Switch period            shift+tab

   FIRST row of the Suggested section (`New session`) is SELECTED — background #292e42 spanning row width, fg stays #c0caf5.

6. 12px gap

7. Section "Session" (orange-bold label):
     Open editor              ctrl+x e
     Rename session           ctrl+r
     Jump to message          ctrl+x g
     Fork session
     Compact session          ctrl+x c
     Share session
     Export transcript        ctrl+x x

8. 12px gap

9. Section "Channel" (orange-bold label):
     Refresh channels
     Add channel
     Remove channel
     Toggle channel filter

10. 12px gap

11. Section "Output" (orange-bold label):
      Copy last assistant message  ctrl+x y
      Copy session transcript
      Show tool details
      Toggle sidebar           ctrl+x b
      Show timestamps

## Do NOT
- Do not add Tailwind transitions, animations, or hover effects on rows (no `hover:bg-*` etc.).
- Do not add backdrop blur or dim overlay behind Ctrl+P palette.
- Do not use any web fonts.
- Do not add rounded corners or shadows.
- Do not modify `/` or `/start`.

Render it.
```

---

## After v0 returns

1. Navigate the preview to `/palettes` to view.
2. Verify `/` and `/start` still render identically (no regressions).
3. Screenshot the result.
4. Bring it back for review.
5. Once locked, save snapshot to `~/Dev/pito/tmp/v0-snapshots/p3.zip` before P4.
