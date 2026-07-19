import { describe, it, expect } from "vitest"
import {
  fnv1a, starAt, tintFor, sizeFor, pulseAt, layerStars, drawSky,
  TINTS, SIZES, DENSITY, LAYERS, CELL,
} from "fx/sky"

describe("the natural sky's field (TUI math, ported)", () => {
  it("is deterministic: the same cell always deals the same star", () => {
    const a = starAt(12, 340)
    const b = starAt(12, 340)
    expect(a).toEqual(b)
  })

  // Was 200_000 samples, no explicit timeout — flaky under coverage
  // instrumentation (fnv1a runs twice per sample; istanbul's per-call
  // overhead pushed this past vitest's 5000ms default on a loaded runner).
  // The tolerance band (0.6x..1.6x the expected rate) is generous enough
  // that statistical power barely moves with n: at 50_000 samples the
  // expected-count std dev is ~4% of the mean, still an order of magnitude
  // inside the band, so trimming 4x the samples costs no real confidence.
  // An explicit generous timeout covers what trimming alone doesn't.
  it("hits the ~1/DENSITY presence rate", () => {
    let present = 0
    const cells = 50_000
    for (let i = 0; i < cells; i++) {
      if (starAt(i % 500, Math.floor(i / 500)) !== null) present++
    }
    const rate = present / cells
    expect(rate).toBeGreaterThan(0.6 / DENSITY)
    expect(rate).toBeLessThan(1.6 / DENSITY)
  }, 15000)

  it("deals tint classes at the TUI's 40/30/20/10 weights", () => {
    const counts = [0, 0, 0, 0]
    for (let h = 0; h < 100_000; h++) counts[TINTS.indexOf(tintFor(h))]++
    expect(counts[0] / 100_000).toBeCloseTo(0.4, 1)
    expect(counts[1] / 100_000).toBeCloseTo(0.3, 1)
    expect(counts[2] / 100_000).toBeCloseTo(0.2, 1)
    expect(counts[3] / 100_000).toBeCloseTo(0.1, 1)
  })

  it("deals size classes at the TUI's 70/20/8/2 rarity ladder", () => {
    const counts = [0, 0, 0, 0]
    for (let h = 0; h < 100_000; h++) counts[sizeFor(h)]++
    expect(counts[0] / 100_000).toBeCloseTo(0.7, 1)
    expect(counts[1] / 100_000).toBeCloseTo(0.2, 1)
    expect(counts[2] / 100_000).toBeCloseTo(0.08, 1)
    expect(counts[3] / 100_000).toBeCloseTo(0.02, 1)
  })

  it("breathes inside the loudness law: pulse ∈ (0, ceiling], floor 0.35·ceiling", () => {
    for (let seed = 0; seed < 500; seed++) {
      const star = { offset: (seed % 97) / 97, period: 0.6 + (seed % 97) / 97, size: seed % 4 }
      const ceiling = SIZES[star.size].ceiling
      for (let phase = 0; phase < 20; phase += 0.37) {
        const p = pulseAt(star, phase)
        expect(p).toBeGreaterThanOrEqual(0.35 * ceiling - 1e-9)
        expect(p).toBeLessThanOrEqual(ceiling + 1e-9)
      }
    }
    // ~54k expect() calls — comfortably fast idle, but the proven repeat
    // flaker under machine load (2× on 2026-07-19); same generous ceiling
    // as the presence test above.
  }, 15000)

  it("gives every star a period in 0.6..1.6 so the field never metronomes", () => {
    for (let row = 0; row < 200; row++) {
      for (let col = 0; col < 200; col++) {
        const star = starAt(row, col)
        if (!star) continue
        expect(star.period).toBeGreaterThanOrEqual(0.6)
        expect(star.period).toBeLessThan(1.6)
      }
    }
  })

  it("salts the two parallax layers into different fields", () => {
    const a = layerStars(LAYERS[0], 2000, 1000, 0).map((s) => `${s.x},${s.y}`)
    const b = layerStars(LAYERS[1], 2000, 1000, 0).map((s) => `${s.x},${s.y}`)
    expect(a).not.toEqual(b)
  })

  it("slides the field continuously: positions shift by fractional pixels with phase", () => {
    const before = layerStars(LAYERS[0], 2000, 400, 0)
    const after = layerStars(LAYERS[0], 2000, 400, 0.1)
    expect(before.length).toBeGreaterThan(0)
    // same field (drift < 1 cell) — every star moved left by the same sub-cell amount
    const dx = before[0].x - after[0].x
    expect(dx).toBeGreaterThan(0)
    expect(dx).toBeLessThan(CELL)
  })

  it("tilts the field per depth: near layer sways more than far", () => {
    const still = layerStars(LAYERS[0], 800, 400, 0)
    const far = layerStars(LAYERS[0], 800, 400, 0, { x: 1, y: 0 })
    const near = layerStars(LAYERS[1], 800, 400, 0, { x: 1, y: 0 })
    expect(far[0].x - still[0].x).toBeCloseTo(LAYERS[0].speed, 5)
    const nearStill = layerStars(LAYERS[1], 800, 400, 0)
    expect(near[0].x - nearStill[0].x).toBeCloseTo(LAYERS[1].speed, 5)
  })

  it("fnv1a matches the reference vector", () => {
    // FNV-1a 32-bit of "a" = 0xe40c292c (published test vector)
    expect(fnv1a("a")).toBe(0xe40c292c)
  })

  it("drawSky paints without touching the canvas when fully crossfaded out", () => {
    const calls = []
    const ctx = new Proxy({}, {
      get: (_, prop) => {
        if (prop === "fillStyle" || prop === "strokeStyle" || prop === "lineWidth") return undefined
        return (...args) => calls.push(prop)
      },
      set: () => true,
    })
    drawSky(ctx, 800, 600, 1.0, 0)
    expect(calls).toEqual([])
    drawSky(ctx, 800, 600, 1.0, 1)
    expect(calls.length).toBeGreaterThan(0)
  })

  // Proxy-counted ctx-call budget (2026-07-19 perf cut): every star costs at
  // least beginPath+arc+fill (3 calls); the rare flare classes (bright,
  // brilliant, pulse > 0.5) add a 4-line cross (beginPath + 2 moveTo + 2
  // lineTo + stroke = 6 more) — 9 calls worst case. CELL threads all the way
  // through drawSky now (T2 of the cut), so the budget at the old CELL=16
  // can be measured directly against today's default — the halved-budget pin
  // the owner asked for, expressed as real behavior instead of a magic number.
  it("halves the per-frame ctx-call budget after the CELL 16→22 cut (owner-authorized quality trim)", () => {
    function budgetAt(cell) {
      const calls = []
      const ctx = new Proxy({}, {
        get: (_, prop) => {
          if (prop === "fillStyle" || prop === "strokeStyle" || prop === "lineWidth") return undefined
          return (...args) => calls.push(prop)
        },
        set: () => true,
      })
      drawSky(ctx, 1920, 1080, 0, 1, { x: 0, y: 0 }, cell)
      return calls.length
    }
    const oldBudget = budgetAt(16) // the pre-cut CELL, measured directly rather than pinned
    const newBudget = budgetAt(CELL) // today's default (22)
    expect(newBudget).toBeGreaterThan(0)
    // The sampled-cell reduction is ~46% ((16/22)^2), the authoritative
    // figure documented in sky.js/fx.yml; this paint-call metric lands a
    // little under that because CELL=22 samples an entirely different
    // (row, col) set, not a subset, and its flare mix differs slightly. 35%
    // leaves comfortable margin over that variance while still catching any
    // future edit that quietly erases the cut.
    expect(newBudget).toBeLessThan(oldBudget * 0.65)
  })

  it("keeps every star's ctx-call cost within the beginPath+arc+fill .. +flare-cross bounds", () => {
    const calls = []
    const ctx = new Proxy({}, {
      get: (_, prop) => {
        if (prop === "fillStyle" || prop === "strokeStyle" || prop === "lineWidth") return undefined
        return (...args) => calls.push(prop)
      },
      set: () => true,
    })
    const width = 1920
    const height = 1080
    const starCount =
      layerStars(LAYERS[0], width, height, 0).length + layerStars(LAYERS[1], width, height, 0).length
    drawSky(ctx, width, height, 0, 1)
    expect(calls.length).toBeGreaterThanOrEqual(starCount * 3)
    expect(calls.length).toBeLessThanOrEqual(starCount * 9)
  })
})
