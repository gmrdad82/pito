// glow.js — the GLOW mood: a spotlight-punch look over a darkened,
// desaturated game cover. Locked look (owner 2026-07-13, approved via the
// gallery demo tmp/fx/glow.html), adapted from pitomd's fx.css:346-370
// (.section[data-cursor="glow"]::before) onto this registry's per-module-
// canvas contract (see ./index.js). Plain 2D canvas — a soft radial reveal
// doesn't need a shader, unlike lens/duotone/water's WebGL passes.
//
// The look: draw the cover dim + desaturated as the base, then punch ONE
// glow per flock member through a radial-gradient mask that reveals the LIT
// (full-brightness, full-saturation) cover underneath — same linear falloff
// to transparent at 62% of the radius as the CSS reference (color-mix(...),
// transparent 62%). Sizes are staggered per flock index (SIZE_TIERS below)
// so no two glows are ever the same size (owner: "different sizes that
// don't collide").
//
// Motion is deliberately SLOWER than the flock itself (owner: "move
// slower"): each glow eases toward its flock anchor with its own heavy
// low-pass (FOLLOW_RATE, ~0.03/frame) stacked on top of the flock's own
// 0.06/frame smoothing (fx_controller.js #wander), so glows drift dreamily
// even when the flock darts.
//
// Self-contained per THE RENDERER CONTRACT in ./index.js: no imports, no DOM
// queries outside this module's own canvases, no listeners, no pointer
// reads — attractor.flock replaces the cursor entirely (F7/P6).

const DEFAULT_DIM = 0.35 // base darkness; mirrors the gallery's .fx-dim overlay alpha (35%)
const DEFAULT_GLOW_ALPHA = 0.85 // peak strength of the lit reveal
const BASE_SATURATE = 0.9 // mirrors the gallery's .fx-cover filter: saturate(0.9)
const FOLLOW_RATE = 0.03 // heavy low-pass — slower than the flock's own 0.06 (owner: "move slower")
const FADE_STOP = 0.62 // radial-gradient falloff: opaque at the center, transparent by 62% of the radius (pitomd fx.css:351-370 / tmp/fx/glow.html)

// Radius fractions of the canvas's short side, one per flock index —
// staggered so no two glows are ever the same size (owner: "different sizes
// that don't collide"). The flock is 3-6 members (fx_controller.js); this
// array covers the max.
const SIZE_TIERS = [0.34, 0.22, 0.28, 0.18, 0.25, 0.2]

function clamp01(v) {
  return v < 0 ? 0 : v > 1 ? 1 : v
}

// object-fit: cover placement for the loaded image inside a box — scaled
// and centered; the canvas's own bounds clip whatever spills past the edge.
function coverRect(imgW, imgH, boxW, boxH) {
  const scale = Math.max(boxW / imgW, boxH / imgH)
  const dw = imgW * scale
  const dh = imgH * scale
  return { dx: (boxW - dw) / 2, dy: (boxH - dh) / 2, dw, dh }
}

function makeScratchCanvas(w, h) {
  const c = document.createElement("canvas")
  c.width = Math.max(1, Math.round(w))
  c.height = Math.max(1, Math.round(h))
  return { canvas: c, ctx: c.getContext("2d") }
}

export default {
  create({ width, height, dpr, knobs, covers }) {
    if (!covers || covers.length === 0) return null

    const canvas = document.createElement("canvas")
    const ctx = canvas.getContext("2d")
    if (!ctx) return null

    const k = knobs || {}
    const dim = clamp01(k.dim ?? DEFAULT_DIM)
    const glowAlpha = clamp01(k.glow_alpha ?? DEFAULT_GLOW_ALPHA)
    const baseBrightnessPct = Math.round((1 - dim) * 100)
    const baseSaturatePct = Math.round(BASE_SATURATE * 100)

    const pixelRatio = dpr || 1
    canvas.width = Math.max(1, Math.round(width * pixelRatio))
    canvas.height = Math.max(1, Math.round(height * pixelRatio))

    // Two scratch canvases for the mask-composite reveal: `lit` holds the
    // full-brightness cover, masked in place by `mask`'s per-glow radial
    // gradients, then drawn back onto the visible canvas at glowAlpha.
    let { canvas: lit, ctx: litCtx } = makeScratchCanvas(canvas.width, canvas.height)
    let { canvas: mask, ctx: maskCtx } = makeScratchCanvas(canvas.width, canvas.height)

    let destroyed = false
    let loaded = false
    const img = new Image()
    img.addEventListener(
      "load",
      () => {
        if (destroyed) return
        loaded = true
      },
      { once: true },
    )
    img.src = covers[0]

    // Per-glow eased position — the heavy low-pass toward each flock
    // anchor (FOLLOW_RATE), seeded lazily on the first frame() that sees it
    // so a late-arriving flock member doesn't animate in from a phantom
    // (0.5, 0.5).
    const eased = []

    function frame(_dtMs, _phase, attractor) {
      if (destroyed || !loaded) return

      const flock =
        attractor && attractor.flock && attractor.flock.length
          ? attractor.flock
          : [attractor || { x: 0.5, y: 0.5 }]

      flock.forEach((body, i) => {
        if (!eased[i]) eased[i] = { x: body.x, y: body.y }
        eased[i].x += (body.x - eased[i].x) * FOLLOW_RATE
        eased[i].y += (body.y - eased[i].y) * FOLLOW_RATE
      })

      const { dx, dy, dw, dh } = coverRect(
        img.naturalWidth || 1,
        img.naturalHeight || 1,
        canvas.width,
        canvas.height,
      )

      // Base: darkened + desaturated cover.
      ctx.clearRect(0, 0, canvas.width, canvas.height)
      ctx.filter = `saturate(${baseSaturatePct}%) brightness(${baseBrightnessPct}%)`
      ctx.drawImage(img, dx, dy, dw, dh)
      ctx.filter = "none"

      // Lit layer: the same cover at full brightness/saturation.
      litCtx.clearRect(0, 0, lit.width, lit.height)
      litCtx.drawImage(img, dx, dy, dw, dh)

      // Mask: one radial gradient per flock member, staggered sizes, linear
      // falloff to transparent at FADE_STOP of its radius (the gallery's
      // "transparent 62%" math) — additive so overlapping glows read
      // brighter where they cross.
      maskCtx.clearRect(0, 0, mask.width, mask.height)
      maskCtx.globalCompositeOperation = "lighter"
      const shortSide = Math.min(canvas.width, canvas.height)
      eased.forEach((pos, i) => {
        const radius = SIZE_TIERS[i % SIZE_TIERS.length] * shortSide
        const px = pos.x * canvas.width
        const py = pos.y * canvas.height
        const gradient = maskCtx.createRadialGradient(px, py, 0, px, py, radius)
        gradient.addColorStop(0, "rgba(255, 255, 255, 1)")
        gradient.addColorStop(FADE_STOP, "rgba(255, 255, 255, 0)")
        gradient.addColorStop(1, "rgba(255, 255, 255, 0)")
        maskCtx.fillStyle = gradient
        maskCtx.beginPath()
        maskCtx.arc(px, py, radius, 0, Math.PI * 2)
        maskCtx.fill()
      })
      maskCtx.globalCompositeOperation = "source-over"

      // Punch the lit layer through the mask, then composite onto the dark
      // base at glowAlpha — the art reads brighter only inside each glow.
      litCtx.globalCompositeOperation = "destination-in"
      litCtx.drawImage(mask, 0, 0)
      litCtx.globalCompositeOperation = "source-over"

      ctx.globalAlpha = glowAlpha
      ctx.drawImage(lit, 0, 0)
      ctx.globalAlpha = 1
    }

    function resize(w, h) {
      canvas.width = Math.max(1, Math.round(w * pixelRatio))
      canvas.height = Math.max(1, Math.round(h * pixelRatio))
      ;({ canvas: lit, ctx: litCtx } = makeScratchCanvas(canvas.width, canvas.height))
      ;({ canvas: mask, ctx: maskCtx } = makeScratchCanvas(canvas.width, canvas.height))
    }

    function ready() {
      return loaded && !destroyed
    }

    function destroy() {
      destroyed = true
    }

    return { canvas, frame, resize, ready, destroy }
  },
}
