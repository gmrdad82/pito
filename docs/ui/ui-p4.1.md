# P4.1 — pito sidebar restructure to overlay (v0.dev edit prompt)

> **How to use this file**
> - Same v0.dev project. Edits the existing `/sidebar` route.
> - Model: **v0 Max** — structural restructure (columns → overlay). Mini will stumble.
> - Attach this file and paste the one-liner below in the chat input.

---

## What to type in the v0 chat input (along with attaching this file)

> Apply the revisions in `ui-p4.1.md` ONLY to `app/sidebar/page.tsx`. Do NOT touch `/`, `/start`, `/palettes`, or any shared component. Restructure from 2-column flex layout to overlay pattern (position: fixed sidebar). Verify no horizontal scroll on the page after rendering.

---

## Prompt

```
# Revise: pito right sidebar mode (P4 → P4.1)

Restructure the `/sidebar` route. The current 2-column flex layout is wrong — it constrains the chat shell to a narrow column, causes horizontal scrolling, and makes the chatbox/segments look cramped. Replace with the OVERLAY pattern.

The correct pattern: chat shell renders at the natural page width (same as `/`), wrapped in a container with right-padding equal to the sidebar width. The sidebar is `position: fixed` on the right edge of the viewport, overlaying anything that would otherwise sit beneath it.

## CRITICAL — scope
Modify ONLY `app/sidebar/page.tsx`. Do NOT touch `/`, `/start`, `/palettes`, or shared components.

## Layout (revised)

Root structure:
- Outer wrapper covering the entire page with `overflow-x: hidden`.
- A `<main>` element holding the chat shell content. Apply `padding-right: 480px` to this main element so chat content never slides under the sidebar.
- A SIBLING (not a flex column) `<aside>` for the sidebar with the positioning below.

## Sidebar (revised)

Positioning:
  position: fixed
  right: 0
  top: 0
  bottom: 0
  width: 480px
  background: #1a1b26
  border-left: 1px solid #292e42
  z-index: 10
  display: flex
  flex-direction: column
  overflow: hidden  (only inner body scrolls — the whole sidebar does not scroll)

Sidebar's INNER flex-column structure:

1. **Header — pinned, does NOT scroll**:
   - flex: 0 0 auto
   - padding: 16px
   - background: #1a1b26 (so content scrolling under cannot bleed through)
   - 1px bottom border #292e42 to separate from the scrollable body
   - Contents (flex row, justify-between):
     - Left: title block (2 lines)
        - Line 1: `Hollow Knight` (cyan #7dcfff, bold)
        - Line 2: `Game · imported 2026-05-18` (dim #565f89)
     - Right (aligned with Line 1): `esc` (dim #565f89)

2. **Body — scrollable**:
   - flex: 1 1 auto
   - overflow-y: auto
   - padding: 16px
   - Contains all P4 sections (Overview, Channels covering this game, Top videos, Tags, Recommendation, Quick commands) — same structure, same content, same colors.

## Chat shell (revised)
Render the chat shell from `/` (P1.5) at the natural width of `<main>` (which is now `viewport-width − 480px`). All chat-shell components must look IDENTICAL to how they appear at `/`:
  - Segments render full available width
  - Chatbox renders full available width
  - Mini status row right-aligned within the chatbox container
- Do not constrain the chat shell to any narrower column.
- The chat shell does NOT need to know about the sidebar; the `<main>` padding-right handles the offset.

## Constraints
- NO animation, transition, slide-in/out for the sidebar. Instant.
- NO horizontal scroll on the page or on any child container.
- The chat shell's vertical scroll (if any) is independent from the sidebar's body scroll — neither affects the other.
- The sidebar body's scrollbar (if shown) is internal to the sidebar; it does not produce page-level scroll.

## Width tuning
Sidebar width: lock to 480px (was variable 360-480). Wider feels right per the design review.

## Keep unchanged
All content inside the sidebar (Hollow Knight detail data, colors, sections). All chat shell content. Tokyo Night palette. Font. Everything else.

Render it.
```

---

## After v0 returns

1. Navigate the preview to `/sidebar`.
2. Verify: NO horizontal scrollbar anywhere on the page.
3. Verify: chat shell looks identical to `/` (segments and chatbox at natural width).
4. Verify: sidebar header (`Hollow Knight` + `esc`) stays visible when scrolling sidebar body.
5. Verify: scrolling inside the sidebar body does NOT scroll the chat shell or the page.
6. Verify: `/`, `/start`, `/palettes` still render identically.
7. Screenshot and bring back for review.
8. Once locked, this completes P4 and the v0 phase. Save the final snapshot to `~/Dev/pito/tmp/v0-snapshots/p4.zip`.
