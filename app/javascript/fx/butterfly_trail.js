// The idle ring bodies' TRAIL CASCADE — factored out of fx_controller.js's
// #drawButterfly (2026-07-19 perf cut, "the allocation storm"). Pure module
// (canvas-free math is trivial here, but the ctx is INJECTED, never read
// from `this`) so an op-count test can drive it with a counting Proxy ctx,
// same pattern as sky.test.js's ctx-call budget specs.
//
// THE CUT: every trail sample used to be its own createRadialGradient — a
// fresh gradient object PER SAMPLE, per body, per frame. At the old
// TRAIL_LENGTH (14) and up to 10 ring bodies under "lighter" compositing:
//   14 trail gradients + 1 glow + 1 disk = 16 gradients/body
//   16 × 10 bodies = up to 160 gradient allocations/frame (the storm)
// A gradient is the expensive allocation here (an internal color-ramp
// texture), not the fill — so trail samples now paint as PLAIN solid
// circles, their falloff carried entirely by globalAlpha (a number write,
// no allocation) built from the sample's age and the pair's own lerp color.
// The body glow + head disk KEEP their gradients (see #drawButterfly) — the
// glowing head and the soft rim are the cascade's "soul"; only the repeated
// per-sample gradient work is cut:
//   TRAIL_LENGTH (8) trail circles × 0 gradients + 2 gradients/body (glow +
//   disk) = 2 gradients/body, × 10 bodies = up to 20 gradients/frame —
//   an 8x cut on the gradient budget alone (160 → 20), comfortably past the
//   owner's ~50% work-reduction target once the sample COUNT cut (14 → 8,
//   -43%) is folded in too.
export const TRAIL_LENGTH = 8 // was 14 (owner-authorized 2026-07-19 perf cut)

// The old gradient's 0.72-stop peak (0.05·age·skyAlpha) was the brightest
// point of each sample's soft falloff; a flat circle has no falloff of its
// own, so it reads at ITS alpha everywhere — set a shade under that old
// peak (rather than matching it) so the flat disks don't read harsher than
// the gradient they replace. Consecutive samples overlap under "lighter"
// compositing, so the cascade still blooms softly where they stack.
const TRAIL_ALPHA = 0.04 // was an implicit ~0.05 gradient peak (createRadialGradient stop)

// Paints one body's trail cascade as plain alpha-faded circles (no
// gradients). `ctx` is any CanvasRenderingContext2D-shaped object (a Proxy
// in tests). `trail` is the sample buffer, oldest first — same age law as
// the gradient version: age = (i+1)/length, old → young. `pair` is the
// body's own [C1, C2] RING_PAIRS colors, lerped by age exactly as the old
// gradient's color stops were.
export function drawTrail(ctx, trail, { widthPx, heightPx, r, pair, skyAlpha = 1 }) {
  if (skyAlpha <= 0 || !trail.length) return
  const [C1, C2] = pair
  const savedAlpha = ctx.globalAlpha
  for (let i = 0; i < trail.length; i++) {
    const p = trail[i]
    const age = (i + 1) / trail.length // old → young, unchanged
    const tr = r * (0.7 + age * 1.3) // unchanged size law
    const tx = p.x * widthPx
    const ty = p.y * heightPx
    const cr = Math.round(C1[0] + (C2[0] - C1[0]) * age)
    const cg = Math.round(C1[1] + (C2[1] - C1[1]) * age)
    const cb = Math.round(C1[2] + (C2[2] - C1[2]) * age)
    ctx.globalAlpha = TRAIL_ALPHA * age * skyAlpha
    ctx.beginPath()
    ctx.arc(tx, ty, tr, 0, Math.PI * 2)
    ctx.fillStyle = `rgb(${cr} ${cg} ${cb})`
    ctx.fill()
  }
  ctx.globalAlpha = savedAlpha
}
