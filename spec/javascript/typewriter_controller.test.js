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
import { enqueue } from "pito/reveal_queue"

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

  it("blanks the body AND every prose target on connect (regression: prose collection)", async () => {
    const { body, proses } = buildSegment("hello world", ["SECTION", "key", "value"])
    await waitForConnect()

    expect(body.textContent).toBe("")
    expect(proses.map((p) => p.textContent)).toEqual(["", "", ""])
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

    expect(body.textContent).toBe("")
    await new Promise((r) => setTimeout(r, 400))
    expect(body.textContent).toBe("just a body")
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
    it("hides the html card on connect then reveals it after the queue runs", async () => {
      const { card } = buildHtmlCard("<div class='card'>game detail</div>")
      await waitForConnect()
      // Hidden synchronously in connect() — no body target needed.
      expect(card.style.visibility).toBe("hidden")

      await new Promise((r) => setTimeout(r, 400))
      expect(card.style.visibility).toBe("")
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
      const { div, card } = buildHtmlCard("<div>about to be swapped</div>")
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
      const { div, card } = buildHtmlCard("<div>still here</div>")
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

      // Blanked while it waits in the queue — not yet signalled mid-reveal.
      expect(body.textContent).toBe("")
      expect(caught).toBeNull()

      // Let the short text type out (TICK_MS=12, CHARS_TICK=2).
      await new Promise((r) => setTimeout(r, 400))

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
})
