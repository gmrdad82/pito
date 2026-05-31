# P1.3 — pito chat shell structural refactor (v0.dev edit prompt)

> **How to use this file**
>
> - Same v0.dev project as P1 / P1.1 / P1.2.
> - Model: **v0 Max Fast** (do NOT use Auto — these are design-taste / structural changes; Mini will miss the alignment invariant).
> - Attach this file and paste the one-liner below in the chat input.

---

## What to type in the v0 chat input (along with attaching this file)

> Apply the revisions in `ui-p1.3.md` to the current component. Two structural changes: refactor the Segment component to use a separate bar+gap pattern, and rebuild the chatbox to match. Watch the alignment invariant noted in section 1.

---

## Prompt

```
# Revise: pito chat shell (P1.2 → P1.3)

Two structural changes to bring the visual style closer to the OpenCode TUI reference.

## 1. Restructure the <Segment> component — bar + gap + content
Currently the colored bar is implemented as `border-left: 3px solid <color>`, attached directly to the content's left edge. Change this to a separate, gap-spaced bar.

New layout:
  [ BAR (4px wide, full height) ] [ GAP (12px empty space) ] [ CONTENT ]

Implementation:
- Outer wrapper: flex row, `align-items: stretch` (bar stretches to full content height).
- First child (bar):
    width: 4px
    background: the `border` prop color when set; transparent when null
- Spacer: 12px gap (flex `gap: 12px` is fine, OR an explicit 12px-wide spacer div)
- Last child (content):
    flex: 1
    padding: 6px 16px 6px 0  (top / right / bottom / left=0 — bar+gap handles left)
    NO left-padding inside content

Background prop behavior:
- When `background` is set, apply it to the OUTER wrapper — fill covers the bar area, the gap, AND the content. Continuous block with a colored stripe on the left.
- When null, outer wrapper is transparent.

CRITICAL invariant: Even when `border` is null, still render the bar (transparent) + the 12px gap. This keeps borderless prose horizontally aligned with bordered content. All segments share the same left x-coordinate for their content.

## 2. Chatbox: drop top/right/left borders, more compact, same bar+gap pattern
Currently the chatbox has 1px borders on top, right, left + a 3px purple left bar. Change to:

- Remove all 4 1px borders. No frame.
- Use the same [BAR 4px purple #bb9af7] [GAP 12px] [CONTENT] structure as the new Segment.
- Content area has background fill #1f2335.
- The outer wrapper background also #1f2335 — fill extends behind the bar + gap + content, so the whole chatbox row is one continuous surface with the purple stripe on the left.
- Content area internal padding: 8px top, 16px right, 8px bottom, 0 left.
- The two content lines (placeholder + filter context) sit on consecutive lines with default line-height — no extra gap between them.
- Target total chatbox height: roughly 55–65px. Currently it's ~140px, so cut by more than half.

## 3. Align the row BELOW the chatbox with the chatbox CONTENT
The post-command dots and mini status row that sits beneath the chatbox should be aligned with the chatbox's content area, not flush with the bar. I.e., the dots' left edge should sit at the same x-coordinate as where the "Ask anything…" placeholder text begins (4px bar + 12px gap = 16px in from the chatbox's left edge).

## Keep unchanged
Palette, font, all content (no text changes), segment border/background MAPPING (user = orange, tool-output = purple + #24283b, etc.), viewport horizontal padding.

Render it.
```

---

## After v0 returns

1. Screenshot the result.
2. Bring it back to Claude for review against this spec.
3. Verify the alignment invariant: bordered and borderless segments should have their content starting at the same x-coordinate.
4. If P1.3 lands clean, P2 is next (start screen).
