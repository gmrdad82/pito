# P2 — pito start screen (v0.dev prompt)

> **How to use this file**
> - Same v0.dev project as P1.x (new component or new page within it).
> - Model: **v0 Max Fast** — new screen, worth the credits.
> - Attach this file and paste the one-liner below in the chat input.

---

## What to type in the v0 chat input (along with attaching this file)

> Build the pito start screen described in `ui-p2.md`. Reuse the Chatbox component from P1.5 exactly. Render the ASCII logo JSX verbatim — do not redraw the glyphs.

---

## Prompt

```
# Build: pito start screen (P2)

## What this is
The empty/unauthenticated entry state of the pito app. Centered logo + centered chatbox + corner metadata (working dir + version). No segments, no messages, no tip line.

## Reuse from P1.5 (do NOT reinvent)
- Tokyo Night palette, exact hex values
- 16px font-size everywhere; `ui-monospace, monospace`; no web fonts
- Zero rounded corners, zero CSS shadows, zero gradients
- The Chatbox component from P1.5: 4px purple #bb9af7 bar + 6px gap (shows root bg) + content area with #1f2335 fill, content padding `10px 16px 10px 12px`

## Layout (full viewport)
Vertically:
  empty top  →  centered group  →  empty bottom  →  corner metadata pinned to viewport edges

The centered group, vertically stacked, horizontally centered. Sits at roughly 45–50% of viewport height:
  1. ASCII logo (6 rows, see literal JSX below — render verbatim, do NOT redraw)
  2. 32px vertical gap
  3. Chatbox (centered, max-width 600px)

Bottom-left of viewport (16px padding from edges):
  `~/Dev/pito` in dim #565f89

Bottom-right of viewport (16px padding from edges):
  `0.1.0` in dim #565f89

## ASCII logo — render this JSX verbatim

This is the chosen variant. Block chars (█) in pito-blue #5170ff. Shadow/box-drawing chars (╔ ╗ ╚ ╝ ║ ═) in dim #565f89. Six rows tall. Wrap in a <pre> with font-size 18px, line-height 1, no margin, `white-space: pre`. Center horizontally via parent flex/grid.

Copy this JSX exactly into your component (do not modify glyphs, spacing, or colors):

<pre style={{ fontSize: '18px', lineHeight: '1', margin: 0, whiteSpace: 'pre', fontFamily: 'ui-monospace, monospace' }}>
<span style={{ color: '#5170ff' }}>██████</span><span style={{ color: '#565f89' }}>╗ </span><span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>╗</span><span style={{ color: '#5170ff' }}>████████</span><span style={{ color: '#565f89' }}>╗ </span><span style={{ color: '#5170ff' }}>██████</span><span style={{ color: '#565f89' }}>╗ </span>{'\n'}
<span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>╔══</span><span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>╗</span><span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>║╚══</span><span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>╔══╝</span><span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>╔═══</span><span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>╗</span>{'\n'}
<span style={{ color: '#5170ff' }}>██████</span><span style={{ color: '#565f89' }}>╔╝</span><span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>║   </span><span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>║   </span><span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>║   </span><span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>║</span>{'\n'}
<span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>╔═══╝ </span><span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>║   </span><span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>║   </span><span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>║   </span><span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>║</span>{'\n'}
<span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>║     </span><span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>║   </span><span style={{ color: '#5170ff' }}>██</span><span style={{ color: '#565f89' }}>║   ╚</span><span style={{ color: '#5170ff' }}>██████</span><span style={{ color: '#565f89' }}>╔╝</span>{'\n'}
<span style={{ color: '#565f89' }}>╚═╝     ╚═╝   ╚═╝    ╚═════╝ </span>
</pre>

## Chatbox on the start screen
Use the EXACT same Chatbox component established in P1.5. Differences from the chat shell:
- max-width: 600px, centered horizontally
- Render ONLY the input line: `[purple █ block cursor] Ask anything…` (placeholder in dim #565f89)
- Do NOT render the filter context line ("Channel: … · Period: …") — no channels yet
- Do NOT render the row below the chatbox (no post-command dots, no mini status)

Result: chatbox shows exactly one line (placeholder + cursor) inside standard padding. Total chatbox height ≈ 36–40px.

## Do NOT
- Do not add a tip line below the chatbox. (Reserved for a future tip dictionary.)
- Do not render any segments or messages above the chatbox.
- Do not render the bottom status strip.
- Do not render the mini status row.
- Do not render the post-command dots.
- Do not use any web fonts.
- Do not add rounded-* or shadow-* utilities anywhere.
- Do not redraw or alter the ASCII logo. Use the JSX above verbatim.

Render it.
```

---

## After v0 returns

1. Screenshot the result.
2. Verify the logo renders with the two-tone effect (blue blocks + dim shadow chars).
3. Verify the chatbox is centered, max-width 600px, single line of placeholder.
4. Verify the corner metadata is in the right corners and dim.
5. Save a local snapshot of the v0 JSX to `tmp/v0-snapshots/start-screen-p2.tsx` before moving to P3.
