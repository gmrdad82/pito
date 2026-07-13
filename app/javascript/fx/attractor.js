// The BUTTERFLY (2.1.0 P6) — the autonomous body every enforcer follows
// instead of the pointer (F7). It travels in LEGS of deliberately uneven
// tempo (owner: "fast segments, then slow ones, then fast ones, then very
// slow ones"): each leg picks a destination and a duration class —
//
//   darting   0.5–1.1s   (25%)
//   cruising  1.6–3.2s   (45%)
//   drifting  4.5–8.0s   (30%)
//
// — and eases through it (easeInOutCubic), so motion surges and rests like
// something alive, never metronomic. Real pito events kick() it: the next
// leg darts and the impulse flag decays for the renderers (water splashes,
// smoke bursts, plasma pulls).
//
// update(now, bias) returns {x, y, vx, vy, impulse} in 0..1 viewport space.
// bias = {x, y, weight} lets the desktop mouse LEAN the flight a fraction
// toward the hand — influence, never obedience.

const TEMPOS = [
  { min: 500, max: 1100, weight: 25 }, // darting
  { min: 1600, max: 3200, weight: 45 }, // cruising
  { min: 4500, max: 8000, weight: 30 }, // drifting
]

function easeInOutCubic(t) {
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2
}

export function createButterfly({ random = Math.random } = {}) {
  let x = 0.5
  let y = 0.5
  let vx = 0
  let vy = 0
  let impulse = 0
  let leg = null
  let forceDart = false

  function pickTempo() {
    if (forceDart) {
      forceDart = false
      return TEMPOS[0]
    }
    const total = TEMPOS.reduce((s, t) => s + t.weight, 0)
    let roll = random() * total
    for (const tempo of TEMPOS) {
      roll -= tempo.weight
      if (roll < 0) return tempo
    }
    return TEMPOS[1]
  }

  function newLeg(now) {
    const tempo = pickTempo()
    // Darting legs HOP, never teleport (owner: "one of them gets crazy and
    // jumps half the screen") — a quick leg picks a NEARBY destination;
    // only the slow legs may cross the field.
    const quick = tempo.max <= 1100
    const toX = quick ? x + (random() * 2 - 1) * 0.2 : 0.08 + random() * 0.84
    const toY = quick ? y + (random() * 2 - 1) * 0.2 : 0.08 + random() * 0.84
    leg = {
      fromX: x,
      fromY: y,
      toX: Math.min(0.92, Math.max(0.08, toX)),
      toY: Math.min(0.92, Math.max(0.08, toY)),
      start: now,
      duration: tempo.min + random() * (tempo.max - tempo.min),
    }
  }

  return {
    // A real pito moment (message landing, thinking resolving, shiny
    // unlocking) — the butterfly startles: full impulse, next leg darts.
    kick(strength = 1) {
      impulse = Math.max(impulse, Math.min(1, strength))
      forceDart = true
    },

    update(now, bias = null) {
      if (!leg) newLeg(now)
      let t = (now - leg.start) / leg.duration
      if (t >= 1) {
        x = leg.toX
        y = leg.toY
        newLeg(now)
        t = 0
      }
      const e = easeInOutCubic(Math.min(1, t))
      let nx = leg.fromX + (leg.toX - leg.fromX) * e
      let ny = leg.fromY + (leg.toY - leg.fromY) * e
      if (bias && bias.weight > 0) {
        nx = nx * (1 - bias.weight) + bias.x * bias.weight
        ny = ny * (1 - bias.weight) + bias.y * bias.weight
      }
      vx = nx - x
      vy = ny - y
      x = nx
      y = ny
      impulse = Math.max(0, impulse - 0.008)
      return { x, y, vx, vy, impulse }
    },

    state() {
      return { x, y, vx, vy, impulse, leg }
    },
  }
}
