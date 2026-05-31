# P1.5 — pito chat shell gap + padding refinements (v0.dev edit prompt)

> **How to use this file**
>
> - Same v0.dev project as P1 / P1.1 / P1.2 / P1.3 / P1.4.
> - Model: **v0 Auto** (these are number swaps — Mini territory).
> - Attach this file and paste the one-liner below in the chat input.

---

## What to type in the v0 chat input (along with attaching this file)

> Apply the revisions in `ui-p1.5.md` to the current component. Halve the bar↔content gap (12 → 6px), add 12px internal left padding to all segment content (and the chatbox content), and re-align the row below the chatbox to match. Verify the math sanity check before rendering.

---

## Prompt

```
# Revise: pito chat shell (P1.4 → P1.5)

Two small refinements.

## 1. Halve the gap

Currently the gap between bar and content is 12px. Change to 6px.

  [ BAR 4px ] [ GAP 6px (shows root #1a1b26) ] [ CONTENT ]

Apply identically to <Segment> AND the chatbox.

## 2. Add internal left padding to the content child

Currently content padding is `10px 16px 10px 0` (top / right / bottom / left=0). Text touches the content area's left edge — for tool-output cards this means text kisses the surface fill's left edge.

Change content padding to: `10px 16px 10px 12px`

This applies to:
- All Segment variants (bordered AND borderless — the alignment invariant must hold)
- The chatbox content area

Effect:
- Tool-output text no longer touches the surface fill's left edge (12px inset inside the colored card).
- Borderless prose segments now have content sitting 12px inside the where-gap-ends point — still horizontally aligned with bordered content because every segment shares the same internal padding.
- Chatbox "Ask anything…" and "Channel: @gmrdad82 · Period: 7d" lines sit 12px inside the surface fill.

## 3. Re-align the row below the chatbox

The post-command dots + mini status row that sits beneath the chatbox should now align with the chatbox's TEXT (not just the content area's left edge). I.e., the dots' left edge should sit at 22px in from the chatbox's left edge (4 bar + 6 gap + 12 content-padding-left).

## Math sanity check (verify before rendering)

Total left offset for any text, from segment edge:
  bar (4) + gap (6) + content padding-left (12) = 22px

Must be identical across:
- User message segments (orange bar)
- Tool-output cards (purple bar + surface fill)
- Borderless prose / thought / status footer / in-progress segments
- Chatbox content
- Row below chatbox (dots aligned to this same 22px)

## Keep unchanged
Everything else: palette, font, content, background-on-content-only rule, 10px breathing room inside chatbox between input line and filter context line, segment border/background mapping.

Render it.
```

---

## After v0 returns

1. Screenshot the result.
2. Verify the gap is now visibly thinner (6px).
3. Verify text inside the tool-output card is inset from the surface fill's left edge.
4. Verify the row below the chatbox aligns with the chatbox's text (22px from chatbox left).
5. If clean, move on to P2 (start screen).
