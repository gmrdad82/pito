# Phase 7.5 — Step 11e — Channel Watermark Preview

> Sub-spec of parent Step 11 (Channel Content Revamp). Builds on D9 (static JPEG
> frames committed in repo) and D21 (right-corner only — no position
> selector). Q4 resolved: expose all four timing options (`always`,
> `entire_video`, `offset_from_start`, `offset_from_end`) if YouTube allows
> them; the preview surfaces each variant via a caption.

---

## Goal

Give the user an at-a-glance preview of how the channel watermark will appear
inside a video player, both on the channel edit form (small inline preview
adjacent to the form fields) and inside the 11d preview modal (rendered at
three sizes: desktop, mobile, TV). Surfaces the timing semantics
(`always` / `entire_video` / `offset_from_start` / `offset_from_end` with
`offset_ms`) via a human-readable caption beneath the player, since the mockup
is static. Empty states cover both missing preview frames and channels with no
watermark uploaded.

The component is layout-agnostic — the parent (edit form or 11d preview modal)
decides the player size; the watermark component renders the player chrome,
overlay, and caption at whatever size it is invoked with.

## Files touched

### New

- `app/components/watermark_preview_component.rb` — ViewComponent class. Accepts
  `channel:`, `size:` (`:edit`, `:desktop`, `:mobile`, `:tv`), `timing:`,
  `offset_ms:`, optional `frame_path:` override (defaults to picking a random
  frame via the `random_watermark_frame` helper from 11d).
- `app/components/watermark_preview_component.html.erb` — markup for the faux
  player: background frame, watermark overlay at bottom-right (per D21 / open
  question 1 resolution recommended), faux controls row (play, progress,
  fullscreen icons), caption beneath the player.
- `public/preview/watermark_frames/.keep` — placeholder so the directory exists
  in git; user drops 2–4 JPEGs at roughly 1920×1080 after the spec lands. The
  `.keep` ships in this dispatch; the JPEGs are user-supplied content.
- `spec/components/watermark_preview_component_spec.rb` — component spec
  covering size variants, watermark positioning, caption formatting, both
  empty-state fallbacks.

### Modified

- `app/helpers/preview_helper.rb` — extend with
  `format_watermark_timing(timing, offset_ms)` returning a short human caption:
  - `always` / `entire_video` → `"Visible: always"`
  - `offset_from_start` → `"Visible: starts at <N>s"`
  - `offset_from_end` → `"Visible: last <N>s"`
  - `nil` / missing watermark → `"No watermark set"`
- `app/views/channels/edit.html.erb` — render
  `WatermarkPreviewComponent.new(channel:, size: :edit, timing:, offset_ms:)`
  adjacent to the watermark form fields (image upload + timing select + offset
  input). Use the `pane--standalone` form container conventions already
  established by 11a/11b (per project pane-primitive rule C).
- `app/components/channel_preview_component.rb` — 11d's preview-modal
  component. Extend to render `WatermarkPreviewComponent` inside each of its
  three layout panes (desktop / mobile / TV) when the channel has a watermark.
  The channel-preview component sets the size (`:desktop`, `:mobile`, `:tv`);
  the watermark component is layout-agnostic (per open question 4
  recommendation).
- `spec/helpers/preview_helper_spec.rb` — extend with cases for
  `format_watermark_timing` across all four timing values + nil watermark.
- `spec/system/channels/watermark_preview_spec.rb` — new system spec covering
  the critical journey: user edits a channel, sets a watermark, picks a timing
  + offset, sees the inline preview caption update; opens the 11d preview
  modal, sees the watermark in all three layout sizes.

### Cross-references (not modified here)

- 11d preview modal spec — defines `random_watermark_frame` helper this
  component reuses and the modal surface the watermark component plugs into.
- 11 parent spec (Channel Content Revamp) — D9 (static JPEG frames committed
  in repo), D21 (right-corner only, no position selector), Q4 (timing options).

## Acceptance

- [ ] `WatermarkPreviewComponent` exists at `app/components/` with the four
      `size:` variants (`:edit`, `:desktop`, `:mobile`, `:tv`) rendering at
      roughly:
  - `:edit` — inline preview, ~480×270 (16:9), fits next to the form fields
  - `:desktop` — 1280×720
  - `:mobile` — 390×220 (16:9)
  - `:tv` — 1920×1080
- [ ] Background of the faux player is a random JPEG from
      `public/preview/watermark_frames/`, picked via the
      `random_watermark_frame` helper (11d).
- [ ] Watermark overlay renders at **bottom-right** of the player (per open
      question 1 resolution: YouTube's UI shows bottom-right per image #41).
      Sizing scales naturally with the player size (TV layout = larger
      watermark, mobile = smaller); proportional, not pixel-fixed.
- [ ] Faux player controls render at the bottom of the player as a rough
      approximation (play icon, progress bar, fullscreen icon, optional
      settings/cog) — no JS, no real interactivity. Visual fidelity is rough,
      not pixel-perfect (per open question 2).
- [ ] Caption beneath the player matches the timing + offset via
      `format_watermark_timing(timing, offset_ms)`:
  - `always` / `entire_video` → `"Visible: always"`
  - `offset_from_start`, `offset_ms: 5_000` → `"Visible: starts at 5s"`
  - `offset_from_end`, `offset_ms: 15_000` → `"Visible: last 15s"`
  - Offset displayed in **seconds**, not milliseconds (per open question 3).
- [ ] Empty state: when `public/preview/watermark_frames/` contains no JPEGs,
      the component renders muted `[no preview frames yet]` (bracketed-link
      convention A: no inner padding spaces) in place of the player. Caption
      still renders (or is suppressed — caller decides).
- [ ] No-watermark state: when `channel.watermark` is absent, the mock player
      renders WITHOUT the overlay; caption reads `"No watermark set"`.
- [ ] Channel edit form (`/channels/:slug/edit`) renders the component
      adjacent to the watermark form fields, size `:edit`. The preview updates
      after a form save (no live JS preview required in this dispatch — the
      page reload after save is sufficient).
- [ ] 11d preview modal renders the watermark inside each of its three layout
      panes (desktop / mobile / TV) when the channel has a watermark.
- [ ] `format_watermark_timing` lives in `PreviewHelper` (extends 11d's
      helper module).
- [ ] Component spec covers: each `size:` variant; watermark position
      (bottom-right) across all sizes; caption matches each timing+offset
      combo; missing-frames fallback; missing-watermark fallback.
- [ ] Helper spec covers `format_watermark_timing` across all four timing
      values plus a nil-watermark caller.
- [ ] System spec covers the critical journey: set watermark, set timing +
      offset, see caption update in edit form, open preview modal, see
      watermark inside all three layouts.
- [ ] No `confirm`/`alert` JS anywhere in the new partial (project hard rule).
- [ ] Bracketed-link strings follow the no-inner-padding convention
      (`[label]`, not `[ label ]`) per project rule A.
- [ ] No new HTTP boundary booleans; if any are needed for form params they
      use `"yes"`/`"no"` per project rule E.

## Manual test recipe

Pre-requisite: user has dropped 2–4 JPEGs into
`public/preview/watermark_frames/` (e.g., screenshots from a real channel's
video at ~1920×1080). If empty, the empty-state path is what gets exercised.

1. Start the stack: `bin/dev`.
2. Sign in (Phase 6 login) and create or pick a channel.
3. Visit `/channels/<slug>/edit`.
4. Verify the watermark preview renders adjacent to the form fields at the
   `:edit` size. Verify the background is one of the dropped frames. Verify the
   faux player controls appear at the bottom.
5. **No-watermark fallback:** if the channel has no watermark, verify the
   overlay is absent and the caption reads `"No watermark set"`.
6. Upload a watermark image (PNG with transparency works best). Set timing =
   `always`. Save. Reload `/channels/<slug>/edit`. Verify:
   - The watermark renders at the bottom-right corner of the mock player.
   - Caption reads `"Visible: always"`.
7. Change timing to `offset_from_start`, offset to `5000` (ms). Save. Verify
   caption reads `"Visible: starts at 5s"`.
8. Change timing to `offset_from_end`, offset to `15000`. Save. Verify caption
   reads `"Visible: last 15s"`.
9. Open the 11d preview modal for this channel. Verify the watermark appears in
   each of the three layout panes (desktop, mobile, TV). The TV pane's
   watermark should look proportionally larger than the mobile pane's.
10. **Empty-frames fallback:** stop the server, move all JPEGs out of
    `public/preview/watermark_frames/`, restart, reload `/channels/<slug>/edit`.
    Verify the player area renders `[no preview frames yet]` muted text.
    Restore the frames and reload to confirm normal rendering returns.
11. Run the relevant specs:
    - `bundle exec rspec spec/components/watermark_preview_component_spec.rb`
    - `bundle exec rspec spec/helpers/preview_helper_spec.rb`
    - `bundle exec rspec spec/system/channels/watermark_preview_spec.rb`

Teardown: none — the preview is read-only against the channel's stored
watermark + timing fields. Reverting any changes via the edit form is the
normal path.

## Cross-stack scope

- **Rails (web):** in scope — the component, helper extension, edit-form
  integration, 11d modal integration, all specs.
- **MCP:** out of scope — the preview is a web-only visual surface. No MCP
  tool changes.
- **CLI (`pito`):** out of scope for this dispatch — the TUI does not render
  the watermark preview. (If parity is wanted later, a follow-up CLI dispatch
  decides terminal-image rendering strategy; not committed here.)
- **Website (`extras/website/`):** out of scope.

## Open questions

These need user input before the implementation dispatch fans out.

1. **Watermark corner — top-right or bottom-right?** D21 says "right-corner
   only — no position selector", but does not pin the vertical. YouTube's UI
   shows bottom-right per image #41. **Recommendation: lock to bottom-right.**
   Confirm or override.
2. **Faux player controls visual fidelity.** How closely should the mock
   controls mimic YouTube's player chrome? Pixel-perfect, or a rough
   approximation (play icon, progress bar, fullscreen)? **Recommendation:
   rough approximation, not pixel-perfect** — the preview communicates
   placement, not the player itself.
3. **Timing offset display unit.** Show `"5s"` / `"15s"` or
   `"5,000ms"` / `"15,000ms"` in the caption? **Recommendation: seconds**, for
   readability. The DB still stores `offset_ms`; the helper does the
   conversion at the render boundary.
4. **Component reuse with 11d.** Should the 11d channel-preview component
   call into `WatermarkPreviewComponent` (composition), or should the
   layout-specific sizing live inside `WatermarkPreviewComponent` itself?
   **Recommendation: composition.** `WatermarkPreviewComponent` stays
   layout-agnostic; the caller (`ChannelPreviewComponent` for the modal,
   `edit.html.erb` for the inline preview) picks the `size:`. Cleaner reuse,
   no branching inside the watermark component over which surface invoked it.
5. **TV-layout watermark size.** Scale proportionally with the 1920×1080
   mockup? **Recommendation: yes — natural scaling.** A single CSS rule sized
   relative to the player container handles all three layouts; no per-size
   override needed.
6. **Where does the watermark image come from?** The spec assumes
   `channel.watermark` is an attached image (Active Storage or similar).
   Confirm the attachment shape is already in place from 11a/11b/11c, or
   whether this sub-spec needs to declare it. If the attachment is not yet
   wired, this sub-spec depends on whichever sub-spec lands it first.
7. **Frame-picking determinism.** `random_watermark_frame` (from 11d) picks a
   random frame per render. Is that the right UX for the edit form, or should
   the edit form pick once per session / per channel and stick (so the user
   doesn't see a different background on every save)? Default: random per
   render, matching 11d. Confirm.
