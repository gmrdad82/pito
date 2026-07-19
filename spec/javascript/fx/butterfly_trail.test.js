import { describe, it, expect } from "vitest"
import { TRAIL_LENGTH, drawTrail } from "fx/butterfly_trail"

// Counting Proxy ctx (sky.test.js:104-117 pattern): properties assigned as
// plain data (fillStyle, globalAlpha) resolve to undefined and are never
// counted; anything CALLED as a canvas method is recorded by name. A gradient
// object has its own addColorStop calls too, so createRadialGradient must
// hand back a stub that swallows those without throwing.
function countingCtx() {
  const calls = []
  const ctx = new Proxy({}, {
    get: (_, prop) => {
      if (prop === "fillStyle" || prop === "strokeStyle" || prop === "globalAlpha") return undefined
      if (prop === "createRadialGradient") {
        return (...args) => {
          calls.push(prop)
          return { addColorStop: () => {} }
        }
      }
      return (...args) => calls.push(prop)
    },
    set: () => true,
  })
  return { ctx, calls }
}

function trailOf(length) {
  return Array.from({ length }, (_, i) => ({ x: 0.1 + i * 0.01, y: 0.2 + i * 0.01 }))
}

const PAIR = [[187, 154, 247], [81, 112, 255]] // purple / pito-blue, RING_PAIRS[0]

describe("the butterfly ring trail (2026-07-19 perf cut — gradients out of the cascade)", () => {
  it("holds TRAIL_LENGTH at 8 (was 14) — the shared constant #wander's cap and #drawButterfly's age law both read", () => {
    expect(TRAIL_LENGTH).toBe(8)
  })

  it("never allocates a gradient: the trail budget is zero createRadialGradient calls, at any sample count", () => {
    for (const length of [0, 1, TRAIL_LENGTH, 14]) {
      const { ctx, calls } = countingCtx()
      drawTrail(ctx, trailOf(length), { widthPx: 1920, heightPx: 1080, r: 20, pair: PAIR, skyAlpha: 1 })
      expect(calls.filter((c) => c === "createRadialGradient")).toEqual([])
    }
  })

  it("costs exactly beginPath+arc+fill per sample — a deterministic 3x call budget, no more, no less", () => {
    const { ctx, calls } = countingCtx()
    drawTrail(ctx, trailOf(TRAIL_LENGTH), { widthPx: 1920, heightPx: 1080, r: 20, pair: PAIR, skyAlpha: 1 })
    expect(calls.length).toBe(TRAIL_LENGTH * 3)
    expect(calls).toEqual(
      Array.from({ length: TRAIL_LENGTH }, () => ["beginPath", "arc", "fill"]).flat()
    )
  })

  // The arithmetic the report cites: old cost was TRAIL_LENGTH(14) gradients
  // + 1 glow + 1 disk = 16 gradients/body; new cost is 0 trail gradients + 1
  // glow + 1 disk = 2 gradients/body (glow/disk aren't this module's concern
  // — they stay in fx_controller.js#drawButterfly — but the trail's own
  // contribution dropping from 14 to 0 is exactly what this asserts).
  it("drops the per-body gradient contribution from the old TRAIL_LENGTH(14) to zero", () => {
    const oldTrailGradients = 14 // the pre-cut per-sample gradient, one per old trail length
    const { ctx, calls } = countingCtx()
    drawTrail(ctx, trailOf(TRAIL_LENGTH), { widthPx: 1920, heightPx: 1080, r: 20, pair: PAIR, skyAlpha: 1 })
    const newTrailGradients = calls.filter((c) => c === "createRadialGradient").length
    expect(newTrailGradients).toBe(0)
    expect(newTrailGradients).toBeLessThan(oldTrailGradients)
  })

  it("does nothing at skyAlpha 0 — same zero-alpha bail as drawSky", () => {
    const { ctx, calls } = countingCtx()
    drawTrail(ctx, trailOf(TRAIL_LENGTH), { widthPx: 1920, heightPx: 1080, r: 20, pair: PAIR, skyAlpha: 0 })
    expect(calls).toEqual([])
  })

  it("does nothing on an empty trail (a freshly spawned body hasn't sampled yet)", () => {
    const { ctx, calls } = countingCtx()
    drawTrail(ctx, [], { widthPx: 1920, heightPx: 1080, r: 20, pair: PAIR, skyAlpha: 1 })
    expect(calls).toEqual([])
  })

  it("restores ctx.globalAlpha after painting, so it never leaks into the glow/disk fills that follow", () => {
    const alphaLog = []
    let current = 1
    const ctx = new Proxy({}, {
      get: (_, prop) => {
        if (prop === "globalAlpha") return current
        if (prop === "fillStyle") return undefined
        if (prop === "createRadialGradient") return () => ({ addColorStop: () => {} })
        return () => {}
      },
      set: (_, prop, value) => {
        if (prop === "globalAlpha") {
          current = value
          alphaLog.push(value)
        }
        return true
      },
    })
    ctx.globalAlpha = 1 // the save()'d baseline #drawButterfly's outer ctx.save() establishes
    drawTrail(ctx, trailOf(TRAIL_LENGTH), { widthPx: 1920, heightPx: 1080, r: 20, pair: PAIR, skyAlpha: 1 })
    expect(ctx.globalAlpha).toBe(1)
    // it did vary mid-paint (per-sample falloff), not just a no-op
    expect(alphaLog.some((a) => a !== 1)).toBe(true)
  })

  it("lerps oldest→youngest sample color exactly along the pair, matching the old gradient stops' law", () => {
    const seen = []
    const ctx = new Proxy({}, {
      get: (_, prop) => {
        if (prop === "fillStyle") return undefined
        if (prop === "globalAlpha") return undefined
        return () => {}
      },
      set: (_, prop, value) => {
        if (prop === "fillStyle") seen.push(value)
        return true
      },
    })
    drawTrail(ctx, trailOf(2), { widthPx: 100, heightPx: 100, r: 10, pair: PAIR, skyAlpha: 1 })
    // sample 0 of 2: age = 1/2 = 0.5 → exact midpoint of C1/C2
    expect(seen[0]).toBe("rgb(134 133 251)")
    // sample 1 of 2: age = 2/2 = 1 → pure C2
    expect(seen[1]).toBe(`rgb(${PAIR[1][0]} ${PAIR[1][1]} ${PAIR[1][2]})`)
  })
})
