// AURORA — the cover-less mood for ANALYZE contexts (owner verdict
// 2026-07-13, locked look + name from the regenerated demo
// tmp/fx/aurora.html): 2-4 blurred hue blobs, deliberately staggered sizes,
// each drifting toward its own flock member instead of an autonomous walker
// of its own. Where GLOW punches light through cover art and COVER WALL
// floats game covers, ANALYZE surfaces have no cover art to pin a mood to —
// aurora paints directly with color: the demo's four baked hues (pito-blue,
// purple, cyan, pink), each blob easing toward its flock anchor with a
// heavy low-pass so the field drifts dreamily even when the flock darts
// (mirrors glow.js's FOLLOW_RATE shape, a touch looser per the owner's
// spec).
//
// DOM/CSS engine per THE RENDERER CONTRACT's cover_wall variant in
// ./index.js: instead of a canvas, `element` is a self-built DOM node the
// compositor mounts and drives via style.opacity; frame() updates custom
// properties instead of drawing. Unlike cover_wall (which leans on
// .pito-fx-wall/.pito-fx-wall__tile rules in application.css), aurora sets
// EVERY visual property inline on the divs it creates in create() — no
// <style> tag, no stylesheet edit, fully self-contained per the contract's
// "no imports, no DOM queries outside the own element, no listeners" rule.
// Custom properties still carry the per-frame position, mirroring
// cover_wall's --wall-x/--wall-y pattern: --blob-tx/--blob-ty are set on
// each blob's own inline style and read back by that same div's own inline
// transform (var() resolves fine inside an element's own style attribute,
// no external CSS rule required).

const BLOB_COUNT_MAX = 6
const BLOB_COUNT_MIN = 4

// Heavy low-pass toward each flock member — aurora drifts dreamily even
// when the flock darts, same shape as glow.js's FOLLOW_RATE (0.03) but a
// touch looser per the owner's spec (~0.04/frame).
const FOLLOW_RATE = 0.04

// The demo's four hues, baked per blob index (tmp/fx/aurora.html #b1..#b4)
// — never re-derived from theme tokens, so the mood reads identically
// regardless of data-theme/data-accent.
const BLOB_COLORS = ["#5170ff", "#bb9af7", "#7dcfff", "#ff6ec7", "#9ece6a", "#ff9e64"] // pito-blue, purple, cyan, pink, green, orange

// Demo's per-blob opacity (tmp/fx/aurora.html #b1..#b4 inline styles),
// index-aligned with BLOB_COLORS/DEFAULT_SIZES — scaled by the `alpha` knob.
const BASE_ALPHAS = [0.5, 0.48, 0.3, 0.34, 0.4, 0.36]

// Demo's per-blob vmax width fractions (tmp/fx/aurora.html #b1..#b4) — the
// "never the same size" stagger the owner locked. Overridable per-blob via
// the size_0..size_3 knobs; params will iterate later.
const DEFAULT_SIZES = [0.58, 0.4, 0.5, 0.3, 0.46, 0.35]

const DEFAULT_BLUR_PX = 48 // demo: .aurora { filter: blur(48px) }
const DEFAULT_ALPHA = 1 // global multiplier over BASE_ALPHAS

function clamp01(v) {
  return v < 0 ? 0 : v > 1 ? 1 : v
}

// CSS vmax = the LARGER of viewport width/height — matches the demo's
// `58vmax` etc. sizing so size_0..size_3 stay drop-in compatible with the
// demo's numbers.
function vmaxOf(w, h) {
  return Math.max(w, h) || 1
}

export default {
  create({ width = 0, height = 0, knobs = {} } = {}) {
    const k = knobs || {}
    const sizeFracs = [
      k.size_0 ?? DEFAULT_SIZES[0],
      k.size_1 ?? DEFAULT_SIZES[1],
      k.size_2 ?? DEFAULT_SIZES[2],
      k.size_3 ?? DEFAULT_SIZES[3],
    ]
    const blurPx = k.blur ?? DEFAULT_BLUR_PX
    const alphaMul = clamp01(k.alpha ?? DEFAULT_ALPHA)

    // Fills the compositor's fixed, full-viewport wall layer (mirrors the
    // demo's .aurora positioning, translated to inline style since this
    // module may not touch application.css).
    const element = document.createElement("div")
    element.style.position = "absolute"
    element.style.inset = "0"
    element.style.overflow = "hidden"
    element.style.pointerEvents = "none"
    element.style.filter = `blur(${blurPx}px)`

    let w = width
    let h = height

    // Always build the full BLOB_COUNT_MAX set — cheap (four divs) — and
    // toggle visibility per frame from the live flock size instead of
    // churning DOM nodes every time the flock count changes.
    const blobs = BLOB_COLORS.map((color, i) => {
      const el = document.createElement("div")
      el.style.position = "absolute"
      el.style.top = "0"
      el.style.left = "0"
      el.style.borderRadius = "50%"
      el.style.background = `radial-gradient(circle, ${color}, transparent 60%)`
      el.style.willChange = "transform"
      // --blob-tx/--blob-ty are custom properties on THIS SAME element,
      // consumed by THIS SAME element's transform — no stylesheet involved.
      el.style.transform = "translate(var(--blob-tx, 0px), var(--blob-ty, 0px))"
      const alpha = clamp01(BASE_ALPHAS[i] * alphaMul)
      el.style.opacity = String(alpha)
      element.appendChild(el)
      return { el, sizeFrac: sizeFracs[i], sizePx: 0, alpha, eased: null }
    })

    function applySizes(nw, nh) {
      w = nw
      h = nh
      const vmax = vmaxOf(w, h)
      blobs.forEach((blob) => {
        blob.sizePx = vmax * blob.sizeFrac
        blob.el.style.width = `${blob.sizePx.toFixed(2)}px`
        blob.el.style.height = `${blob.sizePx.toFixed(2)}px`
      })
    }
    applySizes(width, height)

    // 4-6 balls, rolled ONCE per instance (owner 2026-07-13: "4-6 random,
    // different size") — independent of flock size.
    const count = BLOB_COUNT_MIN + Math.floor(Math.random() * (BLOB_COUNT_MAX - BLOB_COUNT_MIN + 1))

    function frame(_dtMs, _phase, attractor) {
      // FLOCK-DRIVEN, no walkers of its own (owner 2026-07-13): reads
      // attractor.flock directly; falls back to the single attractor point
      // when no flock is present, same fallback shape as glow/globs/duotone.
      const flock =
        attractor && attractor.flock && attractor.flock.length
          ? attractor.flock
          : [attractor || { x: 0.5, y: 0.5 }]


      blobs.forEach((blob, i) => {
        if (i >= count) {
          blob.el.style.opacity = "0"
          return
        }
        const body = flock[i % flock.length]
        // Blobs beyond the flock share an anchor — spread them apart with
        // a fixed per-index offset so they never stack.
        const spread = i >= flock.length ? 0.12 + (i % 3) * 0.05 : 0
        const ax = Math.min(0.95, body.x + spread)
        const ay = Math.max(0.05, body.y - spread)
        // Seeded lazily on the first sighting so a blob never animates in
        // from a phantom (0.5, 0.5) — same shape as glow.js's `eased`.
        if (!blob.eased) blob.eased = { x: ax, y: ay }
        blob.eased.x += (ax - blob.eased.x) * FOLLOW_RATE
        blob.eased.y += (ay - blob.eased.y) * FOLLOW_RATE

        // Center the blob on its flock member (translate moves the div's
        // top-left corner, so offset by half the blob's own size).
        const px = blob.eased.x * w - blob.sizePx / 2
        const py = blob.eased.y * h - blob.sizePx / 2
        blob.el.style.setProperty("--blob-tx", `${px.toFixed(2)}px`)
        blob.el.style.setProperty("--blob-ty", `${py.toFixed(2)}px`)
        blob.el.style.opacity = String(blob.alpha)
      })
    }

    function resize(nw, nh) {
      applySizes(nw, nh)
    }

    function ready() {
      return true // no assets — CSS-engine blobs are ready on arrival
    }

    function destroy() {
      element.remove()
    }

    return { element, frame, resize, ready, destroy }
  },
}
