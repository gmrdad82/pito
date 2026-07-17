import { Controller } from "@hotwired/stimulus"
import { drawSky } from "fx/sky"
import { createEngine } from "fx/engine"
import { createButterfly } from "fx/attractor"
import renderers from "fx/renderers"

// perp() rotates a vector 90° — the crosswise deflection behind every
// "tilted" flock personality below (owner 2026-07-13, flock mouse
// personalities).
function perp(x, y) {
  return { x: -y, y: x }
}

// The VIRTUAL bias TARGET a personality leans a flock member toward, given
// the member's own position m and the fresh pointer p. attractor.js is
// never touched — it still only ever sees "lean toward this point" via
// update(now, {x, y, weight}); it has no idea personalities exist. Offsets
// from each ingredient compose (owner: "pushed and tilted") and land back
// on m:
//   attracted  → target = m + (p - m)             = p itself
//   repelled   → target = m + (m - p)              the mirror of p across m
//                (leaning toward the mirror moves AWAY from p)
//   tilted     → target = m + perp(p - m)          deflects crosswise
//   combos     → sum the ingredient offsets, then add to m
function personalityBiasTarget(personality, m, p) {
  let ox = 0
  let oy = 0
  if (personality.includes("attracted")) {
    ox += p.x - m.x
    oy += p.y - m.y
  }
  if (personality.includes("repelled")) {
    ox += m.x - p.x
    oy += m.y - p.y
  }
  if (personality.includes("tilted")) {
    const t = perp(p.x - m.x, p.y - m.y)
    ox += t.x
    oy += t.y
  }
  return {
    x: Math.min(0.95, Math.max(0.05, m.x + ox)),
    y: Math.min(0.95, Math.max(0.05, m.y + oy)),
  }
}

// The living background's engine shell (2.1.0 P3 — T3.1): owns the ONE
// canvas, the 30fps fx clock, and the lifecycle listener (F5's third
// listener: visibility / resize / reduced-motion). Renders the resting sky
// pass; the context engine (P4) and enforcer passes (P5) plug into the
// same frame loop.
//
// Perf posture (F9/F13): fps + DPR come from the fx.yml registry (served
// as a data value — one config, both sides of the wire); document.hidden
// pauses the clock entirely; prefers-reduced-motion renders ONE static
// frame and stops. No media-query gating — mobile runs the full engine,
// the caps are the guard.
//
// Emits `pito:fx:fps` (detail.fps — achieved frames over the last window)
// every 500ms for the DEVELOPMENT ribbon's meter.
export default class extends Controller {
  static values = { config: Object }

  connect() {
    this._ctx = this.element.getContext("2d")
    if (!this._ctx) return

    const engine = this.configValue?.engine || {}
    this._interval = 1000 / (engine.fps || 30)
    this._dprCap = engine.dpr_cap || 1.0
    // Sky tunables ride fx.yml (owner tuning is a YAML edit, never code):
    // drift_scale slows/hastens the resting glide; tilt_gain multiplies the
    // hand-tilt sway.
    this._enforcerAlpha = engine.enforcer_alpha ?? 1.0
    const knobs = this.configValue?.effects?.sky?.knobs || {}
    this._driftScale = knobs.drift_scale ?? 1.0
    this._tiltGain = knobs.tilt_gain ?? 1.0

    this._phase = 0
    this._running = false
    this._raf = null
    this._last = null
    this._frames = 0
    this._fpsWindowStart = null

    this._reduced = window.matchMedia("(prefers-reduced-motion: reduce)")
    this._abort = new AbortController()
    const signal = this._abort.signal

    window.addEventListener("resize", () => this.#resize(), { signal, passive: true })
    // Phone-tilt parallax (owner): gyro sways the field, per-depth. gamma =
    // left/right roll, beta = front/back pitch; both low-pass smoothed and
    // clamped so a pocketed phone never sends the sky flying. No permission
    // needed on Android; iOS would require a user-gesture prompt — parked
    // until an iOS app exists. Reduced motion keeps the sky still anyway.
    this._tilt = { x: 0, y: 0 }
    window.addEventListener("deviceorientation", (e) => this.#onTilt(e), { signal, passive: true })
    // Desktop gets the same sway from the MOUSE (owner refinement of F7:
    // the resting sky may tilt with the pointer — a depth response, not a
    // follower; enforcers still get the butterfly, never the cursor).
    // Viewport center = neutral; edges = full tilt; same low-pass.
    // FRAME-BOUNDED (owner perf report: fps sank to 10-15 while the mouse
    // moved): the listener only RECORDS the newest coords — normalization
    // and the low-pass run once per rAF tick in #stepPointerTilt, so a
    // pointermove burst (high-Hz mice, uncoalesced browsers) costs two
    // field writes per event, never math.
    this._pointerLast = { x: 0, y: 0, dirty: false }
    window.addEventListener("pointermove", (e) => this.#onPointerTilt(e), { signal, passive: true })
    document.addEventListener("visibilitychange", () => this.#onVisibility(), { signal })
    this._reduced.addEventListener?.("change", () => this.#onReducedMotion(), { signal })

    // The context engine (P4): dominance in, crossfade mix out. Renderers
    // register in fx/renderers/index — until then every pick degrades to
    // the sky (engine-tested behavior, visually inert by design).
    this._engine = createEngine({
      config: this.configValue,
      capabilities: this.#probeCapabilities(),
      renderers,
    })
    this.#watchDominance(signal)

    // The BUTTERFLY FLOCK (P6 + owner 2026-07-13 "make more of them move
    // chaotically"): engine.butterflies bodies of eased, uneven tempo. The
    // FIRST is the leader every effect follows and the mouse leans (F7);
    // companions are pure chaos, each also GENTLY reacting to the mouse in
    // its own way (owner 2026-07-13: "maybe one gets attracted, maybe one
    // gets tilted, maybe one gets pushed, maybe one gets pushed and
    // tilted" — see FLOCK_PERSONALITIES below and #wander for the lean
    // itself). A soft separation pass keeps them from touching. Real pito
    // events startle the whole flock. Bodies render on the SKY only — over
    // an enforcer mood they read as a second effect (owner: lens/duotone/
    // water rounds), so they fade with skyAlpha. Flock size re-rolls 3 up
    // to engine.butterflies on EVERY new fx pick (owner: "3-6 random per
    // setup and not fixed — when a new fx is picked, pick a random flock
    // between 3 and 6"); see #rerollFlock.
    this._flockMax = Math.max(3, engine.butterflies ?? 6)
    const flockSize = 3 + Math.floor(Math.random() * (this._flockMax - 2))
    // The rings are an IDLE ornament (owner): conversation activity —
    // messages landing, scrolling, typing, tapping — fades them out;
    // stillness past ring_idle_ms fades them back in over the sky.
    this._ringIdleMs = engine.ring_idle_ms ?? 8000
    this._ringAlpha = 0
    this._lastActivityAt = performance.now()
    const markActivity = () => { this._lastActivityAt = performance.now() }
    for (const type of ["scroll", "wheel", "touchmove", "keydown", "pointerdown"]) {
      window.addEventListener(type, markActivity, { signal, passive: true, capture: true })
    }
    // Personality table (owner 2026-07-13): assigned once per member here,
    // cycling by index. Index 0 lands on "attracted" first — exactly the
    // leader's established F7 lean, so nothing changes for it. The other
    // four give companions their own gentle relationship to the mouse;
    // personalityBiasTarget() (top of file) turns each name into a virtual
    // lean target every frame in #wander.
    this._personalities = ["attracted", "repelled", "tilted", "repelled+tilted", "attracted+tilted"]
    this._flock = Array.from({ length: flockSize }, (_, i) => this.#newFlockMember(i))
    this._flockSetupKey = null
    // The ring extras roll at BOOT too (owner bug report: a page that loads
    // straight onto the idle sky never saw its 6-10 bodies — the roll only
    // happened on the first mood change).
    this.#rollRingExtras()
    this._attractor = { x: 0.5, y: 0.5, vx: 0, vy: 0, impulse: 0, flock: [] }
    window.addEventListener("pito:fx:impulse", () => {
      markActivity()
      for (const member of this._flock) member.fly.kick(1)
    }, { signal })

    // Live enforcer instances, keyed name:eventId — at most the active one
    // and the one fading out (F9's context budget).
    this._instances = new Map()

    this.#resize()
    this.#start()
    // Debug handle: the engine's state is inspectable from the console /
    // capture probes (read-only introspection, no API surface).
    this.element.__fx = this
  }

  // Ring color PAIRS (owner 2026-07-13: "several variants of color, not
  // just purple and blue... random assignments and no restrictions").
  // Each body draws its glow, trail, and rotating rim from ITS pair.
  static RING_PAIRS = [
    [[187, 154, 247], [81, 112, 255]],   // purple / pito-blue
    [[81, 112, 255], [125, 207, 255]],   // blue / cyan
    [[255, 110, 199], [187, 154, 247]],  // pink / purple
    [[125, 207, 255], [158, 206, 106]],  // cyan / green
    [[255, 158, 100], [255, 110, 199]],  // orange / pink
    [[224, 175, 104], [255, 158, 100]],  // gold / orange
    [[247, 118, 142], [255, 110, 199]],  // red / pink
    [[158, 206, 106], [125, 207, 255]],  // green / cyan
  ]

  #newFlockMember(i) {
    const pairs = this.constructor.RING_PAIRS
    return {
      fly: createButterfly(),
      // RANDOM per spawn (owner: "each butterfly reacts in a random way") —
      // except the leader, which stays "attracted": every effect anchors to
      // it and its locked feel must not re-roll.
      personality: i === 0
        ? "attracted"
        : this._personalities[Math.floor(Math.random() * this._personalities.length)],
      // Fully random per spawn — repeats allowed, even a whole sky of one
      // pair is a legal roll (owner: "no restrictions").
      pair: pairs[Math.floor(Math.random() * pairs.length)],

      state: { x: 0.5, y: 0.5, vx: 0, vy: 0, impulse: 0 },
      // The ring follower trails the smoothed state EXTRA slowly (owner:
      // the rings must never jump sporadically) — see #drawButterfly.
      ring: { x: 0.5, y: 0.5 },
      trail: [],
      lastTrailAt: 0,
    }
  }

  // Every NEW pick re-rolls the flock size (owner: 3-6 per setup, never
  // fixed). Members grow from the center and glide out; shrinking trims
  // from the tail so the leader — and every effect following it — never
  // blinks. The SKY RINGS roll their own richer count (owner: 6-10 ring
  // bodies per spawn) — the extras beyond the flock are ring-ONLY
  // wanderers, never fed to the effects.
  #rerollFlock() {
    const size = 3 + Math.floor(Math.random() * (this._flockMax - 2))
    while (this._flock.length > size) this._flock.pop()
    while (this._flock.length < size) this._flock.push(this.#newFlockMember(this._flock.length))
    this.#rollRingExtras()
  }

  // The sky's ring population beyond the flock: 6-10 bodies total per
  // spawn (owner), rolled at boot and at every new pick.
  #rollRingExtras() {
    const ringTotal = 6 + Math.floor(Math.random() * 5) // 6..10
    const extras = Math.max(0, ringTotal - this._flock.length)
    this._ringExtras = this._ringExtras || []
    while (this._ringExtras.length > extras) this._ringExtras.pop()
    while (this._ringExtras.length < extras) {
      this._ringExtras.push(this.#newFlockMember(this._flock.length + this._ringExtras.length))
    }
  }

  disconnect() {
    this._abort?.abort()
    this._io?.disconnect()
    this._mo?.disconnect()
    for (const instance of this._instances?.values() || []) instance.destroy?.()
    this._instances?.clear()
    this._wallLayer?.remove()
    this.#stop()
  }

  // ── Clock ──────────────────────────────────────────────────────────────

  #start() {
    if (this._running) return
    if (this._reduced.matches) return this.#renderStaticFrame()
    this._running = true
    this._last = null
    this._fpsWindowStart = null
    const tick = (now) => {
      if (!this._running) return
      this._raf = requestAnimationFrame(tick)
      // Pointer-tilt integrates HERE, before the fps gate: one low-pass
      // step per display frame — the same cadence coalesced pointermove
      // events arrived at, so the sway keeps its original ease.
      this.#stepPointerTilt(now)
      if (this._last === null) this._last = now
      const elapsed = now - this._last
      if (elapsed < this._interval) return
      this._last = now - (elapsed % this._interval)
      // The TUI advanced 0.047/16ms; scale to the achieved step so the
      // drift speed survives any fps cap.
      this._phase += 0.047 * (elapsed / 16) * this._driftScale
      this.#renderFrame()
      this.#countFrame(now)
    }
    this._raf = requestAnimationFrame(tick)
  }

  #stop() {
    this._running = false
    if (this._raf) cancelAnimationFrame(this._raf)
    this._raf = null
  }

  #onVisibility() {
    document.hidden ? this.#stop() : this.#start()
  }

  #onReducedMotion() {
    this.#stop()
    this._reduced.matches ? this.#renderStaticFrame() : this.#start()
  }

  // ── Frames ─────────────────────────────────────────────────────────────

  #resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, this._dprCap)
    this._w = window.innerWidth
    this._h = window.innerHeight
    this.element.width = Math.round(this._w * dpr)
    this.element.height = Math.round(this._h * dpr)
    this._ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    if (!this._running) this.#renderStaticFrame()
  }

  // Record-only (perf): no math, no allocation — #stepPointerTilt does the
  // real work once per frame.
  #onPointerTilt(e) {
    if (e.pointerType && e.pointerType !== "mouse") return
    const p = this._pointerLast
    p.x = e.clientX
    p.y = e.clientY
    p.dirty = true
  }

  // One low-pass step per animation frame, and ONLY when the mouse moved
  // since the last step — when the hand rests, events stop, the tilt
  // freezes mid-ease exactly as the per-event version did.
  #stepPointerTilt(now) {
    const p = this._pointerLast
    if (!p?.dirty) return
    p.dirty = false
    const targetX = Math.max(-1, Math.min(1, (p.x / this._w) * 2 - 1))
    const targetY = Math.max(-1, Math.min(1, (p.y / this._h) * 2 - 1))
    this._tilt.x += (targetX - this._tilt.x) * 0.12
    this._tilt.y += (targetY - this._tilt.y) * 0.12
    // The mouse also BIASES the butterfly (owner): the wanderer leans a
    // third of the way toward a fresh pointer, then reclaims the field
    // when the hand rests (freshness window in #wander).
    this._pointer = { x: p.x / this._w, y: p.y / this._h, at: now }
  }

  #onTilt(e) {
    if (e.gamma == null || e.beta == null) return
    // ±30° of comfortable hand-tilt maps to ±1 unit; layers scale by speed
    // (the far layer sways ~3px, the near ~8px). Low-pass (0.12) smooths
    // sensor jitter into drift.
    const targetX = Math.max(-1, Math.min(1, e.gamma / 30))
    const targetY = Math.max(-1, Math.min(1, (e.beta - 45) / 30))
    this._tilt.x += (targetX - this._tilt.x) * 0.12
    this._tilt.y += (targetY - this._tilt.y) * 0.12
  }

  #renderFrame() {
    const now = performance.now()
    const mix = this._engine.tick(now)
    // A NEW pick (a different mood taking over, or the sky reclaiming the
    // frame) re-rolls the flock size 3..max (owner: "3-6 random per setup").
    const st = this._engine.state()
    const target = st.transition ? st.transition.to : st.active
    const setupKey = target ? `${target.name}:${target.eventId}` : "sky"
    if (this._flockSetupKey !== null && setupKey !== this._flockSetupKey) this.#rerollFlock()
    this._flockSetupKey = setupKey
    this.#wander(now)
    this._ctx.clearRect(0, 0, this._w, this._h)
    // F4: the sky pass skips entirely when an enforcer owns the frame.
    if (mix.skyAlpha > 0) {
      // The sky sways with the LEADER butterfly (owner 2026-07-13: no mood
      // touches the device directly — the hand reaches everything through
      // the flock). tilt_gain now scales the leader's off-center drift.
      const lead = this._flock[0].state
      drawSky(this._ctx, this._w, this._h, this._phase, mix.skyAlpha, {
        x: (lead.x - 0.5) * 2 * this._tiltGain,
        y: (lead.y - 0.5) * 2 * this._tiltGain,
      })
    }
    // Compositor: each live pass renders offscreen and lands here at its
    // crossfade alpha (F4 — one visible canvas, passes composited).
    if (mix.fading) this.#compositePass(mix.fading, now)
    if (mix.enforcer) this.#compositePass(mix.enforcer, now)
    // Idle gate: target 1 after ring_idle_ms of stillness, 0 on activity;
    // ease toward it (~1s at 30fps) so the flock breathes in and out.
    const idle = now - this._lastActivityAt > this._ringIdleMs
    this._ringAlpha += ((idle ? 1 : 0) - this._ringAlpha) * 0.05
    this.#drawButterfly(mix.skyAlpha * this._ringAlpha)
    this.#reapInstances(mix, now)
  }

  #compositePass(pass, now) {
    const instance = this.#instanceFor(pass)
    if (!instance) return
    // DOM renderers mount BEFORE readiness — the browser needs the element
    // alive to fetch and paint its images (opacity holds at 0 meanwhile).
    if (instance.element && !instance.element.isConnected) {
      this.#wallLayer().appendChild(instance.element)
    }
    if (!instance.ready()) return
    instance.frame(this._interval, this._phase, this._attractor)
    if (instance.element) {
      instance.element.style.opacity = (pass.alpha * this._enforcerAlpha).toFixed(3)
    } else {
      this._ctx.globalAlpha = pass.alpha * this._enforcerAlpha
      this._ctx.drawImage(instance.canvas, 0, 0, this._w, this._h)
      this._ctx.globalAlpha = 1
    }
    instance._lastUsed = now
  }

  // The DOM home for css-engine enforcers: right above the canvas, below
  // all content (same stacking slot), inert to input.
  #wallLayer() {
    if (!this._wallLayer) {
      this._wallLayer = document.createElement("div")
      this._wallLayer.className = "pito-fx-wall-layer"
      this.element.insertAdjacentElement("afterend", this._wallLayer)
    }
    return this._wallLayer
  }

  // Instance identity is the mood's OWNING event: the engine's neighbour
  // cache keeps the same active mood object (original eventId) across
  // same-cover neighbours, so "analyze vid 2" reuses the very ripple field
  // "show vid 2" grew — while a NON-neighbour repeat of that cover rolls a
  // fresh event id and thus a fresh instance, never resurrecting the old
  // field even before the reaper collects it (owner: neighbour-only).
  #passKey(pass) {
    return `${pass.name}:${pass.eventId}`
  }

  #instanceFor(pass) {
    const key = this.#passKey(pass)
    if (this._instances.has(key)) return this._instances.get(key)
    const factory = renderers[pass.name]
    if (!factory) return null
    const knobs = this.configValue?.effects?.[pass.name]?.knobs || {}
    const instance = factory.create({
      width: this._w,
      height: this._h,
      dpr: Math.min(window.devicePixelRatio || 1, this._dprCap),
      knobs,
      covers: pass.covers || [],
    })
    if (instance) {
      instance._lastUsed = performance.now()
      this._instances.set(key, instance)
    }
    return instance
  }

  // Destroy instances no mix referenced for 5s (scrolled far away) — the
  // lazy lifecycle that keeps live GL contexts to the active pair.
  #reapInstances(mix, now) {
    const live = new Set(
      [mix.enforcer, mix.fading].filter(Boolean).map((p) => this.#passKey(p))
    )
    for (const [key, instance] of this._instances) {
      if (live.has(key)) continue
      // A DOM-backed pass (the wall) keeps whatever opacity its LAST
      // composited frame wrote — and once it leaves the mix, no pass ever
      // writes it again. A mid-crossfade frame hitch (multiple ls-games
      // walls loading images) strands it at a visible alpha, ghosting
      // under the incoming mood until the 5s reap. Kill the paint NOW;
      // keep the instance warm for the quick-flip reuse window.
      if (instance.element) instance.element.style.opacity = "0"
      if (now - (instance._lastUsed || 0) > 5000) {
        instance.destroy?.()
        this._instances.delete(key)
      }
    }
  }

  // The flock's flight + each body's trail buffer. Three layers keep the
  // motion calm and collision-free (owner: circles collided, moved too fast,
  // and shoves read as half-screen jumps):
  //   1. per-body SAFETY RADII, generous for the first three (they anchor
  //      the big lens/duotone circles), relaxed over two passes;
  //   2. the relaxed positions are TARGETS, not teleports — every consumer
  //      reads a low-pass smoothed follower that glides toward them;
  //   3. quick dart legs hop nearby (attractor.js), never across the field.
  #wander(now) {
    const SEP = [0.17, 0.17, 0.16, 0.11, 0.1, 0.09]
    // Bias weight per member: gentle throughout — the leader keeps its
    // established 0.33 (F7, unchanged); companions stagger across
    // 0.15–0.22 so no two lean at the same rate (owner 2026-07-13).
    const BIAS_WEIGHT = [0.33, 0.15, 0.22, 0.18, 0.2, 0.17]
    const pointerFresh = this._pointer && now - this._pointer.at < 2000
    // Phones have no pointer — the GYRO is the hand there (owner: "every
    // butterfly reacts to mouse AND gyro"): a meaningful tilt synthesizes
    // the lean point the personalities react to, same math as the mouse.
    const tiltActive = !pointerFresh && (Math.abs(this._tilt.x) > 0.08 || Math.abs(this._tilt.y) > 0.08)
    const hand = pointerFresh
      ? this._pointer
      : tiltActive
        ? {
            x: Math.min(0.95, Math.max(0.05, 0.5 + this._tilt.x * 0.4)),
            y: Math.min(0.95, Math.max(0.05, 0.5 + this._tilt.y * 0.4)),
          }
        : null
    const raw = this._flock.map((member, i) => {
      const bias = hand
        ? {
            ...personalityBiasTarget(member.personality, member.state, hand),
            weight: BIAS_WEIGHT[i] ?? 0.15 + (i % 4) * 0.02,
          }
        : null
      const s = member.fly.update(now, bias)
      member.impulse = s.impulse
      return { x: s.x, y: s.y }
    })
    for (let pass = 0; pass < 2; pass++) {
      for (let i = 0; i < raw.length; i++) {
        for (let j = i + 1; j < raw.length; j++) {
          const minSep = (SEP[i] ?? 0.09) + (SEP[j] ?? 0.09)
          const dx = raw[j].x - raw[i].x
          const dy = raw[j].y - raw[i].y
          const dist = Math.hypot(dx, dy) || 0.0001
          if (dist < minSep) {
            const push = (minSep - dist) / 2
            const ux = dx / dist
            const uy = dy / dist
            raw[i].x = Math.min(0.95, Math.max(0.05, raw[i].x - ux * push))
            raw[i].y = Math.min(0.95, Math.max(0.05, raw[i].y - uy * push))
            raw[j].x = Math.min(0.95, Math.max(0.05, raw[j].x + ux * push))
            raw[j].y = Math.min(0.95, Math.max(0.05, raw[j].y + uy * push))
          }
        }
      }
    }
    this._flock.forEach((member, i) => {
      const prev = member.state
      const nx = prev.x + (raw[i].x - prev.x) * 0.06
      const ny = prev.y + (raw[i].y - prev.y) * 0.06
      member.state = { x: nx, y: ny, vx: nx - prev.x, vy: ny - prev.y, impulse: member.impulse }
      // The ring body lags even further behind (owner: rings glide, never
      // jump) — a second, heavier low-pass over the already-smoothed state.
      member.ring.x += (nx - member.ring.x) * 0.035
      member.ring.y += (ny - member.ring.y) * 0.035
      // Denser sampling + longer stack (owner: smaller gaps between the
      // trail rings).
      if (!member.lastTrailAt || now - member.lastTrailAt > 45) {
        member.trail.push({ x: nx, y: ny })
        if (member.trail.length > 14) member.trail.shift()
        member.lastTrailAt = now
      }
    })
    // The ring-only extras fly plain (no mouse personality, no separation —
    // rings may overlap, pitomd's cascades do) and keep their own smoothed
    // followers + trails exactly like flock members.
    for (const member of this._ringExtras || []) {
      const st = member.fly.update(now)
      const prev = member.state
      const nx = prev.x + (st.x - prev.x) * 0.06
      const ny = prev.y + (st.y - prev.y) * 0.06
      member.state = { x: nx, y: ny, vx: nx - prev.x, vy: ny - prev.y, impulse: st.impulse }
      member.ring.x += (nx - member.ring.x) * 0.035
      member.ring.y += (ny - member.ring.y) * 0.035
      if (!member.lastTrailAt || now - member.lastTrailAt > 45) {
        member.trail.push({ x: nx, y: ny })
        if (member.trail.length > 14) member.trail.shift()
        member.lastTrailAt = now
      }
    }

    // Effects follow the LEADER; multi-focus renderers (lens, duotone)
    // read the whole flock off the same object.
    this._attractor = {
      ...this._flock[0].state,
      flock: this._flock.map((m) => m.state),
    }
  }

  // The sky's RING BODIES — pitomd's luminous cascades, definitively this
  // time (a stale duplicate of this method shadowed the first port; owner
  // saw thin purple/blue hoops twice). Flock members PLUS the ring-only
  // extras (6-10 total per spawn), each wearing ITS OWN color pair
  // (RING_PAIRS, random per spawn, repeats legal): soft radial glow fills
  // cascading behind the extra-slow ring follower, a rim whose pair-colored
  // conic gradient ROTATES, all additive so overlaps bloom. SKY ONLY,
  // idle-gated — the bodies fade with skyAlpha.
  #drawButterfly(skyAlpha = 1) {
    if (skyAlpha <= 0.01) return
    const ctx = this._ctx
    const DEFAULT_PAIR = [[187, 154, 247], [81, 112, 255]]
    const bodies = (this._ringExtras && this._ringExtras.length)
      ? this._flock.concat(this._ringExtras)
      : this._flock
    ctx.save()
    ctx.globalCompositeOperation = "lighter"
    bodies.forEach((member, idx) => {
      const [C1, C2] = member.pair || DEFAULT_PAIR
      // LOCKED (owner): heads LEAD — the disk sits on the live position,
      // every trail sample is a past state, the cascade streams behind.
      const px = member.state.x * this._w
      const py = member.state.y * this._h
      // Staggered sizes, never a matching neighbour (owner).
      const RING_TIERS = [1, 0.88, 0.76, 0.66, 0.57, 0.5, 0.94, 0.82, 0.7, 0.61]
      const scale = RING_TIERS[idx % RING_TIERS.length]
      // Halved (owner: the cascades — "I like a lot more" — were 2x too
      // big); everything hangs off r, so one coefficient halves it all.
      const r = (13 + member.state.impulse * 5) * scale
      // The trailing cascade: big soft glow fills, ~double size with tight
      // gaps (owner) — the far tail wears the biggest, faintest circle.
      for (let i = 0; i < member.trail.length; i++) {
        const p = member.trail[i]
        const age = (i + 1) / member.trail.length // old → young
        const tr = r * (0.7 + age * 1.3)
        const tx = p.x * this._w
        const ty = p.y * this._h
        const mix = age
        const cr = Math.round(C1[0] + (C2[0] - C1[0]) * mix)
        const cg = Math.round(C1[1] + (C2[1] - C1[1]) * mix)
        const cb = Math.round(C1[2] + (C2[2] - C1[2]) * mix)
        const fill = ctx.createRadialGradient(tx, ty, 0, tx, ty, tr)
        fill.addColorStop(0, `rgb(${cr} ${cg} ${cb} / ${(0.015 * age * skyAlpha).toFixed(4)})`)
        fill.addColorStop(0.72, `rgb(${cr} ${cg} ${cb} / ${(0.05 * age * skyAlpha).toFixed(4)})`)
        fill.addColorStop(1, "rgb(0 0 0 / 0)")
        ctx.beginPath()
        ctx.arc(tx, ty, tr, 0, Math.PI * 2)
        ctx.fillStyle = fill
        ctx.fill()
      }
      // The body: soft pair-colored inner glow + the ROTATING conic rim —
      // each pair's two colors chase each other around the circle.
      const glow = ctx.createRadialGradient(px, py, r * 0.3, px, py, r * 1.35)
      glow.addColorStop(0, `rgb(${C1[0]} ${C1[1]} ${C1[2]} / ${(0.05 * skyAlpha).toFixed(3)})`)
      glow.addColorStop(0.8, `rgb(${C2[0]} ${C2[1]} ${C2[2]} / ${(0.1 * skyAlpha).toFixed(3)})`)
      glow.addColorStop(1, "rgb(0 0 0 / 0)")
      ctx.beginPath()
      ctx.arc(px, py, r * 1.35, 0, Math.PI * 2)
      ctx.fillStyle = glow
      ctx.fill()
      // The head is a REALLY SMALL solid disk at the comet's own center
      // (owner revision: not gone — shrunk from the prominent stroked ring
      // to a dot the cascade streams from).
      const diskR = Math.max(2, r * 0.3)
      const disk = ctx.createRadialGradient(px, py, 0, px, py, diskR)
      disk.addColorStop(0, `rgb(${C1[0]} ${C1[1]} ${C1[2]} / ${(0.85 * skyAlpha).toFixed(3)})`)
      disk.addColorStop(1, `rgb(${C2[0]} ${C2[1]} ${C2[2]} / ${(0.25 * skyAlpha).toFixed(3)})`)
      ctx.beginPath()
      ctx.arc(px, py, diskR, 0, Math.PI * 2)
      ctx.fillStyle = disk
      ctx.fill()
    })
    ctx.restore()
  }

  // Reduced motion: one honest, still sky — breathing frozen mid-breath.
  #renderStaticFrame() {
    this.#renderFrame()
  }

  // ── Listeners one and two (F5): viewport dominance + cable activity ──

  // WebGL2 + float-buffer capability probe, once per page.
  #probeCapabilities() {
    try {
      const probe = document.createElement("canvas").getContext("webgl2")
      if (!probe) return { webgl: false, float: false }
      const float = !!probe.getExtension("EXT_color_buffer_float")
      probe.getExtension("WEBGL_lose_context")?.loseContext()
      return { webgl: true, float }
    } catch {
      return { webgl: false, float: false }
    }
  }

  // Dominance: the eligible message covering the most viewport height (and
  // at least 35% of it) declares the mood; anything less is a sky moment.
  // IntersectionObserver feeds a live map; a MutationObserver re-enrolls
  // appended/replaced messages (listener two — it also doubles as the
  // butterfly's impulse source via pito:fx:impulse).
  #watchDominance(signal) {
    this._visible = new Map()
    const scrollback = document.getElementById("pito-scrollback")
    if (!scrollback) return

    this._io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) this._visible.set(entry.target, entry.intersectionRect.height)
          else this._visible.delete(entry.target)
        }
        this.#declareDominant()
      },
      { threshold: [0, 0.25, 0.5, 0.75, 1] }
    )
    const enroll = () => {
      for (const el of scrollback.querySelectorAll("[data-fx-context]")) this._io.observe(el)
    }
    enroll()

    this._mo = new MutationObserver(() => {
      enroll()
      window.dispatchEvent(new CustomEvent("pito:fx:impulse", { detail: { kind: "stream" } }))
    })
    this._mo.observe(scrollback, { childList: true, subtree: true })
    scrollback.addEventListener("scroll", () => this.#declareDominant(), { signal, passive: true })
  }

  #declareDominant() {
    let best = null
    let bestHeight = 0
    for (const [el, height] of this._visible) {
      if (height > bestHeight) {
        best = el
        bestHeight = height
      }
    }
    const now = performance.now()
    if (!best || bestHeight < window.innerHeight * 0.35) {
      this._engine.observeDominant(null, now)
      return
    }
    let covers = []
    try {
      covers = JSON.parse(best.dataset.fxCovers || "[]")
    } catch {
      covers = []
    }
    this._engine.observeDominant(
      {
        context: best.dataset.fxContext,
        eventId: best.id || best.dataset.fxContext,
        covers,
      },
      now
    )
  }

  #countFrame(now) {
    if (this._fpsWindowStart === null) {
      this._fpsWindowStart = now
      this._frames = 0
    }
    this._frames++
    if (now - this._fpsWindowStart >= 500) {
      const fps = Math.round((this._frames * 1000) / (now - this._fpsWindowStart))
      window.dispatchEvent(new CustomEvent("pito:fx:fps", { detail: { fps } }))
      this._fpsWindowStart = now
      this._frames = 0
    }
  }
}
