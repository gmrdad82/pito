// spec/javascript/typewriter_controller.test.js
//
// Tests for the pito--typewriter controller (typewriter_controller.js).
//
// Strategy: mount the real controller on a jsdom segment with a `body` target
// plus several `prose` targets, then assert it collects + reveals ALL of them.
//
// Regression guard: the controller must use the singular Stimulus getter
// `hasProseTarget` (not `hasProseTargets`) — the plural is `undefined`, which
// once silently disabled prose collection so only the body animated. The
// "blanks all prose targets on connect" test fails if that collection branch
// is skipped.
//
// htmlProse targets: HTML cells (e.g. platform logo spans) carry the
// `htmlProse` target so the controller can hide them at connect and reveal
// them in DOM order during the animation sequence — preventing logos from
// popping in immediately while text cells are still being typed out.

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import TypewriterController from "controllers/pito/typewriter_controller"
import { enqueue, __resetForTest as resetRevealQueue } from "pito/reveal_queue"
import { revealDuration, REVEAL_MIN_MS, REVEAL_MAX_MS, SCRAMBLE_SPEED_FACTOR } from "pito/reveal_engine"

// Build a typewriter segment: one body target + N prose targets.
function buildSegment(bodyText, proseTexts = []) {
  const div = document.createElement("div")
  div.setAttribute("data-controller", "pito--typewriter")

  const body = document.createElement("span")
  body.setAttribute("data-pito--typewriter-target", "body")
  body.textContent = bodyText
  div.appendChild(body)

  const proses = proseTexts.map((t) => {
    const p = document.createElement("span")
    p.setAttribute("data-pito--typewriter-target", "prose")
    p.textContent = t
    div.appendChild(p)
    return p
  })

  document.body.appendChild(div)
  return { div, body, proses }
}

// Build a segment with mixed prose and htmlProse targets (mirrors the platform
// logo use-case: body + some prose text cells + one html logo cell).
function buildSegmentWithHtmlProse(bodyText, proseTexts = [], htmlContents = []) {
  const div = document.createElement("div")
  div.setAttribute("data-controller", "pito--typewriter")

  const body = document.createElement("span")
  body.setAttribute("data-pito--typewriter-target", "body")
  body.textContent = bodyText
  div.appendChild(body)

  proseTexts.forEach((t) => {
    const p = document.createElement("span")
    p.setAttribute("data-pito--typewriter-target", "prose")
    p.textContent = t
    div.appendChild(p)
  })

  const htmlEls = htmlContents.map((html) => {
    const p = document.createElement("span")
    p.setAttribute("data-pito--typewriter-target", "htmlProse")
    p.innerHTML = html
    div.appendChild(p)
    return p
  })

  document.body.appendChild(div)
  return { div, htmlEls }
}

// Build an html-ONLY card (the game/video detail, analytics, recommendation,
// shinies, error case): a typewriter controller whose only target is a single
// htmlProse wrapper holding the whole card — no plain-text body target. Reveal
// is the visibility toggle. `withController: false` mirrors the server-side
// reply_consumed suppression (no data-controller mounted at all).
function buildHtmlCard(html, { withController = true } = {}) {
  const div = document.createElement("div")
  if (withController) div.setAttribute("data-controller", "pito--typewriter")

  const card = document.createElement("div")
  card.setAttribute("data-pito--typewriter-target", "htmlProse")
  card.innerHTML = html
  div.appendChild(card)

  document.body.appendChild(div)
  return { div, card }
}

describe("pito--typewriter controller", () => {
  let app

  beforeEach(() => {
    // Reset the module-global reveal-queue backpressure counter so a prior test's
    // job can't push this test's reveal into instant mode.
    resetRevealQueue()
    // jsdom has no matchMedia; the controller calls it in #skipAnimation.
    window.matchMedia = () => ({ matches: false })
    // Live arrival (so the controller animates rather than rendering instant).
    window.__pitoReady = true
    // No #pito-settings element → fxEnabled() fails open (true).

    app = Application.start()
    app.register("pito--typewriter", TypewriterController)
  })

  afterEach(async () => {
    await app.stop() // disconnect() cancels + restores + drains the reveal queue
    document.body.innerHTML = ""
    delete window.__pitoReady
  })

  function waitForConnect() {
    return new Promise((r) => setTimeout(r, 0))
  }

  it("prefills the FIRST char of the body AND every prose target on connect (K2 + regression: prose collection)", async () => {
    // K2: a text unit is never an empty/flat box — it starts with its first
    // character already in place, then types the rest.
    const { body, proses } = buildSegment("hello world", ["SECTION", "key", "value"])
    await waitForConnect()

    expect(body.textContent).toBe("h")
    expect(proses.map((p) => p.textContent)).toEqual(["S", "k", "v"])
  })

  it("reveals the body and all prose targets to their full text", async () => {
    const { body, proses } = buildSegment("hi", ["xy", "z"])
    await waitForConnect()
    // Small texts type out well within this window (TICK_MS=12, CHARS_TICK=2).
    await new Promise((r) => setTimeout(r, 400))

    expect(body.textContent).toBe("hi")
    expect(proses.map((p) => p.textContent)).toEqual(["xy", "z"])
  })

  it("does not animate (no blanking) on the initial server render (__pitoReady falsy)", async () => {
    window.__pitoReady = false
    const { body, proses } = buildSegment("hello", ["AAA"])
    await waitForConnect()

    expect(body.textContent).toBe("hello")
    expect(proses[0].textContent).toBe("AAA")
  })

  it("animates the body even when there are no prose targets", async () => {
    const { body } = buildSegment("just a body")
    await waitForConnect()

    expect(body.textContent).toBe("j") // K2: first char prefilled, not empty
    await new Promise((r) => setTimeout(r, 800))
    expect(body.textContent).toBe("just a body")
  })

  it("reveals a plain body PROGRESSIVELY, not all at once (fresh live message)", async () => {
    // A long body so the reveal spans many ticks (TICK_MS=12, CHARS_TICK=2):
    // mid-flight it must be partially typed — proof it is NOT instant.
    const full = "x".repeat(120)
    const { body } = buildSegment(full)
    await waitForConnect()

    // Sample mid-animation: some chars revealed, but not the whole body yet.
    await new Promise((r) => setTimeout(r, 80))
    const mid = body.textContent.length
    expect(mid).toBeGreaterThan(0)
    expect(mid).toBeLessThan(full.length)

    // And it eventually completes.
    await new Promise((r) => setTimeout(r, 1500))
    expect(body.textContent).toBe(full)
  })

  describe("htmlProse targets — reveal gating for HTML cells (platform logos)", () => {
    it("hides htmlProse targets immediately on connect (before animation starts)", async () => {
      const { htmlEls } = buildSegmentWithHtmlProse("body text", ["prose text"], ["<img src='ps.svg'>"])
      await waitForConnect()

      // Hidden synchronously in connect() before the reveal job runs.
      expect(htmlEls[0].style.visibility).toBe("hidden")
    })

    it("reveals htmlProse targets after animation completes", async () => {
      const { htmlEls } = buildSegmentWithHtmlProse("hi", ["ok"], ["<img src='ps.svg'>"])
      await waitForConnect()
      // Wait for animation to finish (TICK_MS=12, short texts done well within 400ms).
      await new Promise((r) => setTimeout(r, 400))

      expect(htmlEls[0].style.visibility).toBe("")
    })

    it("reveals htmlProse targets in instant mode (backpressure / __pitoReady false)", async () => {
      window.__pitoReady = false
      const { htmlEls } = buildSegmentWithHtmlProse("body", [], ["<img src='icon.svg'>"])
      await waitForConnect()

      // No controller connected (skipAnimation returned early) — element unmodified.
      expect(htmlEls[0].style.visibility).toBe("")
    })

    it("does NOT hide htmlProse targets when animation is skipped (__pitoReady falsy)", async () => {
      window.__pitoReady = false
      const { htmlEls } = buildSegmentWithHtmlProse("hello", ["world"], ["<img src='x.svg'>"])
      await waitForConnect()

      expect(htmlEls[0].style.visibility).not.toBe("hidden")
    })
  })

  // ── html-ONLY cards (detail / analytics / recommendation / shinies / error) ──
  // These carry no plain-text body target — only an htmlProse wrapper revealed
  // via the visibility toggle, sequenced through the shared reveal queue.
  describe("html-only cards — reveal with no body target", () => {
    it("types a text card in place (wrapper stays visible, first char prefilled) then completes", async () => {
      // A text-bearing card is NOT hidden as a whole — its structure stays
      // visible and its text types in (first char prefilled, K2). Only text-free
      // visuals are hidden/revealed (see the atomic-reveal tests below).
      const { card } = buildHtmlCard("<div class='card'>game detail</div>")
      await waitForConnect()
      expect(card.style.visibility).toBe("")  // wrapper never hidden
      expect(card.textContent).toBe("g")      // first char prefilled, not empty

      await new Promise((r) => setTimeout(r, 800))
      expect(card.textContent).toBe("game detail")
    })

    it("hides a text-FREE (image-only) card on connect and reveals it as one atomic unit", async () => {
      // A card whose only content is an image carries no text — it is hidden on
      // connect and un-hidden when the reveal cursor reaches it.
      const { card } = buildHtmlCard("<img src='cover.jpg'>")
      await waitForConnect()
      expect(card.style.visibility).toBe("hidden")

      await new Promise((r) => setTimeout(r, 800))
      expect(card.style.visibility).toBe("")
    })

    it("TYPES the card's text PROGRESSIVELY, not a single whole-card pop-in (regression)", async () => {
      // Regression: a whole-card htmlProse wrapper used to be revealed by ONE
      // visibility flip, so every detail/list/enhanced card appeared all at once.
      // It must now un-hide the wrapper AND type its descendant text in place.
      const text = "y".repeat(120)
      const { card } = buildHtmlCard(`<div class='card'><span>${text}</span></div>`)
      await waitForConnect()
      // First char prefilled while the rest waits to type (K2) — never empty.
      expect(card.textContent).toBe("y")

      // Mid-animation: the wrapper is visible (structure shown) but the text is
      // only partially typed — proof it is NOT a single instant pop-in.
      await new Promise((r) => setTimeout(r, 80))
      expect(card.style.visibility).toBe("")
      const mid = card.textContent.length
      expect(mid).toBeGreaterThan(0)
      expect(mid).toBeLessThan(text.length)

      // Eventually the full text is revealed.
      await new Promise((r) => setTimeout(r, 1500))
      expect(card.textContent).toBe(text)
    })

    it("types EVERY text node of a multi-element card in document order", async () => {
      const { card } = buildHtmlCard(
        "<div><span>alpha</span><div><b>bravo</b> charlie</div></div>"
      )
      await waitForConnect()
      await new Promise((r) => setTimeout(r, 900))

      // All text restored, structure intact.
      expect(card.querySelector("span").textContent).toBe("alpha")
      expect(card.querySelector("b").textContent).toBe("bravo")
      expect(card.textContent).toContain("charlie")
    })

    it("prefills the FIRST char of EVERY text node in a multi-node card (K2)", async () => {
      const { card } = buildHtmlCard("<div><span>alpha</span><span>bravo</span></div>")
      await waitForConnect()
      const spans = card.querySelectorAll("span")
      expect(spans[0].textContent).toBe("a")
      expect(spans[1].textContent).toBe("b")
    })

    it("reveals an image only AFTER the text before it has typed (K6.3 reading order)", async () => {
      // A cover-art image must not pop in before the title/text above it. The
      // image (a text-free atomic unit) stays hidden until the reveal cursor —
      // typing top-to-bottom — reaches its DOM position.
      const text = "T".repeat(80)
      const { card } = buildHtmlCard(`<div><span>${text}</span><img src='cover.jpg'></div>`)
      await waitForConnect()
      const img = card.querySelector("img")

      expect(img.style.visibility).toBe("hidden") // hidden on connect

      // Mid-reveal: the preceding text is still typing → the image is STILL hidden.
      await new Promise((r) => setTimeout(r, 80))
      expect(card.textContent.length).toBeLessThan(text.length)
      expect(img.style.visibility).toBe("hidden")

      // After the text finishes, the image is revealed.
      await new Promise((r) => setTimeout(r, 1500))
      expect(card.textContent).toBe(text)
      expect(img.style.visibility).toBe("")
    })

    it("animates a NEW card concurrently — it is NOT blocked by an in-flight one (K3)", async () => {
      // Regression guard against the old global FIFO: a short card mounted
      // alongside a long one must type AND finish while the long one is still
      // animating — proof reveals run concurrently, not serialised behind a slow
      // earlier card.
      const long  = "A".repeat(400)
      const slow  = buildHtmlCard(`<div><span>${long}</span></div>`)
      const fast  = buildHtmlCard("<div><span>hi</span></div>")
      await waitForConnect()

      // Enough time for the short card to fully type; the long card is still going.
      await new Promise((r) => setTimeout(r, 600))

      expect(fast.card.textContent).toBe("hi")                       // finished independently
      expect(slow.card.textContent.length).toBeLessThan(long.length) // still typing
    })

    it("does NOT reveal/animate when there is no controller (reply_consumed render)", async () => {
      // Server suppresses data-controller for consumed cards — the controller
      // never connects, so the card is never hidden (renders instantly).
      const { card } = buildHtmlCard("<div>historical card</div>", { withController: false })
      await waitForConnect()

      expect(card.style.visibility).toBe("")
    })

    it("renders the html card instantly on initial server render (__pitoReady falsy)", async () => {
      window.__pitoReady = false
      const { card } = buildHtmlCard("<div>card</div>")
      await waitForConnect()

      expect(card.style.visibility).not.toBe("hidden")
    })

    it("renders the html card instantly under prefers-reduced-motion", async () => {
      window.matchMedia = () => ({ matches: true })
      const { card } = buildHtmlCard("<div>card</div>")
      await waitForConnect()

      expect(card.style.visibility).not.toBe("hidden")
    })

    it("settles the reveal queue when disconnected mid-reveal (queue not stalled)", async () => {
      // Mount an html card (enqueues a reveal job), then disconnect it before the
      // job finishes by removing it from the DOM. The disconnect must settle the
      // in-flight promise so a later job still runs — otherwise the FIFO stalls.
      const { div, card } = buildHtmlCard("<img src='swapme.jpg'>")
      await waitForConnect()
      expect(card.style.visibility).toBe("hidden")

      // Simulate a Turbo replace mid-reveal: remove the element → disconnect().
      div.remove()
      await waitForConnect()

      // A follow-up reveal job must still be reached (queue drained, not hung) —
      // this is the landmine: a disconnect mid-reveal that fails to settle the
      // in-flight promise would stall every later message.
      let ran = false
      await enqueue(() => {
        ran = true
        return Promise.resolve()
      })
      expect(ran).toBe(true)
    })

    it("restores visibility on disconnect for a still-connected element", async () => {
      // When the element stays in the DOM (controller detached, not swapped),
      // disconnect restores its content so it is never left hidden/truncated.
      const { div, card } = buildHtmlCard("<img src='stay.jpg'>")
      await waitForConnect()
      expect(card.style.visibility).toBe("hidden")

      div.removeAttribute("data-controller") // Stimulus disconnects the controller
      await waitForConnect()

      expect(card.isConnected).toBe(true)
      expect(card.style.visibility).toBe("")
    })
  })

  // ── completion signal (doneEvent value) — the echo comet trigger ─────────────
  // The echo segment mounts the typewriter with a `doneEvent` value of
  // "pito:echo-typed". The controller must dispatch that document event ONCE the
  // reveal settles — on BOTH the animated path (after the text types out) AND the
  // instant/skip path (where no animation runs but the comet must still clear).
  describe("doneEvent completion signal (echo-style mount)", () => {
    // Build an echo-style segment: a body target plus a doneEvent value.
    function buildEcho(text, doneEvent = "pito:echo-typed") {
      const div = document.createElement("div")
      div.setAttribute("data-controller", "pito--typewriter")
      div.setAttribute("data-pito--typewriter-done-event-value", doneEvent)

      const body = document.createElement("span")
      body.setAttribute("data-pito--typewriter-target", "body")
      body.textContent = text
      div.appendChild(body)

      document.body.appendChild(div)
      return { div, body }
    }

    it("dispatches doneEvent after the text finishes typing (animated path)", async () => {
      let caught = null
      document.addEventListener("pito:echo-typed", (e) => { caught = e }, { once: true })

      const { body } = buildEcho("list videos")
      await waitForConnect()

      // First char prefilled (K2) — not yet fully typed, not yet signalled.
      expect(body.textContent).toBe("l")
      expect(caught).toBeNull()

      // Let the short text type out (log-scaled floor ≈ 0.4s, a bit over for 11 chars).
      await new Promise((r) => setTimeout(r, 800))

      expect(body.textContent).toBe("list videos")
      expect(caught).not.toBeNull()
    })

    it("dispatches doneEvent immediately on the instant/skip path (__pitoReady falsy)", async () => {
      window.__pitoReady = false
      let caught = null
      document.addEventListener("pito:echo-typed", (e) => { caught = e }, { once: true })

      const { body } = buildEcho("list videos")
      await waitForConnect()

      // Rendered instant (no blanking) AND the comet-clearing event still fired.
      expect(body.textContent).toBe("list videos")
      expect(caught).not.toBeNull()
    })

    it("dispatches doneEvent on the instant/skip path under prefers-reduced-motion", async () => {
      window.matchMedia = () => ({ matches: true })
      let caught = null
      document.addEventListener("pito:echo-typed", (e) => { caught = e }, { once: true })

      const { body } = buildEcho("hello")
      await waitForConnect()

      expect(body.textContent).toBe("hello")
      expect(caught).not.toBeNull()
    })

    it("dispatches doneEvent with bubbles: true", async () => {
      window.__pitoReady = false
      let caught = null
      document.addEventListener("pito:echo-typed", (e) => { caught = e }, { once: true })

      buildEcho("hi")
      await waitForConnect()

      expect(caught?.bubbles).toBe(true)
    })

    it("does NOT dispatch any completion event when no doneEvent value is set", async () => {
      let caught = false
      document.addEventListener("pito:echo-typed", () => { caught = true })

      // A plain body mount (no doneEvent) — the default for non-echo segments.
      buildSegment("plain body")
      await waitForConnect()
      await new Promise((r) => setTimeout(r, 400))

      expect(caught).toBe(false)
    })
  })

  // ── effect resolution + the three reveal effects (L1/L2/L3) ──────────────────
  // Resolution contract: element's own `effect` value → global fxEffect() →
  // "typewriter". A per-element override wins so a showcase row forces an effect
  // regardless of the global /config setting.
  describe("reveal effects", () => {
    // Mount a single-body segment with an optional per-element effect override
    // and/or doneEvent value.
    function buildFx(text, { effect, doneEvent } = {}) {
      const div = document.createElement("div")
      div.setAttribute("data-controller", "pito--typewriter")
      if (effect) div.setAttribute("data-pito--typewriter-effect-value", effect)
      if (doneEvent) div.setAttribute("data-pito--typewriter-done-event-value", doneEvent)

      const body = document.createElement("span")
      body.setAttribute("data-pito--typewriter-target", "body")
      body.textContent = text
      div.appendChild(body)

      document.body.appendChild(div)
      return { div, body }
    }

    // Set the GLOBAL effect via the #pito-settings element fxEffect() reads.
    function setGlobalFx(effect) {
      let el = document.getElementById("pito-settings")
      if (!el) { el = document.createElement("div"); el.id = "pito-settings"; document.body.appendChild(el) }
      el.dataset.fxEffect = effect
      return el
    }

    // ── effect resolution ──────────────────────────────────────────────────
    describe("effect resolution (override → global → default)", () => {
      it("defaults to typewriter when neither an element override nor a global is set", async () => {
        const { body } = buildFx("hello world")
        await waitForConnect()
        // Typewriter primes the FIRST char only (not the whole text, not scrambled).
        expect(body.textContent).toBe("h")
        expect(body.style.opacity).not.toBe("0.01") // not comet
      })

      it("uses the global fxEffect() when there is NO element override", async () => {
        setGlobalFx("scramble")
        const { body } = buildFx("hello world") // no per-element effect
        await waitForConnect()
        // Scramble primes a fully-visible, fully-WRONG string of the same length.
        expect(body.textContent).not.toBe("hello world")
        expect(body.textContent.length).toBe("hello world".length)
      })

      it("the per-element effect override BEATS the global fxEffect()", async () => {
        setGlobalFx("typewriter")             // global says typewriter…
        const { body } = buildFx("hello world", { effect: "comet" }) // …element forces comet
        await waitForConnect()
        // Comet primes its host HIDDEN (~0.01 opacity) with its sweep duration
        // stamped — proof the override won over the global typewriter (which would
        // prime "h"). Content is already correct, just dimmed until the sweep.
        expect(body.style.opacity).toBe("0.01")
        expect(body.style.getPropertyValue("--pito-comet-ms")).toMatch(/ms$/)
        expect(body.textContent).toBe("hello world")
      })
    })

    // ── L1 typewriter — log-scaled timing ──────────────────────────────────
    describe("L1 typewriter (log-scaled)", () => {
      it("reveals progressively (not instant) and a SHORT message hits the fast floor", async () => {
        const { body } = buildFx("hello", { effect: "typewriter" }) // ≤ base → floor ≈ 0.4s
        await waitForConnect()

        // Animating, not instant: only the prefilled first char shows so far
        // (queue reset in beforeEach guarantees no backpressure instant-snap).
        expect(body.textContent).toBe("h")
        expect(body.textContent).not.toBe("hello")

        // Completes near the floor (≈ 0.4s), not dragging.
        await new Promise((r) => setTimeout(r, 700))
        expect(body.textContent).toBe("hello")
      })

      it("CAPS a very long message (log-scale) instead of dragging linearly", async () => {
        // A linear char cadence would take this many chars ~18s; the log cap keeps
        // the whole reveal under ~2.5s. Prove it animates (only the prefill shows
        // right after connect), then is fully done well before any linear schedule.
        const full = "x".repeat(3000)
        const { body } = buildFx(full, { effect: "typewriter" })
        await waitForConnect()

        expect(body.textContent.length).toBeLessThan(full.length) // not instant

        await new Promise((r) => setTimeout(r, 2700)) // > cap (2.5s) + overhead
        expect(body.textContent).toBe(full)           // capped, not dragging
      })
    })

    // ── L2 scramble — wrong-then-resolve ───────────────────────────────────
    describe("L2 scramble", () => {
      it("starts FULLY VISIBLE but wrong, then resolves to the EXACT text", async () => {
        const full = "hello world"
        const { body } = buildFx(full, { effect: "scramble" })
        await waitForConnect()

        // Primed: same length, but not the correct text (every glyph wrong).
        expect(body.textContent.length).toBe(full.length)
        expect(body.textContent).not.toBe(full)

        // Settles to the exact correct text.
        await new Promise((r) => setTimeout(r, 800))
        expect(body.textContent).toBe(full)
      })

      it("preserves whitespace positions while scrambling", async () => {
        const full = "ab cd ef" // spaces at indices 2 and 5
        const { body } = buildFx(full, { effect: "scramble" })
        await waitForConnect()

        expect(body.textContent[2]).toBe(" ")
        expect(body.textContent[5]).toBe(" ")
      })

      it("finishes in SCRAMBLE_SPEED_FACTOR × engine duration — shorter than the full typewriter budget", async () => {
        // 40 chars → engineDuration ≈ 850ms; scramble budget ≈ 425ms.
        // The speed factor is strictly < 1, so scramble is always faster.
        const full = "x".repeat(40)
        const engineDuration     = revealDuration(40)
        const scrambleDuration   = engineDuration * SCRAMBLE_SPEED_FACTOR

        expect(scrambleDuration).toBeLessThan(engineDuration) // math sanity

        const { body } = buildFx(full, { effect: "scramble" })
        await waitForConnect()
        expect(body.textContent).not.toBe(full) // still animating on connect

        // Resolves within the scramble budget (+ generous jsdom timing overhead).
        await new Promise(r => setTimeout(r, scrambleDuration + 250))
        expect(body.textContent).toBe(full)
      })

      it("keeps the WHOLE unresolved tail as live noise (not a blank typewriter reveal)", async () => {
        // Regression guard: scramble must look like scramble, not typewriter. The
        // entire not-yet-settled tail is random glyphs every frame — it never blanks
        // ahead of a frontier. "A".repeat(60) has NO spaces and SCRAMBLE_GLYPHS has
        // NO space, so a real scramble shows 60 non-space chars throughout (settled
        // A's + glyph noise); a blanked/typewriter reveal would introduce spaces.
        const full = "A".repeat(60)
        const { body } = buildFx(full, { effect: "scramble" })
        await waitForConnect()

        // Mid-animation: full row present, no blanks — the whole tail is live noise.
        await new Promise(r => setTimeout(r, 30))
        const mid = body.textContent

        expect(mid).not.toBe(full)              // still animating
        expect(mid.length).toBe(full.length)    // whole row rendered (nothing blanked)
        expect(mid).not.toContain(" ")          // entire tail is glyphs, never a blank placeholder

        // Eventually the full correct text is restored.
        await new Promise(r => setTimeout(r, 1000))
        expect(body.textContent).toBe(full)
      })
    })

    // ── L3 comet — opacity sweep ───────────────────────────────────────────
    describe("L3 comet-sweep", () => {
      it("renders content HIDDEN, reveals it as the sweep passes, and ends correct", async () => {
        const full = "comet message here"
        const { body } = buildFx(full, { effect: "comet" })
        await waitForConnect()

        // Primed: content correct but HIDDEN (~0.01) with its duration stamped —
        // nothing visible before the comet reaches it, so NO sweep class yet.
        expect(body.textContent).toBe(full)
        expect(body.style.opacity).toBe("0.01")
        expect(body.classList.contains("pito-comet-reveal")).toBe(false)
        expect(body.style.getPropertyValue("--pito-comet-ms")).toMatch(/ms$/)

        // The sweep then begins (single host → starts immediately): the host is
        // lifted to full opacity and the mask-sweep class drives the reveal.
        await new Promise((r) => setTimeout(r, 20))
        expect(body.classList.contains("pito-comet-reveal")).toBe(true)
        expect(body.style.opacity).toBe("")

        // After the sweep: full opacity, class cleared, content still correct.
        await new Promise((r) => setTimeout(r, 1600))
        expect(body.textContent).toBe(full)
        expect(body.style.opacity).toBe("")
        expect(body.classList.contains("pito-comet-reveal")).toBe(false)
      })

      it("fires the doneEvent after the comet settles", async () => {
        let caught = null
        document.addEventListener("pito:comet-done", (e) => { caught = e }, { once: true })

        buildFx("comet finishes", { effect: "comet", doneEvent: "pito:comet-done" })
        await waitForConnect()
        expect(caught).toBeNull() // still sweeping

        await new Promise((r) => setTimeout(r, 1600))
        expect(caught).not.toBeNull()
      })

      // ── shared engine log-scale (no separate comet constants) ────────────
      // Comet must derive its --pito-comet-ms from the same #revealDurationMs
      // engine function as typewriter and scramble — REVEAL_MIN_MS=400 /
      // REVEAL_MAX_MS=2500.  There are no separate COMET_MIN_MS / COMET_MAX_MS.
      describe("timing is derived from the shared engine log-scale", () => {
        it("short message (≤ REVEAL_BASE chars): --pito-comet-ms sits at the engine floor (400ms)", async () => {
          // "hi" = 2 chars, well below REVEAL_BASE=8 → revealDuration returns REVEAL_MIN_MS exactly.
          const { body } = buildFx("hi", { effect: "comet" })
          await waitForConnect()

          const ms = parseInt(body.style.getPropertyValue("--pito-comet-ms"))
          expect(ms).toBe(400)
        })

        it("very long message (>> REVEAL_BASE): --pito-comet-ms hits the engine cap (2500ms)", async () => {
          // 10000 chars far exceeds the log-scale inflection; min(2500, …) clamps to REVEAL_MAX_MS.
          const long = "x".repeat(10000)
          const { body } = buildFx(long, { effect: "comet" })
          await waitForConnect()

          const ms = parseInt(body.style.getPropertyValue("--pito-comet-ms"))
          expect(ms).toBe(2500)
        })

        it("comet --pito-comet-ms always falls within [REVEAL_MIN_MS, REVEAL_MAX_MS] = [400, 2500]", async () => {
          // A moderate-length message must land inside the shared engine band, not
          // inside any old comet-specific band (e.g. the removed [360, 1400]).
          const text = "a moderately long chat message to check the shared band"
          const { body } = buildFx(text, { effect: "comet" })
          await waitForConnect()

          const ms = parseInt(body.style.getPropertyValue("--pito-comet-ms"))
          expect(ms).toBeGreaterThanOrEqual(400)
          expect(ms).toBeLessThanOrEqual(2500)
        })
      })

      // ── per-host stagger (cascade / crescendo) ───────────────────────────
      // The comet must reveal PER HOST with progressive start offsets — each
      // text host begins its short sweep a bit later than the previous one — and
      // the LAST host must still FINISH within the engine's log-capped budget,
      // so a long message never produces a wait past the cap.
      describe("per-host stagger (cascade)", () => {
        // A card whose only content is N sibling spans, each its own comet host.
        function buildCometCard(spanTexts) {
          const div = document.createElement("div")
          div.setAttribute("data-controller", "pito--typewriter")
          div.setAttribute("data-pito--typewriter-effect-value", "comet")

          const card = document.createElement("div")
          card.setAttribute("data-pito--typewriter-target", "htmlProse")
          card.innerHTML = spanTexts.map((t) => `<span>${t}</span>`).join("")
          div.appendChild(card)

          document.body.appendChild(div)
          return { div, spans: [...card.querySelectorAll("span")] }
        }

        it("primes ALL hosts HIDDEN with NONE swept; then the FIRST host begins, later hosts stay dimmed", async () => {
          // 3 long spans → budget hits the cap (2500ms) so later host delays
          // (~1125ms, ~1500ms) are unmistakably non-zero.
          const { spans } = buildCometCard(["a".repeat(2000), "b".repeat(2000), "c".repeat(2000)])
          await waitForConnect()

          // On prime EVERY host is hidden (~0.01) and NONE has begun its sweep —
          // nothing is visible before the comet reaches it (the LOCKED intent).
          spans.forEach((s) => {
            expect(s.style.opacity).toBe("0.01")
            expect(s.classList.contains("pito-comet-reveal")).toBe(false)
          })

          // The cascade then starts: the first host sweeps (lifted to full opacity)
          // while the staggered later hosts stay dimmed and hidden.
          await new Promise((r) => setTimeout(r, 20))
          expect(spans[0].classList.contains("pito-comet-reveal")).toBe(true)
          expect(spans[0].style.opacity).toBe("")
          expect(spans[1].classList.contains("pito-comet-reveal")).toBe(false)
          expect(spans[1].style.opacity).toBe("0.01")
          expect(spans[2].classList.contains("pito-comet-reveal")).toBe(false)
          expect(spans[2].style.opacity).toBe("0.01")
        })

        it("raises each host to full opacity ONLY at/after its staggered start (not at t=0)", async () => {
          const { spans } = buildCometCard(["a".repeat(2000), "b".repeat(2000), "c".repeat(2000)])
          await waitForConnect()

          // delays ≈ [0, 1125, 1500] over the capped 2500ms budget. Sample after
          // the first offset but before the second: only host 0 is at full opacity.
          await new Promise((r) => setTimeout(r, 20))
          expect(spans[0].style.opacity).toBe("")    // revealed
          expect(spans[1].style.opacity).toBe("0.01") // still hidden
          expect(spans[2].style.opacity).toBe("0.01") // still hidden

          // Past the second offset: host 1 has now been lifted; host 2 still waits.
          await new Promise((r) => setTimeout(r, 1250))
          expect(spans[1].style.opacity).toBe("")
          expect(spans[2].style.opacity).toBe("0.01")
        })

        it("each host's own sweep is SHORT (a fraction of the budget), not the whole budget", async () => {
          // Single host sweeps over the whole budget; multiple hosts share it, so
          // each per-host --pito-comet-ms is strictly less than the budget.
          const { spans } = buildCometCard(["a".repeat(2000), "b".repeat(2000), "c".repeat(2000)])
          await waitForConnect()

          const budget = revealDuration(6000) // == REVEAL_MAX_MS (2500), capped
          expect(budget).toBe(REVEAL_MAX_MS)
          const sweepMs = parseInt(spans[0].style.getPropertyValue("--pito-comet-ms"))
          expect(sweepMs).toBeGreaterThan(0)
          expect(sweepMs).toBeLessThan(budget) // short per-host sweep, not the full budget
        })

        it("lights hosts up PROGRESSIVELY — a later host begins only after its offset elapses", async () => {
          const { spans } = buildCometCard(["a".repeat(2000), "b".repeat(2000), "c".repeat(2000)])
          await waitForConnect()

          // Mid-budget: the second host has started (offset ~1125ms) but the LAST
          // host (offset ~1500ms) has not — proof the sweep cascades, not all-at-once.
          await new Promise((r) => setTimeout(r, 1250))
          expect(spans[1].classList.contains("pito-comet-reveal")).toBe(true)
          expect(spans[2].classList.contains("pito-comet-reveal")).toBe(false)
        })

        it("the LAST host FINISHES within the engine budget (long → capped at 2500ms)", async () => {
          const { spans } = buildCometCard(["a".repeat(2000), "b".repeat(2000), "c".repeat(2000)])
          await waitForConnect()

          const budget = revealDuration(6000) // 2500ms cap
          // Just before the budget elapses the cascade is still running (the last
          // host has started but the final settle has not cleared everything yet).
          await new Promise((r) => setTimeout(r, budget - 300))
          expect(spans[2].classList.contains("pito-comet-reveal")).toBe(true)

          // By the budget (+overhead) every host has settled to full opacity, class
          // cleared, content intact — the whole comet completed by the cap.
          await new Promise((r) => setTimeout(r, 600))
          spans.forEach((s, i) => {
            expect(s.style.opacity).toBe("")
            expect(s.classList.contains("pito-comet-reveal")).toBe(false)
            expect(s.textContent).toBe([..."abc"][i].repeat(2000))
          })
        })

        it("a SHORT multi-host comet finishes by the engine floor (≈400ms)", async () => {
          // Tiny content → budget == REVEAL_MIN_MS (400). The whole staggered
          // cascade must still complete right around the floor, never dragging.
          const { spans } = buildCometCard(["a", "b", "c"])
          await waitForConnect()
          expect(revealDuration(3)).toBe(REVEAL_MIN_MS)

          await new Promise((r) => setTimeout(r, REVEAL_MIN_MS + 300))
          spans.forEach((s) => {
            expect(s.style.opacity).toBe("")
            expect(s.classList.contains("pito-comet-reveal")).toBe(false)
          })
        })
      })
    })

    // ── skip guards apply to ALL three effects ─────────────────────────────
    describe("skip guards (instant + doneEvent) for every effect", () => {
      const EFFECTS = ["typewriter", "scramble", "comet"]

      EFFECTS.forEach((effect) => {
        it(`${effect}: renders instant and fires doneEvent on initial load (__pitoReady falsy)`, async () => {
          window.__pitoReady = false
          let caught = null
          document.addEventListener("pito:skip-done", (e) => { caught = e }, { once: true })

          const { body } = buildFx("instant text here", { effect, doneEvent: "pito:skip-done" })
          await waitForConnect()

          // Final content immediately — never scrambled, dimmed, or truncated.
          expect(body.textContent).toBe("instant text here")
          expect(body.style.opacity).not.toBe("0.01")
          expect(body.classList.contains("pito-comet-reveal")).toBe(false)
          expect(caught).not.toBeNull()
        })

        it(`${effect}: renders instant and fires doneEvent under prefers-reduced-motion`, async () => {
          window.matchMedia = () => ({ matches: true })
          let caught = null
          document.addEventListener("pito:rm-done", (e) => { caught = e }, { once: true })

          const { body } = buildFx("reduced motion text", { effect, doneEvent: "pito:rm-done" })
          await waitForConnect()

          expect(body.textContent).toBe("reduced motion text")
          expect(body.style.opacity).not.toBe("0.01")
          expect(caught).not.toBeNull()
        })
      })
    })
  })

  // ── L4 always-pop set — never animated under ANY effect ──────────────────────
  // Bars / covers / thumbnails / avatars (allowlisted classes) render whole and
  // immediately at their DOM position, even when they carry text and even when a
  // chosen effect would otherwise touch them.
  describe("L4 always-pop set", () => {
    // One representative real class per allowlist pattern.
    const ALWAYS_POP_CLASSES = [
      "pito-score-bar",                                // score bars
      "pito-ttb",                                      // time-to-beat bars
      "pito-game-detail__cover",                       // big detail / Ken-Burns cover
      "pito-game-enhanced-message__similar-game-cover",// list-size strip cover
      "pito-video-linked-game-card__cover",            // linked-card cover
      "pito-cover-pan",                                // the Ken-Burns <img>
      "pito-video-detail__thumbnail",                  // video thumbnail
      "pito-channel-item__avatar",                     // avatar (item)
      "pito-channel-list__avatar",                     // avatar (list)
      "pito-metric"                                    // analytics widget (owns its own reveal)
    ]
    const EFFECTS = ["typewriter", "scramble", "comet"]

    // A card with a typing-able title PLUS an always-pop element that carries text.
    function buildWithPop(klass, effect) {
      const div = document.createElement("div")
      div.setAttribute("data-controller", "pito--typewriter")
      if (effect) div.setAttribute("data-pito--typewriter-effect-value", effect)

      const card = document.createElement("div")
      card.setAttribute("data-pito--typewriter-target", "htmlProse")
      card.innerHTML = `<span class="title">a typing title here</span><span class="${klass}">POP</span>`
      div.appendChild(card)

      document.body.appendChild(div)
      return { div, card, pop: card.querySelector("." + klass) }
    }

    EFFECTS.forEach((effect) => {
      ALWAYS_POP_CLASSES.forEach((klass) => {
        it(`${effect}: .${klass} pops whole — never typed/scrambled/dimmed`, async () => {
          const { pop } = buildWithPop(klass, effect)
          await waitForConnect()

          // Immediately present, full, and visible — under every effect.
          expect(pop.textContent).toBe("POP")               // not typed/scrambled
          expect(pop.style.visibility).not.toBe("hidden")   // not held back (typewriter atomic)
          expect(pop.style.opacity).not.toBe("0.01")        // not dimmed (comet)
          expect(pop.classList.contains("pito-comet-reveal")).toBe(false)

          // …and still intact after the reveal settles.
          await new Promise((r) => setTimeout(r, 900))
          expect(pop.textContent).toBe("POP")
          expect(pop.style.visibility).not.toBe("hidden")
        })
      })
    })
  })
})
