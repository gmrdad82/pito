# /channels Wave A — visual validation playbook

**Date:** 2026-05-19 **Surfaces:** /channels page, all sections below the ID
card shelf hairline

## How to use this playbook

1. Open https://app.pitomd.com/channels in your browser
2. For each section below, look at the rendered variants side-by-side
3. Pick the variant you want to keep — note it in chat with the master agent
4. After all picks, the master dispatches a cleanup pass to delete unused
   variants

The Wave A fanout dispatched 8 parallel agents. Each agent built one section
below the ID card shelf with 2–3 visual variants. The variants render
simultaneously on `/channels` so you can compare them in one scroll-through.

## Section validations

### 1. Basics (4 stat totals)

- **Variant 1 — Inline row:** single horizontal row,
  `▲ 2.3M subs   ▲ 412 videos   ▲ 1.2B views   ▲ joined 2014`
- **Variant 2 — Card grid:** four stat blocks with background + border, each
  block stacks label / value / delta
- **Variant 3 — Separator row:** four stats separated by vertical hairlines, no
  background fill
- **Component dir:** `app/components/channels/basics_section_*`
- **Decision:** pick V1 / V2 / V3 + any tweaks

### 2. Top Content

- **Variant 1 — Vertical list:** thumbnail + title + views + channel badge per
  row, scrollable column
- **Variant 2 — Grid:** tile layout (cover / title / view count under each
  tile), responsive grid
- **Variant 3 — Compact table:** title | views | channel columns, dense rows
- **Component dir:** `app/components/channels/top_content_*`
- **Decision:** pick V1 / V2 / V3 + any tweaks

### 3. Window Summaries

- **Variant 1 — Tab strip:** five tabs (7d / 28d / 3m / 365d / alltime),
  selected tab reveals the three deltas
- **Variant 2 — Side-by-side cards:** all five windows visible at once, each
  card carries its three deltas inline
- **Component dir:** `app/components/channels/window_summaries_*`
- **Decision:** pick V1 / V2 + any tweaks

### 4. Geography

- **Variant 1 — Ranked list with bars:** country rows ordered by share, inline
  proportional bar per row
- **Variant 2 — Horizontal bar chart:** standalone bar chart, one bar per
  country, axis on the left
- **Variant 3 — Treemap blocks:** area-proportional rectangles, country label
  inside each block
- **Component dir:** `app/components/channels/geography_*`
- **Decision:** pick V1 / V2 / V3 + any tweaks

### 5. Demographics

- **Variant 1 — Population pyramid:** male left / female right, age buckets
  stacked vertically
- **Variant 2 — Side-by-side grouped bars:** age buckets along the x-axis,
  gender as grouped bars per bucket
- **Component dir:** `app/components/channels/demographics_*`
- **Decision:** pick V1 / V2 + any tweaks

### 6. Device Type

- **Variant 1 — Donut chart:** conic-gradient ring, legend with bracketed
  labels to the right
- **Variant 2 — Horizontal bar list:** one row per device, inline proportional
  bar, percentage at the right edge
- **Component dir:** `app/components/channels/device_type_*`
- **Decision:** pick V1 / V2 + any tweaks

### 7. Heatmap (when viewers on YouTube)

- **Variant 1 — Color-intensity grid:** 7 rows (days of week) × 24 columns
  (hours), cell color encodes viewer count
- **Variant 2 — Sparkline per day:** one sparkline row per day, hour on x-axis,
  viewers on y-axis
- **Component dir:** `app/components/channels/heatmap_*`
- **Decision:** pick V1 / V2 + any tweaks

### 8. Traffic Sources

- **Variant 1 — Ranked list + search terms below:** primary sources list on
  top, search-term sub-section stacked below
- **Variant 2 — Split two-column:** sources ranked on the left column, search
  terms ranked on the right column
- **Component dir:** `app/components/channels/traffic_sources_*`
- **Decision:** pick V1 / V2 + any tweaks

## Open items (not in this fanout)

- **A5** — Trend indicators (architect spec only; pending Wave A4 lock)
- **A11** — Latest content shelf (uses existing shelf primitive, no variant
  pick needed)
- **A12** — Sync UI per chip
- **A13** — Multi-channel picker modal
- **A14** — Revoke flow UI

## Outstanding question chain for the architect

After the user picks variants, the master agent:

1. Deletes the unused variant components + their templates + their specs
2. Wires the chosen variants into the canonical `/channels` view (removes the
   side-by-side rendering scaffold)
3. Surfaces any remaining design ambiguities discovered during validation
   (token gaps, spacing inconsistencies, copy questions)

## Slack / chat update protocol

The master agent posts per-section landings to chat AND the `#pito-app` Slack
channel as each background agent reports completion. The user receives a
concise heads-up per section so they can begin reviewing variants before the
whole fanout lands.

## Cross-references

- Spec:
  `docs/plans/beta/37-channels-revamp/specs/02-wave-a2-chip-wiring-basics.md`
- Handoff:
  `docs/orchestration/handoff-2026-05-19-channels-and-live-updates.md`
- Design tokens: `docs/design.md` (color, spacing, type rules apply to every
  variant)
