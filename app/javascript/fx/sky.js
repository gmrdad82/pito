// The natural star sky — the living background's resting mood (2.1.0 P3),
// a faithful port of pito-tui's ambient.go math onto a continuous canvas:
//
//   • IDENTITY: a star is a pure hash of its grid cell — fnv1a("row:col")
//     % DENSITY picks presence; the same hash deals tint class, size class,
//     breathing period, and phase offset. The field NEVER reshuffles; the
//     sampling grid slides for drift (col + base), positions stay stable
//     relative to the field.
//   • CLASSES (hash mod 10): 40% near-white, 30% blue-white, 20% warm
//     yellow, 10% purple — a naked-eye field, the house purple smuggled in.
//   • SIZES (hash mod 50): 70% dust, 20% double, 8% bright, 2% brilliant —
//     rarity means something.
//   • BREATHING: per-star period 0.6 + (hash%97)/97 (prime kills resonance);
//     breath = (sin((phase·0.13·period + offset)·2π)+1)/2;
//     depth = 0.35 + 0.65·breath; pulse = depth · ceiling[size].
//   • MOTION: two parallax layers (speeds 3 and 8) salted apart; canvas
//     gives sub-pixel positions free, so the TUI's cell crossfade drops.
//   • LOUDNESS LAW: color = lerp(bg → class tint, pulse) with size-capped
//     ceilings — dust whispers, brilliants glow, nothing shouts over text.
//
// Pure module: compute is deterministic and canvas-free (vitest-covered);
// drawSky paints onto any CanvasRenderingContext2D. The engine controller
// owns the clock; this owns the field.

// CELL/DENSITY are fallbacks for calling the pure functions standalone
// (vitest, no config); the engine controller threads the real values in
// from config/pito/fx.yml effects.sky.knobs (house law — fx tuning is a
// YAML edit, never a code edit).
export const CELL = 22 // px per sampling cell (the terminal's "column"); was 16 — owner-authorized 2026-07-19 perf cut, coarser cells for ~46% fewer starAt calls/frame
export const DENSITY = 80 // ~1 star per this many cells — held steady 2026-07-19 (the CELL cut alone clears the halving target; the sparser field still reads full)
export const LAYERS = [
  { speed: 3, salt: 0 },
  { speed: 8, salt: 3691 }, // the TUI's layer salt, verbatim
]

export const TINTS = [
  { r: 0xd8, g: 0xd8, b: 0xe8 }, // near-white
  { r: 0x9d, g: 0xb8, b: 0xff }, // blue-white
  { r: 0xff, g: 0xe9, b: 0xa3 }, // warm yellow
  { r: 0xbb, g: 0x9a, b: 0xf7 }, // purple
]

// size → [radius(px), brightness ceiling, flare?]
export const SIZES = [
  { radius: 0.9, ceiling: 0.45, flare: false }, // dust
  { radius: 1.5, ceiling: 0.6, flare: false }, // double
  { radius: 2.4, ceiling: 0.8, flare: true }, // bright ✧
  { radius: 3.4, ceiling: 1.0, flare: true }, // brilliant ✦
]

export const BG = { r: 0x16, g: 0x16, b: 0x1a }

// fnv1a32 over a small string — the TUI's identity hash, verbatim semantics.
export function fnv1a(str) {
  let h = 0x811c9dc5
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i)
    h = Math.imul(h, 0x01000193) >>> 0
  }
  return h >>> 0
}

// The TUI's weighted dealers, verbatim.
export function tintFor(h) {
  const v = h % 10
  if (v <= 3) return TINTS[0]
  if (v <= 6) return TINTS[1]
  if (v <= 8) return TINTS[2]
  return TINTS[3]
}

export function sizeFor(h) {
  const v = h % 50
  if (v < 35) return 0
  if (v < 45) return 1
  if (v < 49) return 2
  return 3
}

// Deterministic star lookup for a sampling cell. Same (row, col) → same
// star, forever. Returns null for empty cells (~79 of 80). `density`
// defaults to the fallback constant; the engine passes fx.yml's knob.
export function starAt(row, col, density = DENSITY) {
  const h = fnv1a(`${row}:${col}`)
  if (h % density !== 0) return null
  const sub = fnv1a(`${row}/${col}`)
  return {
    offset: ((h >>> 16) % 997) / 997,
    tint: tintFor(sub >>> 12),
    size: sizeFor(sub >>> 4),
    period: 0.6 + ((sub % 97) / 97),
    // sub-cell jitter so the field reads organic, not grid-locked (the
    // terminal had glyph variety; canvas has position freedom instead)
    jx: ((h >>> 8) % 100) / 100,
    jy: ((h >>> 4) % 100) / 100,
  }
}

// The star's brightness at a given phase — the TUI's breathing, verbatim.
export function pulseAt(star, phase) {
  const breath =
    (Math.sin((phase * 0.13 * star.period + star.offset) * 2 * Math.PI) + 1) / 2
  const depth = 0.35 + 0.65 * breath
  return depth * SIZES[star.size].ceiling
}

export function lerpColor(a, b, t) {
  return {
    r: Math.round(a.r + (b.r - a.r) * t),
    g: Math.round(a.g + (b.g - a.g) * t),
    b: Math.round(a.b + (b.b - a.b) * t),
  }
}

// All visible stars of one layer for a viewport, at a drift phase. The
// sampling grid slides by base cells; fractional drift lands in px so the
// glide is continuous (sub-pixel, no crossfade needed). `cell`/`density`
// default to the fallback constants; the engine passes fx.yml's knobs.
export function layerStars(layer, widthPx, heightPx, phase, tilt = { x: 0, y: 0 }, cell = CELL, density = DENSITY) {
  // Device-tilt parallax (owner: "can the phone movement affect the sky?"):
  // the tilt offset scales with the layer's drift speed, so near stars sway
  // more than far ones — depth you can feel in the hand.
  const tiltX = tilt.x * layer.speed
  const tiltY = tilt.y * layer.speed
  const drift = phase * layer.speed
  const base = Math.floor(drift)
  const fracPx = (drift - base) * cell
  const cols = Math.ceil(widthPx / cell) + 1
  const rows = Math.ceil(heightPx / cell)
  const stars = []
  for (let row = 0; row < rows; row++) {
    const saltedRow = row + layer.salt
    for (let col = 0; col < cols; col++) {
      const star = starAt(saltedRow, col + base, density)
      if (!star) continue
      stars.push({
        star,
        x: (col + star.jx) * cell - fracPx + tiltX,
        y: (row + star.jy) * cell + tiltY,
      })
    }
  }
  return stars
}

// Paint one frame of sky. `alpha` scales the whole pass (the crossfade mix
// knob — 1 at rest, → 0 as an enforcer takes the frame). `cell`/`density`
// default to the fallback constants; the engine passes fx.yml's knobs.
export function drawSky(ctx, widthPx, heightPx, phase, alpha = 1, tilt = { x: 0, y: 0 }, cell = CELL, density = DENSITY) {
  if (alpha <= 0) return
  for (const layer of LAYERS) {
    for (const { star, x, y } of layerStars(layer, widthPx, heightPx, phase, tilt, cell, density)) {
      const pulse = pulseAt(star, phase) * alpha
      const c = lerpColor(BG, star.tint, pulse)
      const { radius, flare } = SIZES[star.size]
      ctx.fillStyle = `rgb(${c.r} ${c.g} ${c.b})`
      ctx.beginPath()
      ctx.arc(x, y, radius, 0, Math.PI * 2)
      ctx.fill()
      if (flare && pulse > 0.5) {
        // a faint 4-point cross for the rare bright classes
        const reach = radius * 3 * pulse
        ctx.strokeStyle = `rgb(${c.r} ${c.g} ${c.b} / ${(0.35 * pulse).toFixed(3)})`
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(x - reach, y)
        ctx.lineTo(x + reach, y)
        ctx.moveTo(x, y - reach)
        ctx.lineTo(x, y + reach)
        ctx.stroke()
      }
    }
  }
}
