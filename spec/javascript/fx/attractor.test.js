import { describe, it, expect } from "vitest"
import { createButterfly } from "fx/attractor"

// Deterministic "random" sequence for reproducible flights.
function seq(values) {
  let i = 0
  return () => values[i++ % values.length]
}

describe("the butterfly", () => {
  it("stays inside the viewport margins forever", () => {
    const b = createButterfly({ random: seq([0.01, 0.99, 0.5, 0.33, 0.77]) })
    for (let now = 0; now < 120_000; now += 33) {
      const { x, y } = b.update(now)
      expect(x).toBeGreaterThanOrEqual(0.05)
      expect(x).toBeLessThanOrEqual(0.95)
      expect(y).toBeGreaterThanOrEqual(0.05)
      expect(y).toBeLessThanOrEqual(0.95)
    }
  })

  it("flies in legs of UNEVEN tempo — fast and very slow segments coexist", () => {
    const b = createButterfly({ random: Math.random })
    const durations = new Set()
    let last = b.state().leg
    for (let now = 0; now < 90_000; now += 16) {
      b.update(now)
      const leg = b.state().leg
      if (leg !== last) {
        durations.add(leg.duration < 1200 ? "fast" : leg.duration > 4000 ? "slow" : "mid")
        last = leg
      }
    }
    expect(durations.has("fast")).toBe(true)
    expect(durations.has("slow")).toBe(true)
  })

  it("eases: velocity is small at leg edges, larger mid-leg", () => {
    const b = createButterfly({ random: seq([0.9, 0.9, 0.5, 0.5, 0.5]) })
    b.update(0)
    const early = Math.hypot(b.update(50).vx, b.update(80).vy)
    const leg = b.state().leg
    const mid = b.update(leg.start + leg.duration / 2)
    const midSpeed = Math.hypot(mid.vx, mid.vy)
    expect(midSpeed).toBeGreaterThan(early)
  })

  it("kick() raises impulse and forces the next leg to dart", () => {
    const b = createButterfly({ random: seq([0.99, 0.99, 0.99, 0.99]) })
    b.update(0)
    b.kick()
    expect(b.update(16).impulse).toBeGreaterThan(0.9)
    const current = b.state().leg
    b.update(current.start + current.duration + 1) // roll into the next leg
    expect(b.state().leg.duration).toBeLessThanOrEqual(1100)
  })

  it("bias leans the flight toward the hand without owning it", () => {
    const free = createButterfly({ random: seq([0.5, 0.5, 0.5]) })
    const leaned = createButterfly({ random: seq([0.5, 0.5, 0.5]) })
    free.update(0)
    leaned.update(0)
    const f = free.update(500)
    const l = leaned.update(500, { x: 1, y: 1, weight: 0.33 })
    expect(l.x).toBeGreaterThan(f.x)
    expect(l.x).toBeLessThan(1)
  })
})
