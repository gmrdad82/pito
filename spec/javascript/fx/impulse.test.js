import { describe, it, expect } from "vitest"
import { planCablePush, isPlanLive } from "fx/impulse"

// Deterministic "random" sequence for reproducible rolls (attractor.test.js's
// own seq() pattern) — each mode consumes a different, KNOWN number of
// random() calls (mode roll, then that mode's own magnitude rolls), so every
// exact-shape test below hand-picks a sequence long enough for exactly one
// member's plan.
function seq(values) {
  let i = 0
  return () => values[i++ % values.length]
}

// Field margins mirror attractor.js's own clamp (0.08..0.92) — impulse.js
// keeps its own copy for the same reason attractor.js does: a pull/tilt/move
// target must never ask a member to lean or fly past the edge the flight
// model enforces.
const FIELD_MIN = 0.08
const FIELD_MAX = 0.92

const KNOBS = { strengthMin: 0, strengthMax: 1, durationMsMin: 1000, durationMsMax: 2000 }

describe("planCablePush — exact shapes per mode (seeded)", () => {
  it("push: an immediate kick, strength rolled in the knob range", () => {
    // mode roll 0.0 -> floor(0*5)=0 -> push; strength roll 0.5 -> midpoint.
    const [plan] = planCablePush(seq([0.0, 0.5]), 1, KNOBS, 0)
    expect(plan).toEqual({ mode: "push", strength: 0.5 })
  })

  it("pull: a short-lived bias toward a random point, weighted, with an absolute expiresAt", () => {
    // mode roll 0.25 -> floor(1.25)=1 -> pull; duration 0.5 -> midpoint (1500);
    // point (0.0, 1.0) -> field's own min/max corners; weight 0.5 -> midpoint.
    const [plan] = planCablePush(seq([0.25, 0.5, 0.0, 1.0, 0.5]), 1, KNOBS, 1000)
    expect(plan.mode).toBe("pull")
    expect(plan.x).toBeCloseTo(FIELD_MIN)
    expect(plan.y).toBeCloseTo(FIELD_MAX)
    expect(plan.weight).toBeCloseTo(0.5)
    expect(plan.durationMs).toBeCloseTo(1500)
    expect(plan.expiresAt).toBeCloseTo(2500) // now(1000) + durationMs(1500)
  })

  it("tilt: same shape as pull, distinguished only by mode", () => {
    // mode roll 0.45 -> floor(2.25)=2 -> tilt.
    const [plan] = planCablePush(seq([0.45, 0.5, 0.5, 0.5, 0.5]), 1, KNOBS, 0)
    expect(plan.mode).toBe("tilt")
    expect(plan).toHaveProperty("x")
    expect(plan).toHaveProperty("y")
    expect(plan).toHaveProperty("weight")
    expect(plan).toHaveProperty("expiresAt")
  })

  it("move: forces a new leg toward a random FULL-FIELD destination, no expiry to track", () => {
    // mode roll 0.65 -> floor(3.25)=3 -> move; duration 0.5 -> midpoint;
    // point (0.2, 0.8).
    const [plan] = planCablePush(seq([0.65, 0.5, 0.2, 0.8]), 1, KNOBS, 0)
    expect(plan.mode).toBe("move")
    expect(plan.toX).toBeCloseTo(FIELD_MIN + 0.2 * (FIELD_MAX - FIELD_MIN))
    expect(plan.toY).toBeCloseTo(FIELD_MIN + 0.8 * (FIELD_MAX - FIELD_MIN))
    expect(plan.durationMs).toBeCloseTo(1500)
    expect(plan).not.toHaveProperty("expiresAt") // one-shot — #wander never reads it
  })

  it('"sit this one out": the member does nothing this event', () => {
    // mode roll 0.85 -> floor(4.25)=4 -> sit; consumes exactly ONE random()
    // call — a second value in the array would only matter if sit leaked
    // into rolling a magnitude too.
    const [plan] = planCablePush(seq([0.85]), 1, KNOBS, 0)
    expect(plan).toBeNull()
  })
})

describe("planCablePush — distribution and independence (real randomness)", () => {
  it("every mode (push, pull, tilt, move, sit) turns up over many events", () => {
    const seen = new Set()
    for (let i = 0; i < 2000; i++) {
      const [plan] = planCablePush(Math.random, 1, {}, 0)
      seen.add(plan ? plan.mode : "sit")
    }
    expect(seen).toEqual(new Set(["push", "pull", "tilt", "move", "sit"]))
  })

  it("members roll INDEPENDENTLY within the same event — not a flock-wide uniform reaction", () => {
    const plans = planCablePush(Math.random, 40, {}, 0)
    const shapes = new Set(plans.map((p) => JSON.stringify(p)))
    // The old behavior was ONE shape for the whole flock (kick(1) on every
    // member); 40 independent rolls landing on a single identical shape is
    // astronomically unlikely (5 modes, each with its own continuous
    // magnitude rolls) — this is the regression this suite exists to catch.
    expect(shapes.size).toBeGreaterThan(1)
  })

  it("fresh rolls every event — back-to-back calls don't repeat the same plan set", () => {
    const first = planCablePush(Math.random, 10, {}, 0)
    const second = planCablePush(Math.random, 10, {}, 0)
    expect(JSON.stringify(first)).not.toBe(JSON.stringify(second))
  })
})

describe("planCablePush — knob ranges are honored", () => {
  const KNOBS_TIGHT = { strengthMin: 0.2, strengthMax: 0.3, durationMsMin: 500, durationMsMax: 600 }

  it("push.strength, pull/tilt.weight and .durationMs, move.toX/toY all stay within their configured ranges", () => {
    const now = 12345
    for (let i = 0; i < 500; i++) {
      const [plan] = planCablePush(Math.random, 1, KNOBS_TIGHT, now)
      if (!plan) continue // sit-out
      if (plan.mode === "push") {
        expect(plan.strength).toBeGreaterThanOrEqual(0.2)
        expect(plan.strength).toBeLessThanOrEqual(0.3)
      }
      if (plan.mode === "move") {
        expect(plan.toX).toBeGreaterThanOrEqual(FIELD_MIN)
        expect(plan.toX).toBeLessThanOrEqual(FIELD_MAX)
        expect(plan.toY).toBeGreaterThanOrEqual(FIELD_MIN)
        expect(plan.toY).toBeLessThanOrEqual(FIELD_MAX)
        expect(plan.durationMs).toBeGreaterThanOrEqual(500)
        expect(plan.durationMs).toBeLessThanOrEqual(600)
      }
      if (plan.mode === "pull" || plan.mode === "tilt") {
        expect(plan.x).toBeGreaterThanOrEqual(FIELD_MIN)
        expect(plan.x).toBeLessThanOrEqual(FIELD_MAX)
        expect(plan.y).toBeGreaterThanOrEqual(FIELD_MIN)
        expect(plan.y).toBeLessThanOrEqual(FIELD_MAX)
        expect(plan.weight).toBeGreaterThanOrEqual(0.2)
        expect(plan.weight).toBeLessThanOrEqual(0.3)
        expect(plan.durationMs).toBeGreaterThanOrEqual(500)
        expect(plan.durationMs).toBeLessThanOrEqual(600)
        expect(plan.expiresAt).toBeCloseTo(now + plan.durationMs)
      }
    }
  })

  it("falls back to sensible defaults when no knobs are supplied", () => {
    const [plan] = planCablePush(seq([0.0, 1.0]), 1, undefined, 0)
    expect(plan.mode).toBe("push")
    expect(plan.strength).toBeLessThanOrEqual(0.85) // default strengthMax
    expect(plan.strength).toBeGreaterThanOrEqual(0.35) // default strengthMin
  })
})

describe("isPlanLive — expiry semantics", () => {
  it("null/undefined plans, and one-shot plans without an expiresAt, are never live", () => {
    expect(isPlanLive(null, 100)).toBe(false)
    expect(isPlanLive(undefined, 100)).toBe(false)
    expect(isPlanLive({ mode: "push", strength: 0.5 }, 100)).toBe(false)
    expect(isPlanLive({ mode: "move", toX: 0.5, toY: 0.5, durationMs: 500 }, 100)).toBe(false)
  })

  it("a pull/tilt plan is live strictly before its expiresAt, dead at and after it", () => {
    const plan = { mode: "pull", x: 0.5, y: 0.5, weight: 0.5, durationMs: 100, expiresAt: 200 }
    expect(isPlanLive(plan, 100)).toBe(true)
    expect(isPlanLive(plan, 199)).toBe(true)
    expect(isPlanLive(plan, 200)).toBe(false) // boundary: now < expiresAt, not <=
    expect(isPlanLive(plan, 300)).toBe(false)
  })

  it("ties directly to planCablePush's own output — live at roll time, dead past its own duration", () => {
    // mode 0.25 -> pull; duration 0.5 -> midpoint of [1000,2000] = 1500.
    const [plan] = planCablePush(seq([0.25, 0.5, 0.5, 0.5, 0.5]), 1, KNOBS, 1000)
    expect(isPlanLive(plan, 1000)).toBe(true) // rolled at now=1000, still fresh
    expect(isPlanLive(plan, 2499)).toBe(true) // 1ms before expiresAt (2500)
    expect(isPlanLive(plan, 2500)).toBe(false) // expiresAt itself
  })
})
