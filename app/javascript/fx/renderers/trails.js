// TRAILS — the ring-cascade mood (owner 2026-07-13, from the pitomd
// screenshot that settled it: "trails in pitomd looks way cooler — I want
// pito to have the same effects"). NOT the fluid dye we tried first: each
// flock member drags a cascading stack of big, soft, luminous circles —
// small bright head, swelling translucent tail — purple→blue→pink, drawn
// additively so overlaps bloom. Kin to the idle ring bodies, scaled up
// into a full cover-less mood for lists, analyze, and channel moments.
//
// Contract-compliant (see index.js): own offscreen canvas, no listeners,
// no pointer reads — attractor.flock drives everything (F7/P6). The
// cascade is a SPRING CHAIN, not a sampled buffer (owner: the sampled
// version read laggy at the 30fps fx clock — circles teleported between
// 80ms samples): the head eases toward the member every frame, and each
// circle eases toward the one ahead of it, so the whole cascade flows
// continuously at any frame rate. The ease is dt-normalized — the feel
// survives fps dips.

const FOLLOW = 0.35 // per-33ms ease rate along the chain (knob: follow)
const HUES = [
  [187, 154, 247], // purple
  [81, 112, 255], // pito-blue
  [255, 110, 199], // pink
]

function hueFor(i, t) {
  const a = HUES[i % HUES.length]
  const b = HUES[(i + 1) % HUES.length]
  return [
    Math.round(a[0] + (b[0] - a[0]) * t),
    Math.round(a[1] + (b[1] - a[1]) * t),
    Math.round(a[2] + (b[2] - a[2]) * t),
  ]
}

export default {
  create({ width = 0, height = 0, dpr = 1, knobs = {} } = {}) {
    const canvas = document.createElement("canvas")
    const ctx = canvas.getContext("2d")
    if (!ctx) return null

    const scale = knobs.scale ?? 1.0
    const stack = Math.max(4, Math.round(knobs.stack ?? 14))
    const alpha = knobs.alpha ?? 0.5
    const follow = knobs.follow ?? FOLLOW

    let w = Math.max(1, width)
    let h = Math.max(1, height)
    const ratio = Math.max(0.5, dpr || 1)
    canvas.width = Math.round(w * ratio)
    canvas.height = Math.round(h * ratio)
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0)

    // One spring chain per flock slot: chain[0] is the HEAD (chases the
    // member), chain[k] chases chain[k-1].
    const chains = new Map() // index → [{x, y}]

    return {
      canvas,

      frame(dtMs, _phase, attractor) {
        const flock = attractor && attractor.flock && attractor.flock.length
          ? attractor.flock
          : [attractor || { x: 0.5, y: 0.5 }]

        // dt-normalized ease: the chain flows identically at 30 or 60fps.
        const k = 1 - Math.pow(1 - follow, (dtMs || 33) / 33.3)

        ctx.clearRect(0, 0, w, h)
        ctx.save()
        ctx.globalCompositeOperation = "lighter"

        const vmin = Math.min(w, h)
        flock.forEach((member, i) => {
          let chain = chains.get(i)
          if (!chain) {
            chain = Array.from({ length: stack }, () => ({ x: member.x, y: member.y }))
            chains.set(i, chain)
          }
          chain[0].x += (member.x - chain[0].x) * k
          chain[0].y += (member.y - chain[0].y) * k
          for (let n = 1; n < chain.length; n++) {
            chain[n].x += (chain[n - 1].x - chain[n].x) * k
            chain[n].y += (chain[n - 1].y - chain[n].y) * k
          }

          // Per-member size tier — no two cascades match (owner law).
          const tier = [1, 0.8, 0.9, 0.7, 0.85, 0.75][i % 6]
          // The cascade: the FAR END of the chain wears the biggest,
          // faintest circle; the head is small and bright — pitomd's read.
          const trail = chain
          for (let s = trail.length - 1; s >= 0; s--) {
            const p = trail[s]
            const age = trail.length === 1 ? 1 : 1 - s / (trail.length - 1) // 0 far tail → 1 head
            const r = vmin * scale * tier * (0.028 + (1 - age) * 0.105)
            const px = p.x * w
            const py = p.y * h
            const [cr, cg, cb] = hueFor(i, 1 - age)
            const bodyA = alpha * (0.10 + age * 0.16)
            const fill = ctx.createRadialGradient(px, py, r * 0.15, px, py, r)
            fill.addColorStop(0, `rgb(${cr} ${cg} ${cb} / ${(bodyA * 0.55).toFixed(3)})`)
            fill.addColorStop(0.82, `rgb(${cr} ${cg} ${cb} / ${(bodyA * 0.3).toFixed(3)})`)
            fill.addColorStop(1, "rgb(0 0 0 / 0)")
            ctx.beginPath()
            ctx.arc(px, py, r, 0, Math.PI * 2)
            ctx.fillStyle = fill
            ctx.fill()
            // The rim — brighter than the body, the "soap bubble" edge.
            ctx.beginPath()
            ctx.arc(px, py, r * 0.92, 0, Math.PI * 2)
            ctx.strokeStyle = `rgb(${cr} ${cg} ${cb} / ${(bodyA * 1.5).toFixed(3)})`
            ctx.lineWidth = Math.max(1, r * 0.05)
            ctx.stroke()
          }
        })
        // Reap chains for members that left a shrunken flock.
        for (const key of chains.keys()) {
          if (key >= flock.length) chains.delete(key)
        }
        ctx.restore()
      },

      resize(nw, nh) {
        w = Math.max(1, nw)
        h = Math.max(1, nh)
        canvas.width = Math.round(w * ratio)
        canvas.height = Math.round(h * ratio)
        ctx.setTransform(ratio, 0, 0, ratio, 0, 0)
      },

      ready() {
        return true
      },

      destroy() {},
    }
  },
}
