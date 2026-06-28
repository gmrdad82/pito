// pito/reveal_engine.js
//
// The reveal ENGINE — the decomposition + per-effect runner spine shared by the
// live `pito--typewriter` controller (one-shot reveal of a freshly-arrived
// segment) and the `pito--fx-demo` controller (a looping showcase of one effect).
//
// A `RevealEngine` owns the units of one element subtree and knows how to PRIME
// the initial frame and RUN any of the three effects to completion. It carries
// no settings, no Stimulus, no reveal-queue and no doneEvent — those concerns
// stay in the controllers. The engine is pure mechanism: collect → prime → run,
// plus cancel/restore.
//
// Three reveal EFFECTS share one decomposition + scheduling spine; each branches
// only in HOW a unit is revealed:
//
//   • typewriter — char-by-char, total duration LOG-scaled to content length
//     (short snaps to a fast floor; long is capped). The default.
//   • scramble   — text starts FULLY VISIBLE but every char is a wrong glyph;
//     positions resolve left-to-right to the correct text (a decrypt cascade).
//   • comet      — the whole message starts HIDDEN (every host dimmed to ~0.01)
//     then a bright blurred "comet" sweeps across, REVEALING the text behind it:
//     a CSS mask edge rides in lock-step with the comet so each glyph appears
//     only as/after the comet passes over it (see .pito-comet-reveal). The sweep
//     is STAGGERED PER HOST: each text/atomic host starts its own short sweep a
//     bit later than the previous one (a cascade/crescendo), and the LAST host
//     still FINISHES within the engine's log-capped total budget — so a long
//     message's comet completes by the cap and never produces a long wait.
//
// Reveal model — one DOM-ordered stream of "units":
//   Every animatable target is decomposed into a flat list of reveal UNITS,
//   merged across all targets in document order, then revealed top-to-bottom.
//   A unit is one of:
//     • text   — a non-whitespace TEXT NODE (setting its value never re-parses
//                HTML, so an html card's structure is never rebuilt).
//     • atomic — an element with NO visible text (cover art, logos, icons, bar
//                fills) revealed whole at its DOM position.
//
//   ALWAYS-POP set: elements whose class matches the allowlist below (score /
//   time-to-beat bars, avatars, every cover variant, video thumbnails) are
//   excluded from the unit stream entirely, so they render whole and immediately
//   under EVERY effect — no typing, no scramble, no sweep.

// ── reveal-timing tunables (FLAG for smoke-test feel) ────────────────────────
// All three effects share ONE log-scaled duration formula so the "feel" of the
// reveal is consistent regardless of the chosen effect. A short message hits the
// fast floor; a long card is capped.
export const REVEAL_MIN_MS   = 400    // floor: shortest reveal (a tiny message) ≈ 0.4s
export const REVEAL_MAX_MS   = 2500   // cap:   longest reveal (a huge card)     ≈ 2.5s
const REVEAL_BASE     = 8      // chars at/below which the reveal sits on the floor
const REVEAL_LOG_GAIN = 320    // ms added per natural-log unit above the base
const FRAME_MS        = 14     // target frame interval; chars/tick derives from it

// Comet stagger model. The total budget = revealDuration(totalChars). The per-host
// START offsets are spread over COMET_STAGGER_SPAN of that budget; each host's own
// sweep is the remaining (1 - COMET_STAGGER_SPAN) of the budget. Thus the LAST
// host starts at `span` and finishes at `span + sweep == budget` — always within
// the log-capped total. For a SINGLE host the span collapses to 0 and the sweep
// is the whole budget (so a single message sweeps over its full log-scaled time).
const COMET_STAGGER_SPAN = 0.6   // fraction of the budget over which host starts spread

// Scramble tunable — the owner-facing knob.
// SCRAMBLE_SPEED_FACTOR: scramble total = engine log-scale × this factor. The WHOLE
//   unresolved tail stays live noise (that's the scramble look) and decrypts left→right;
//   this factor just makes the run faster. Keeps the ceiling invariant ("engine owns the
//   ceiling") since the result is always < REVEAL_MAX_MS. 0.5 ≈ 2× faster than the base
//   typewriter cadence; raise toward 1.0 to slow back down, lower for snappier.
export const SCRAMBLE_SPEED_FACTOR  = 0.5   // fraction of engine log-scale budget; < 1 = faster

// Typewriter first-glyph priming opacity. The typewriter prime prefills the first
// glyph so the box reserves layout instead of collapsing while it waits for its
// reveal slot — but a fully-opaque prefill "pops" visibly before the reveal even
// starts. Dimming it to ~invisible keeps the reserved space without the pop; the
// run snaps it back to full as the reveal begins. (~0.05 = effectively invisible.)
export const PRIME_OPACITY = 0.05

// Scramble glyph pool: the "wrong" characters shown before a position settles.
const SCRAMBLE_GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!<>-_\\/[]{}=+*#%&@"

// ── always-pop allowlist ─────────────────────────────────────────────────────
// Class-token patterns whose elements NEVER animate under any effect — matched
// against each class token so an element that ALSO carries text still pops.
const ALWAYS_POP_PATTERNS = [
  /^pito-score-bar/,
  /^pito-ttb/,
  /^pito-.*cover/,
  /^pito-.*thumbnail/,
  /^pito-.*avatar/,
  // Analytics metric widgets own THEIR reveal (e.g. the Views chart's "D"
  // bottom-up wipe via pito--views-reveal). The message reveal engine must NOT
  // typewrite/scramble the braille glyphs — skip the whole component so its own
  // controller drives the animation.
  /^pito-metric/
]

// Log-scaled reveal duration for `totalChars`, clamped to [REVEAL_MIN_MS,
// REVEAL_MAX_MS]. The single source of truth all three effects derive timing from.
export function revealDuration(totalChars) {
  if (totalChars <= REVEAL_BASE) return REVEAL_MIN_MS
  return Math.min(REVEAL_MAX_MS, REVEAL_MIN_MS + REVEAL_LOG_GAIN * Math.log(totalChars / REVEAL_BASE))
}

export class RevealEngine {
  // `targets` — the element(s) whose subtree(s) are decomposed and revealed.
  constructor(targets) {
    this.targets   = targets
    this.units     = []
    this.cancelled = false
    this._timers   = []        // every pending setTimeout handle (tw/scramble tick + comet stagger)
    this._cometEls = new Set() // hosts dimmed/swept under comet, for cleanup
    this._settled  = false
  }

  // Decompose every target into reveal units, merged in document order. Returns
  // the units (also stored on the engine).
  collect() {
    this.units = this.targets
      .flatMap(el => this.#collectUnits(el))
      .sort((a, b) => {
        const rel = a.ref.compareDocumentPosition(b.ref)
        return rel & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1
      })
    return this.units
  }

  // Total character count across text units — the input to the log-scaled budget.
  get totalChars() {
    return this.units.reduce((n, u) => n + (u.kind === "text" ? u.full.length : 0), 0)
  }

  // The engine-level log-scaled budget for the current units.
  get duration() {
    return revealDuration(this.totalChars)
  }

  // Prime the first visible frame for the chosen effect (synchronous — a box is
  // never an empty/flat shell before its run begins).
  prime(effect) {
    if (effect === "scramble") {
      for (const u of this.units) {
        if (u.kind === "text") u.node.nodeValue = this.#scrambleAll(u.full)
        else u.el.style.visibility = ""
      }
      return
    }

    if (effect === "comet") {
      // Content is full & correct from frame 0 but the WHOLE message starts
      // HIDDEN: dim EVERY host to ~0.01 and stamp its own sweep duration now, but
      // start NO sweep yet — nothing is visible before the comet reaches it. run()
      // then reveals each host at its staggered offset (the cascade), the bright
      // comet riding the leading edge while the text is unmasked behind it.
      this._cometSchedule = this.#buildCometSchedule()
      for (const u of this.units) {
        if (u.kind === "text") u.node.nodeValue = u.full
        else u.el.style.visibility = ""
      }
      for (const { host, sweepMs } of this._cometSchedule) this.#cometDim(host, sweepMs)
      return
    }

    // typewriter (default): every text unit shows its FIRST char (never an empty
    // box); every atomic unit is hidden so it reveals at its DOM position.
    for (const u of this.units) {
      if (u.kind === "text") u.node.nodeValue = u.full.slice(0, 1)
      else u.el.style.visibility = "hidden"
    }
    // FX: dim that prefilled first glyph to ~invisible so it reserves layout
    // WITHOUT a visible pop before the reveal runs; #runTypewriter snaps it back.
    this.#primeFirstGlyph()
  }

  // Dim the first text unit's host (only the prefilled first glyph is rendered
  // there at prime) so the reserved layout shows no visible glyph until the
  // reveal starts. Remembered so the run / instant / cancel paths can restore it.
  #primeFirstGlyph() {
    const first = this.units.find(u => u.kind === "text")
    const host  = first?.node.parentElement
    if (!host) return
    host.style.opacity = String(PRIME_OPACITY)
    this._primedGlyphHost = host
  }

  // Restore the primed first glyph to full opacity — a hard snap (no fade) as the
  // reveal begins. Idempotent; safe to call on every settle path.
  #clearPrimedGlyph() {
    const host = this._primedGlyphHost
    if (!host) return
    this._primedGlyphHost = null
    if (host.isConnected) host.style.opacity = ""
  }

  // Run the chosen effect to completion. Resolves ONCE when the reveal settles —
  // on natural completion, cancel, or instant-finish.
  run(effect) {
    return new Promise(resolve => {
      this._resolve = resolve
      if (this.cancelled) { this.finishInstant(); return }

      if (effect === "scramble") return this.#runScramble()
      if (effect === "comet")    return this.#runComet()
      return this.#runTypewriter()
    })
  }

  // Snap every unit to its final revealed state and settle (instant mode,
  // backpressure, or cancellation) — covers all effects.
  finishInstant() {
    this.#clearTimers()
    this.#clearPrimedGlyph()
    for (const u of this.units) this.#restoreUnit(u)
    this.#clearComet()
    this.#settle()
  }

  // Cancel an in-flight reveal: stop timers, restore content/visibility so a
  // removed/swapped element isn't left truncated/scrambled/hidden/dimmed, settle.
  cancel() {
    this.cancelled = true
    this.#clearTimers()
    this.#clearPrimedGlyph()
    for (const u of this.units) {
      const ref = u.kind === "text" ? u.node : u.el
      if (ref.isConnected) this.#restoreUnit(u)
    }
    this.#clearComet()
    this.#settle()
  }

  // ── private ────────────────────────────────────────────────────────────────

  #settle() {
    if (this._settled) return
    this._settled = true
    this._resolve?.()
  }

  #clearTimers() {
    for (const t of this._timers) clearTimeout(t)
    this._timers = []
  }

  // typewriter: advance charsPerTick chars per tick across unit boundaries;
  // atomic units un-hide (zero character cost) at their position.
  #runTypewriter() {
    this.#clearPrimedGlyph()   // FX: snap the first glyph to full as the reveal begins
    const { charsPerTick, tickMs } = this.#tickPlan()
    const units = this.units
    let idx = 0
    let pos = 1  // chars shown in the current text unit (first char prefilled)

    const tick = () => {
      if (this.cancelled) { this.finishInstant(); return }

      let charsLeft = charsPerTick
      while (charsLeft > 0 && idx < units.length) {
        const u = units[idx]

        if (u.kind === "atomic") {
          u.el.style.visibility = ""
          idx++
          pos = 1
          continue
        }

        const remaining = u.full.length - pos
        if (remaining <= 0) {
          u.node.nodeValue = u.full
          idx++
          pos = 1
        } else if (charsLeft >= remaining) {
          u.node.nodeValue = u.full
          charsLeft -= remaining
          idx++
          pos = 1
        } else {
          pos += charsLeft
          u.node.nodeValue = u.full.slice(0, pos)
          charsLeft = 0
        }
      }

      if (idx >= units.length) this.#settle()
      else this._timers.push(setTimeout(tick, tickMs))
    }

    this._timers.push(setTimeout(tick, tickMs))
  }

  // scramble: the WHOLE unresolved tail is live random-glyph noise that decrypts
  // left→right — every frame re-randomizes all not-yet-settled chars (that churn IS
  // the scramble look; blanking the tail would just be a typewriter). charsPerTick
  // positions settle to their real char per tick. The whole effect runs in
  // SCRAMBLE_SPEED_FACTOR × the engine log-scale budget so it finishes ~2× faster
  // than typewriter for the same content while still obeying the engine ceiling
  // ("engine owns the cap" — we multiply, never override it).
  // Final state == correct text; whitespace is always passed through unchanged.
  #runScramble() {
    const scDuration = this.duration * SCRAMBLE_SPEED_FACTOR
    const { charsPerTick, tickMs } = this.#tickPlan(scDuration)
    const total = this.totalChars

    const textUnits = []
    let off = 0
    for (const u of this.units) {
      if (u.kind === "text") { textUnits.push({ u, start: off }); off += u.full.length }
      else u.el.style.visibility = ""   // atomics stay fully visible under scramble
    }

    let resolved = 0

    const render = () => {
      for (const { u, start } of textUnits) {
        let out = ""
        for (let i = 0; i < u.full.length; i++) {
          const ch = u.full[i]
          if (/\s/.test(ch)) {
            out += ch                               // whitespace always preserved
          } else {
            const gIdx = start + i
            if (gIdx < resolved) {
              out += ch                             // already settled: exact char
            } else {
              out += this.#scrambleGlyph(ch)        // unresolved: whole tail is live noise
            }
          }
        }
        u.node.nodeValue = out
      }
    }

    const tick = () => {
      if (this.cancelled) { this.finishInstant(); return }

      resolved += charsPerTick
      if (resolved >= total) {
        for (const u of this.units) this.#restoreUnit(u)
        this.#settle()
        return
      }

      render()
      this._timers.push(setTimeout(tick, tickMs))
    }

    this._timers.push(setTimeout(tick, tickMs))
  }

  // comet: every host is already dimmed (primed) and stays hidden until the comet
  // reaches it. Each host's sweep STARTS at its staggered delay (delay-0 → next
  // tick) — raising it to full opacity and adding the mask-sweep class, so the
  // text is revealed left→right behind the comet. A single final timer at the
  // full budget restores everything to plain and settles. The last host finishes
  // within the budget, so the wait never exceeds the cap.
  #runComet() {
    const schedule = this._cometSchedule || this.#buildCometSchedule()

    for (const { host, delay } of schedule) {
      this._timers.push(setTimeout(() => {
        if (this.cancelled) return
        this.#cometSweep(host)
      }, Math.max(0, delay)))
    }

    this._timers.push(setTimeout(() => {
      if (this.cancelled) for (const u of this.units) this.#restoreUnit(u)
      this.#clearComet()
      this.#settle()
    }, this.duration))
  }

  // Tick cadence for typewriter/scramble: spread the budget over as many
  // character-advance steps as the frame budget allows, but never more steps than
  // there are chars (a tiny message still honors the floor).
  // `durationOverride` lets an effect use a scaled sub-budget (e.g. scramble) while
  // still deriving from the engine's log-scale ceiling.
  #tickPlan(durationOverride = null) {
    const duration     = durationOverride !== null ? durationOverride : this.duration
    const total        = Math.max(1, this.totalChars)
    const frames       = Math.max(1, Math.round(duration / FRAME_MS))
    const steps        = Math.max(1, Math.min(frames, total))
    const charsPerTick = Math.max(1, Math.ceil(total / steps))
    const tickMs       = duration / Math.max(1, Math.ceil(total / charsPerTick))
    return { charsPerTick, tickMs }
  }

  // The ordered, de-duplicated comet HOSTS (a text unit's host is its parent
  // element; an atomic unit's host is itself) with their staggered start delay
  // and own sweep duration. The last host finishes at exactly `duration`.
  #buildCometSchedule() {
    const seen  = new Set()
    const hosts = []
    for (const u of this.units) {
      const host = u.kind === "text" ? u.node.parentElement : u.el
      if (host && !seen.has(host)) { seen.add(host); hosts.push(host) }
    }

    const budget  = this.duration
    const n       = hosts.length
    const span    = n > 1 ? budget * COMET_STAGGER_SPAN : 0
    const sweepMs = budget - span   // n == 1 → full budget; n > 1 → short per-host sweep

    return hosts.map((host, i) => {
      const p     = n > 1 ? i / (n - 1) : 0
      // ease-out crescendo: gaps shrink toward the end (rows light up faster and
      // faster), while the endpoints stay 0 and `span`.
      const delay = span * (1 - (1 - p) ** 2)
      return { host, delay, sweepMs }
    })
  }

  // Restore a single unit to its full revealed state.
  #restoreUnit(u) {
    if (u.kind === "text") u.node.nodeValue = u.full
    else u.el.style.visibility = ""
  }

  // Dim a comet host to near-invisible and stamp its own sweep duration; remember
  // it for cleanup. No sweep yet — the host is hidden until the comet reaches it.
  #cometDim(host, sweepMs) {
    host.style.opacity = "0.01"
    host.style.setProperty("--pito-comet-ms", `${Math.round(sweepMs)}ms`)
    this._cometEls.add(host)
  }

  // Start a host's comet sweep: lift it out of the dim (the mask now governs the
  // spatial reveal) and add the sweep class. The duration var was set in dim.
  #cometSweep(host) {
    host.style.opacity = ""
    host.classList.add("pito-comet-reveal")
    this._cometEls.add(host)
  }

  // Clear every comet host back to full opacity (idempotent).
  #clearComet() {
    if (!this._cometEls) return
    for (const el of this._cometEls) {
      if (!el.isConnected) continue
      el.style.opacity = ""
      el.style.removeProperty("--pito-comet-ms")
      el.classList.remove("pito-comet-reveal")
    }
    this._cometEls.clear()
  }

  // A single "wrong" glyph for scramble — guaranteed different from the original.
  #scrambleGlyph(orig) {
    let g = orig
    for (let n = 0; n < 5 && g === orig; n++) {
      g = SCRAMBLE_GLYPHS[Math.floor(Math.random() * SCRAMBLE_GLYPHS.length)]
    }
    return g
  }

  // Fully-scrambled rendering of `full` (whitespace preserved) — the primed frame.
  #scrambleAll(full) {
    let out = ""
    for (const ch of full) out += /\s/.test(ch) ? ch : this.#scrambleGlyph(ch)
    return out
  }

  // Decompose a target element into an ordered list of reveal units (document
  // order). A text node with visible content becomes a `text` unit; an element
  // with NO visible text becomes an `atomic` unit. Elements that DO contain text
  // are descended into so their structure is preserved. ALWAYS-POP elements are
  // skipped entirely — never collected — so they render immediately and fully.
  #collectUnits(root) {
    const units = []

    const walk = (el) => {
      for (const child of el.childNodes) {
        if (child.nodeType === Node.TEXT_NODE) {
          const text = child.nodeValue
          if (text && /\S/.test(text)) units.push({ kind: "text", node: child, full: text, ref: child })
        } else if (child.nodeType === Node.ELEMENT_NODE) {
          if (this.#isAlwaysPop(child)) continue
          if (this.#hasVisibleText(child)) walk(child)
          else units.push({ kind: "atomic", el: child, ref: child })
        }
      }
    }

    if (this.#isAlwaysPop(root)) return units
    if (this.#hasVisibleText(root)) walk(root)
    else units.push({ kind: "atomic", el: root, ref: root })

    return units
  }

  #isAlwaysPop(el) {
    const list = el.classList
    if (!list || list.length === 0) return false
    for (const cls of list) {
      for (const re of ALWAYS_POP_PATTERNS) if (re.test(cls)) return true
    }
    return false
  }

  #hasVisibleText(el) {
    return /\S/.test(el.textContent || "")
  }
}
