# P1.2 — pito chat shell layout fixes (v0.dev edit prompt)

> **How to use this file**
> - Same v0.dev project as P1 / P1.1.
> - Model: **v0 Auto** (it'll likely pick Mini, which is fine — these are surgical layout edits).
> - Attach this file and add the one-liner instruction below in the chat input.

---

## What to type in the v0 chat input (along with attaching this file)

> Apply the revisions in `ui-p1.2.md` to the current component. Four targeted layout changes, no new components.

---

## Prompt

```
# Revise: pito chat shell (P1.1 → P1.2)

Apply these four targeted changes against the current component:

## 1. In-progress segment: drop the border
The `⠋ Building…` segment currently has a purple 3px left-border. Remove it. Render through <Segment border={null} background={null}> like the other prose segments. The braille spinner + shimmering "Building…" carry the visual weight on their own.

## 2. Move the post-command dots OUT of the chatbox
The animated 8-dot sweep currently sits inside the chatbox at bottom-left. Remove it from inside the chatbox. Instead, place it on a NEW row BELOW the chatbox, left-aligned, at the same horizontal padding as the chatbox.

## 3. Chatbox: full width
The chatbox should span the full content width (same horizontal padding as the message area — i.e., viewport edge minus the standard horizontal padding). Currently it's compact and leaves dead space on the right. Make it `flex: 1` / `width: 100%` within its row.

## 4. Mini status: new row, simplified
Move the mini status OUT of being inline with the chatbox. It now lives on the SAME new row as the post-command dots from change #2, right-aligned.

New mini status content (drop the bullet glyph entirely):
  `Connected · 3 notifications · ctrl+p commands`
  - `Connected` in green #9ece6a
  - ` · ` separators in dim #565f89
  - `3 notifications` in cyan #7dcfff
  - `ctrl+p` in yellow-bold #e0af68
  - `commands` in dim #565f89

Disconnected variant (keep as commented-out code, not rendered): replace just the word "Connected" with "Disconnected" in red #f7768e. Rest of the line is unchanged.

## Resulting bottom-region layout (top to bottom)
1. Scrollable message area
2. Chatbox row — full width — contains placeholder text + filter context line ("Channel: @gmrdad82 · Period: 7d") only. Nothing else inside.
3. Status row — same horizontal padding as the chatbox — contains:
   - Left: animated post-command dots `········` with the cyan shimmer sweep
   - Right: mini status text
   - Flex row with justify-between, vertically centered against each other.

## Keep unchanged
Everything else: palette, typography, segment component, content, border/background table for the other segments, all spacing rules.

Render it.
```

---

## After v0 returns

1. Screenshot the result.
2. Bring it back to Claude for review against this spec.
3. If close: write a Mini-tier surgical edit prompt or move on to P2 (start screen).
