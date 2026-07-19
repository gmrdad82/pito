// The CABLE PUSH (2026-07-19, owner: "random per butterfly, random per
// payload event, random in everything — push tilt pull move whatever") —
// every received Turbo Stream now rolls a FRESH, INDEPENDENT reaction per
// flock member, replacing the old uniform `member.fly.kick(1)` that gave
// every body the identical impulse on every message (see fx_controller.js's
// "turbo:before-stream-render" listener).
//
// Factored out PURE (no DOM, no canvas, no `this`) so the distribution,
// per-member independence, and knob ranges are provable the same way
// attractor.test.js proves the flight model — a seeded `random` in, plans
// out, nothing touched.
//
// planCablePush(random, flockSize, knobs, now) → Array<Plan | null>, one
// entry per flock member, index-aligned with fx_controller's this._flock.
// Each member independently rolls a MODE, then that mode's own magnitude:
//
//   push  { mode: "push", strength }
//         An immediate kick — strength ∈ [knobs.strengthMin, strengthMax].
//         fx_controller calls member.fly.kick(strength) once; attractor.js
//         is untouched (kick() already exists).
//   pull  { mode: "pull", x, y, weight, durationMs, expiresAt }
//         A short-lived bias LEANING the member toward a random point —
//         the existing "attracted" shape (fx_controller's
//         personalityBiasTarget) fed a random target instead of the
//         pointer. Lives until expiresAt (now + durationMs).
//   tilt  { mode: "tilt", x, y, weight, durationMs, expiresAt }
//         Same shape as pull, but fx_controller feeds it through the
//         "tilted" shape — a crosswise deflection, recomputed every frame
//         off the member's OWN live position (perp() in fx_controller.js),
//         so it reads as a swerve, not a magnet.
//   move  { mode: "move", toX, toY, durationMs }
//         Forces a brand-new leg toward a random FULL-FIELD destination —
//         unlike kick()'s forced dart (a nearby hop only), this spans the
//         whole viewport. Applied via attractor.js's new leap(), a minimal
//         addition (see that file) — immediate, no expiry to track.
//   null  "sit this one out" — the member does nothing for this event
//         (owner: randomness includes not reacting at all).
//
// Mode selection is a flat, equal-weight roll across the 5 outcomes above —
// a deliberate constant, not an fx.yml knob (only the strength/duration
// RANGES are owner-tunable per the flock's cable-push knobs; ask before
// promoting the mode weights themselves to config).
const MODES = ["push", "pull", "tilt", "move", "sit"]

// Field margins mirror attractor.js's own clamp (0.08..0.92) so a "pull"/
// "tilt"/"move" target never asks a member to lean or fly past the edge
// the flight model already enforces.
const FIELD_MIN = 0.08
const FIELD_MAX = 0.92

function randomInRange(random, min, max) {
  return min + random() * (max - min)
}

function randomPoint(random) {
  return {
    x: randomInRange(random, FIELD_MIN, FIELD_MAX),
    y: randomInRange(random, FIELD_MIN, FIELD_MAX),
  }
}

export function planCablePush(random, flockSize, knobs = {}, now = 0) {
  const strengthMin = knobs.strengthMin ?? 0.35
  const strengthMax = knobs.strengthMax ?? 0.85
  const durationMsMin = knobs.durationMsMin ?? 400
  const durationMsMax = knobs.durationMsMax ?? 1600

  return Array.from({ length: flockSize }, () => {
    const mode = MODES[Math.floor(random() * MODES.length)]
    if (mode === "sit") return null

    if (mode === "push") {
      return { mode, strength: randomInRange(random, strengthMin, strengthMax) }
    }

    const durationMs = randomInRange(random, durationMsMin, durationMsMax)
    if (mode === "move") {
      const { x, y } = randomPoint(random)
      return { mode, toX: x, toY: y, durationMs }
    }

    // pull / tilt: a short-lived bias fx_controller's #wander applies every
    // frame until expiresAt, then the member reclaims its normal lean.
    const { x, y } = randomPoint(random)
    const weight = randomInRange(random, strengthMin, strengthMax)
    return { mode, x, y, weight, durationMs, expiresAt: now + durationMs }
  })
}

// The pure expiry check pull/tilt plans share with fx_controller's #wander —
// a plan with no expiresAt (push/move, both one-shot) is never "live".
export function isPlanLive(plan, now) {
  return !!plan && typeof plan.expiresAt === "number" && now < plan.expiresAt
}
