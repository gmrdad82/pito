// COVER WALL — the shelf mood (game lists, channel libraries): the listed
// games' covers floating at hashed depths, swaying with the butterfly
// instead of the pointer (F7), each drifting on its own slow keyframe
// phase. DOM/CSS engine: the compositor mounts `element` and drives its
// opacity; we only write custom properties per tile plus two per frame.
//
// Deterministic: each cover's position/depth/size hashes from its index +
// path, and the collision relaxation below (F13, owner 2026-07-13) walks a
// FIXED probe spiral — no Math.random anywhere — so the same message
// rebuilds the exact same wall forever.

function hash(str) {
  let h = 0x811c9dc5
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i)
    h = Math.imul(h, 0x01000193) >>> 0
  }
  return h >>> 0
}

// Matches the 180×240 similar-game / channel-games cover convention (see
// .pito-fx-wall__tile's aspect-ratio) — collision boxes use the same ratio
// the rendered tiles are forced into, so "no overlap" is actually true.
const COVER_ASPECT = 3 / 4

// Deterministic relaxation spiral (golden-angle rotation, growing radius):
// probe 0 is always the raw hash-seeded spot; probe N>0 walks the same fixed
// offsets for every tile, so identical covers always relax identically.
const GOLDEN_ANGLE = 2.399963229728653 // radians, ~137.5deg
const MAX_PROBES = 24
const MAX_SHRINK_ROUNDS = 8

function probeOffset(step, spread) {
  if (step === 0) return { dx: 0, dy: 0 }
  const radius = spread * Math.sqrt(step / MAX_PROBES)
  const angle = step * GOLDEN_ANGLE
  return { dx: Math.cos(angle) * radius, dy: Math.sin(angle) * radius }
}

function clamp(value, min, max) {
  if (max < min) return min
  return Math.min(Math.max(value, min), max)
}

function rectsOverlap(a, b, gap) {
  return !(
    a.x + a.w + gap <= b.x ||
    b.x + b.w + gap <= a.x ||
    a.y + a.h + gap <= b.y ||
    b.y + b.h + gap <= a.y
  )
}

// Walk the probe spiral around (baseX, baseY) for a w×h rect that overlaps
// nothing already `placed` (plus `gap` breathing room), clamped to the wall's
// usable area. Returns the free rect, or null if every probe collided.
function findFreeSpot(baseX, baseY, w, h, placed, gap, bounds, spread) {
  for (let step = 0; step < MAX_PROBES; step++) {
    const { dx, dy } = probeOffset(step, spread)
    const x = clamp(baseX + dx, bounds.xMin, bounds.xMin + bounds.xSpan - w)
    const y = clamp(baseY + dy, bounds.yMin, bounds.yMin + bounds.ySpan - h)
    const candidate = { x, y, w, h }
    if (!placed.some((p) => rectsOverlap(candidate, p, gap))) return candidate
  }
  return null
}

export default {
  create({ width = 0, height = 0, knobs = {}, covers = [] } = {}) {
    if (!covers.length) return null

    const element = document.createElement("div")
    element.className = "pito-fx-wall"
    const maxTiles = knobs.max_tiles || 14
    const shown = covers.slice(0, maxTiles)
    let loaded = 0

    // FEW COVERS → BIG TILES (owner 2026-07-13): never double art to fill
    // space — scale what's there. Size is viewport-relative (fraction of the
    // short side, so a desktop wall is never a sparse strip of thumbnails).
    const vmin = Math.min(width, height) || 800
    const boost = Math.sqrt(maxTiles / shown.length)
    const ceilingCap = knobs.size_ceiling_frac || 0.45
    // SIZES BETWEEN A FLOOR AND A CEILING (owner 2026-07-13): tiles are no
    // longer a uniform size — each one's fraction is hash-picked inside
    // [floorFrac, ceilFrac]. size_frac stays the baseline (the range's top),
    // floor_frac (default 0.14) is the new bottom; the same count-boost
    // scales the WHOLE range as the shelf thins, and size_ceiling_frac hard-
    // caps both ends.
    const floorFrac = Math.min((knobs.floor_frac || 0.14) * boost, ceilingCap)
    const ceilFrac = Math.min((knobs.size_frac || 0.22) * boost, ceilingCap)

    // NO TILE OVERLAP (owner 2026-07-13): a small gap (~2% of the viewport's
    // short side) between every pair of placed tiles, and a usable area
    // matching the old hashed band (4%..96% x, 4%..86% y) so tiles never
    // hang off the wall's edge.
    const gap = vmin * 0.02
    const bounds = {
      xMin: 0.04 * width,
      xSpan: 0.92 * width,
      yMin: 0.04 * height,
      ySpan: 0.82 * height,
    }
    const spiralSpread = vmin * 0.3
    const placed = []

    shown.forEach((path, i) => {
      const seed = hash(`${i}:${path}`)
      const depth = 0.35 + (((seed >>> 16) % 60) / 100) // 0.35..0.95, far->near
      const sizeMix = ((seed >>> 24) % 100) / 100 // second hash draw, size variety
      const col = (seed % 100) / 100
      const row = ((seed >>> 8) % 100) / 100
      const baseX = bounds.xMin + col * bounds.xSpan
      const baseY = bounds.yMin + row * bounds.ySpan

      // Depth still modulates within the range: closer tiles (higher depth)
      // lean toward ceilFrac, farther ones toward floorFrac; sizeMix (a
      // second, independent hash draw) keeps two same-depth tiles from
      // landing on the exact same size.
      let frac = floorFrac + (ceilFrac - floorFrac) * (0.5 * sizeMix + 0.5 * ((depth - 0.35) / 0.6))

      // COLLISION-FREE PLACEMENT (owner 2026-07-13): seed the candidate from
      // the hash, spiral-probe up to MAX_PROBES fixed offsets around it for a
      // spot that overlaps no earlier tile; if nothing in the spiral is
      // free, shrink the tile toward floorFrac and spiral again; if it still
      // won't fit at the floor, drop the tile rather than let it overlap.
      let rect = null
      for (let round = 0; round < MAX_SHRINK_ROUNDS; round++) {
        const w = Math.round(vmin * frac)
        const h = Math.round(w / COVER_ASPECT)
        rect = findFreeSpot(baseX, baseY, w, h, placed, gap, bounds, spiralSpread)
        if (rect) break
        if (frac <= floorFrac) break
        frac = Math.max(floorFrac, frac * 0.85)
      }
      if (!rect) return // no collision-free spot even at the floor size — skip

      placed.push(rect)

      const tile = document.createElement("img")
      tile.className = "pito-fx-wall__tile"
      tile.src = path
      tile.alt = ""
      // NOT loading=lazy: detached lazy images never fetch, and ready()
      // would wait forever. Fourteen strip variants load eagerly, cheap.
      tile.decoding = "async"
      tile.style.setProperty("--wall-x", `${rect.x.toFixed(2)}px`)
      tile.style.setProperty("--wall-y", `${rect.y.toFixed(2)}px`)
      tile.style.setProperty("--wall-depth", depth.toFixed(3))
      tile.style.setProperty("--wall-size", `${rect.w}px`)
      tile.style.setProperty("--wall-delay", `${-(((seed >>> 4) % 900) / 100).toFixed(2)}s`)
      tile.addEventListener("load", () => { loaded++ }, { once: true })
      element.appendChild(tile)
    })

    // FILM GRAIN (owner 2026-07-13): a subtle SVG-turbulence overlay on top
    // of every tile, adapted from pitomd's .grain — appended last so it
    // always paints above the covers.
    const grain = document.createElement("div")
    grain.className = "pito-fx-wall__grain"
    element.appendChild(grain)

    return {
      element,
      frame(_dtMs, _phase, attractor) {
        // The butterfly's sway, depth-scaled per tile by CSS calc.
        element.style.setProperty("--wall-ax", (attractor.x - 0.5).toFixed(4))
        element.style.setProperty("--wall-ay", (attractor.y - 0.5).toFixed(4))
        // The SECOND motion layer follows the second butterfly (owner
        // 2026-07-13: tiles react to the flock, never the device directly)
        // — two independent flock-driven sways make the parallax read.
        const second = (attractor.flock && attractor.flock[1]) || attractor
        element.style.setProperty("--wall-tx", ((second.x - 0.5) * 2).toFixed(4))
        element.style.setProperty("--wall-ty", ((second.y - 0.5) * 2).toFixed(4))
      },
      resize() {},
      ready() {
        return loaded > 0
      },
      destroy() {
        element.remove()
      },
    }
  },
}
