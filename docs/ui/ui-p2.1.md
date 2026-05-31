# P2.1 — pito start screen refinements (v0.dev edit prompt)

> **How to use this file**
>
> - Same v0.dev project. The start screen lives at the `/start` route (in `app/start/page.tsx`).
> - Model: **v0 Auto** is fine.
> - Attach this file and paste the one-liner below in the chat input.

---

## What to type in the v0 chat input (along with attaching this file)

> Apply the revisions in `ui-p2.1.md` ONLY to the `/start` route (the file at `app/start/page.tsx`). Do NOT modify `app/page.tsx` or any shared component imported by both routes — the chat shell at `/` must stay exactly as-is. If you need to change shared behavior, copy the shared component into the `/start` scope instead.

---

## Prompt

```
# Revise: pito start screen (P2 → P2.1)

Several refinements to the start screen at /start.

## 1. Wider chatbox
Currently max-width is 600px. Change to 900px. The chatbox is the centerpiece — give it presence without going edge-to-edge.

## 2. Add the mini status row beneath the chatbox
Mirror the chat shell layout: render a row directly under the chatbox, inside the same 900px container, right-aligned. Same horizontal alignment rule as the chat shell: starts at the chatbox's surface-fill left edge (10px in from chatbox left = bar 4 + gap 6). No post-command dots on the start screen — the row has only the mini status.

Mini status content for the NOT-AUTHENTICATED state (render this in the mockup):
  `Not authenticated · ctrl+p commands`
  - `Not authenticated` in red #f7768e
  - ` · ` in dim #565f89
  - `ctrl+p` in yellow-bold #e0af68
  - `commands` in dim #565f89

AUTHENTICATED variant (do NOT render — keep as a commented-out alternative in the code):
  `Authenticated · ctrl+p commands`  — with `Authenticated` in green #9ece6a, rest unchanged.

## 3. Chatbox placeholder text — state-dependent
For the NOT-AUTHENTICATED state (render in the mockup), placeholder inside the chatbox content:
  `/authenticate 123456`  in dim #565f89

(In production this hint will randomly rotate between `/authenticate 123456` and `/authenticate` — either is fine for the mockup. Use the one above.)

AUTHENTICATED variant placeholder (commented-out alternative):
  `List top videos`  in dim #565f89.

## 4. Centered tip line below the mini status row
About 24px below the mini status row, centered horizontally within the viewport (or within the 900px container — either, since the container is itself centered). Single line:
  `● Tip — [placeholder for tip dictionary]`
- `●` in yellow #e0af68
- `Tip` in yellow #e0af68 bold
- ` — ` in dim #565f89
- `[placeholder for tip dictionary]` in dim #565f89

This is a literal placeholder string. We'll later replace with rotating content from a tips dictionary.

## 5. Bottom-left: pitomd.com link
Replace `~/Dev/pito` with a real link:
  <a href="https://pitomd.com" target="_blank" rel="noopener">pitomd.com</a>
- Default color: dim #565f89
- Hover: add underline (Tailwind `hover:underline`)
- Same 16px padding from viewport edges
- Same 16px font-size, ui-monospace

## 6. Bottom-right: keep `0.1.0` as-is
Dim #565f89, 16px padding from viewport edges.

## Keep unchanged
- ASCII logo verbatim (variant 18, pito blue blocks + dim shadow chars)
- Chatbox uses the P1.5 component pattern (4px purple bar + 6px gap + content with 10px 16px 10px 12px padding)
- Single input line inside chatbox (no filter context line)
- Tokyo Night palette, 16px font everywhere, ui-monospace
- Centered group sits at ~45–50% viewport height (will shift slightly because the group is taller now)

## CRITICAL — scope of changes
- Modify ONLY `app/start/page.tsx`.
- Do NOT modify `app/page.tsx` (the chat shell at /) or any of its files.
- Do NOT modify shared components if they're imported by both routes. If you need different behavior, COPY the component locally into the /start scope rather than editing the shared version.
- The chat shell at / must continue to render identically after this change.

Render it.
```

---

## After v0 returns

1. Navigate the preview to `/start` to view the updated screen.
2. Navigate the preview to `/` and verify the chat shell still looks identical to P1.5.
3. Screenshot both for the record.
4. If both look right, save snapshot ZIPs and move on to P3 (palettes).
