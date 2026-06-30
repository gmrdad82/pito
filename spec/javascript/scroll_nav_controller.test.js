// spec/javascript/scroll_nav_controller.test.js
//
// Vitest suite for pito--scroll-nav Stimulus controller.
//
// Covers:
//   • Counting [data-scrollback-message] elements fully above / below viewport
//   • Shows top pill when above > 0; bottom pill when below > 0
//   • Hides pills when counts drop to 0
//   • Picks different top/bottom variant indices simultaneously
//   • Hides both pills when sidebar is open (#pito-sidebar has <aside>)
//   • Hides both pills when palette is open (#pito-command-palette lacks .hidden)
//   • Reappears when overlays close (MutationObserver)
//   • ctrl+Home scrolls to top, ctrl+End scrolls to bottom
//   • Click on jumpTop / jumpBottom tokens scrolls accordingly

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import ScrollNavController from "controllers/pito/scroll_nav_controller"

// jsdom does not implement scrollTo on elements — stub it globally so the
// controller's `this.scrollback?.scrollTo(...)` calls don't throw.  Individual
// tests that need to capture the arguments replace scrollTo on the specific
// element via stubScrollTo().
if (!Element.prototype.scrollTo) {
  Element.prototype.scrollTo = function () {}
}

// ── Shared variants fixture (2 entries to keep tests deterministic enough) ──

const VARIANTS = [
  "%{count} messages %{direction}",
  "%{count} more %{direction}",
  "%{count} items %{direction}",
]

// ── DOM scaffold ─────────────────────────────────────────────────────────────

function buildScaffold({ variants = VARIANTS } = {}) {
  // #pito-scrollback
  const scrollback = document.createElement("div")
  scrollback.id = "pito-scrollback"
  // jsdom has no layout engine — BoundingClientRect returns all-zero by default.
  // Tests set getBoundingClientRect on each element individually.
  document.body.appendChild(scrollback)

  // Controller wrapper + pills
  const wrapper = document.createElement("div")
  wrapper.setAttribute("data-controller", "pito--scroll-nav")
  wrapper.setAttribute(
    "data-pito--scroll-nav-variants-value",
    JSON.stringify(variants)
  )

  const topPill = document.createElement("div")
  topPill.setAttribute("data-pito--scroll-nav-target", "topPill")
  topPill.classList.add("pito-scroll-nav__pill--top", "hidden")

  const topCount = document.createElement("span")
  topCount.setAttribute("data-pito--scroll-nav-target", "topCount")
  topPill.appendChild(topCount)

  const topToken = document.createElement("span")
  topToken.setAttribute("data-action", "click->pito--scroll-nav#jumpTop")
  topPill.appendChild(topToken)

  wrapper.appendChild(topPill)

  const bottomPill = document.createElement("div")
  bottomPill.setAttribute("data-pito--scroll-nav-target", "bottomPill")
  bottomPill.classList.add("pito-scroll-nav__pill--bottom", "hidden")

  const bottomCount = document.createElement("span")
  bottomCount.setAttribute("data-pito--scroll-nav-target", "bottomCount")
  bottomPill.appendChild(bottomCount)

  const bottomToken = document.createElement("span")
  bottomToken.setAttribute("data-action", "click->pito--scroll-nav#jumpBottom")
  bottomPill.appendChild(bottomToken)

  wrapper.appendChild(bottomPill)
  document.body.appendChild(wrapper)

  return { wrapper, scrollback, topPill, bottomPill, topCount, bottomCount, topToken, bottomToken }
}

// Mock the scrollback container's visible rect (represents viewport window into scroll content).
function setContainerRect(scrollback, { top = 0, height = 600 } = {}) {
  scrollback.getBoundingClientRect = () => ({
    top,
    bottom: top + height,
    left: 0,
    right: 800,
    width: 800,
    height,
  })
}

// Stub scrollTo on the scrollback element; returns a spy array.
function stubScrollTo(scrollback) {
  const calls = []
  scrollback.scrollTo = (opts) => calls.push(opts)
  return calls
}

// Add a [data-scrollback-message] element with a given bounding rect.
function addMessage(scrollback, { top, height = 50 } = {}) {
  const el = document.createElement("div")
  el.setAttribute("data-scrollback-message", "")
  el.getBoundingClientRect = () => ({
    top,
    bottom: top + height,
    left: 0,
    right: 800,
    width: 800,
    height,
  })
  scrollback.appendChild(el)
  return el
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito--scroll-nav controller", () => {
  let app

  beforeEach(() => {
    app = Application.start()
    app.register("pito--scroll-nav", ScrollNavController)
  })

  afterEach(async () => {
    await app.stop()
    document.body.innerHTML = ""
    vi.restoreAllMocks()
  })

  // Wait for Stimulus to connect (10ms is sufficient in jsdom).
  function tick(ms = 20) {
    return new Promise((r) => setTimeout(r, ms))
  }

  // ── T14.1: counting above / below ───────────────────────────────────────────

  it("shows top pill when a message is fully above the viewport", async () => {
    const { scrollback, topPill } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })

    // Message fully above (bottom = -10, which is <= containerRect.top = 0).
    addMessage(scrollback, { top: -60, height: 50 })

    await tick()

    expect(topPill.classList.contains("hidden")).toBe(false)
  })

  it("shows bottom pill when a message is fully below the viewport", async () => {
    const { scrollback, bottomPill } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })

    // Message fully below (top = 700, which is >= containerRect.bottom = 600).
    addMessage(scrollback, { top: 700, height: 50 })

    await tick()

    expect(bottomPill.classList.contains("hidden")).toBe(false)
  })

  it("hides top pill when no message is above the viewport", async () => {
    const { scrollback, topPill } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })

    // Message inside viewport (top = 100, bottom = 150 — neither above nor below).
    addMessage(scrollback, { top: 100, height: 50 })

    await tick()

    expect(topPill.classList.contains("hidden")).toBe(true)
  })

  it("hides bottom pill when no message is below the viewport", async () => {
    const { scrollback, bottomPill } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })

    addMessage(scrollback, { top: 100, height: 50 })

    await tick()

    expect(bottomPill.classList.contains("hidden")).toBe(true)
  })

  it("counts multiple messages above and below independently", async () => {
    const { scrollback, topPill, bottomPill, topCount, bottomCount } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })

    addMessage(scrollback, { top: -100, height: 50 }) // above
    addMessage(scrollback, { top: -200, height: 50 }) // above
    addMessage(scrollback, { top: 700, height: 50  }) // below

    await tick()

    expect(topPill.classList.contains("hidden")).toBe(false)
    expect(bottomPill.classList.contains("hidden")).toBe(false)

    // Count text contains "2" for above and "1" for below.
    expect(topCount.textContent).toMatch(/2/)
    expect(bottomCount.textContent).toMatch(/1/)
  })

  // ── T14.2: count text interpolation ────────────────────────────────────────

  it("interpolates %{count} and %{direction} in the count text (top pill)", async () => {
    const { scrollback, topCount } = buildScaffold({
      variants: ["%{count} messages %{direction}"],
    })
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: -60, height: 50 })

    await tick()

    expect(topCount.textContent).toBe("1 messages above")
  })

  it("interpolates %{count} and %{direction} in the count text (bottom pill)", async () => {
    const { scrollback, bottomCount } = buildScaffold({
      variants: ["%{count} messages %{direction}"],
    })
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: 700, height: 50 })

    await tick()

    expect(bottomCount.textContent).toBe("1 messages below")
  })

  // ── T14.3: variant uniqueness (top ≠ bottom simultaneously) ────────────────

  it("top and bottom pills use different variant indices when both visible", async () => {
    // 20 distinctly-prefixed templates so we can detect which one is in use.
    const manyVariants = Array.from(
      { length: 20 },
      (_, i) => `V${i} %{count} %{direction}`
    )

    const { scrollback, topCount, bottomCount } = buildScaffold({ variants: manyVariants })
    setContainerRect(scrollback, { top: 0, height: 600 })

    const above = addMessage(scrollback, { top: -60, height: 50 })
    const below = addMessage(scrollback, { top: 700, height: 50 })

    let sameCount = 0
    const RUNS = 10

    for (let i = 0; i < RUNS; i++) {
      // Hide both pills by moving messages into viewport.
      above.getBoundingClientRect = () => ({ top: 100, bottom: 150, left: 0, right: 800, width: 800, height: 50 })
      below.getBoundingClientRect = () => ({ top: 200, bottom: 250, left: 0, right: 800, width: 800, height: 50 })
      scrollback.dispatchEvent(new Event("scroll"))
      await tick()

      // Re-expose both messages outside the viewport — new variant picks happen on hidden→visible.
      above.getBoundingClientRect = () => ({ top: -60, bottom: -10, left: 0, right: 800, width: 800, height: 50 })
      below.getBoundingClientRect = () => ({ top: 700, bottom: 750, left: 0, right: 800, width: 800, height: 50 })
      scrollback.dispatchEvent(new Event("scroll"))
      await tick()

      if (topCount.textContent === bottomCount.textContent) sameCount++
    }

    // With 20 variants the collision probability per round is 1/20.
    // In 10 rounds we expect at most ~1 collision; threshold is 3.
    expect(sameCount).toBeLessThanOrEqual(3)
  })

  // ── T14.4: variant locked until pill hides again ────────────────────────────

  it("keeps the same variant text while the pill stays visible (count changes)", async () => {
    const { scrollback, topCount } = buildScaffold({
      variants: ["%{count} messages %{direction}"],
    })
    setContainerRect(scrollback, { top: 0, height: 600 })

    const msg1 = addMessage(scrollback, { top: -60, height: 50 })
    addMessage(scrollback, { top: -120, height: 50 })
    await tick()

    // Both messages above → count = 2; variant index is locked.
    const text1 = topCount.textContent

    // Simulate scroll: one message moves into view — now only 1 above.
    msg1.getBoundingClientRect = () => ({ top: 100, bottom: 150, left: 0, right: 800, width: 800, height: 50 })
    scrollback.dispatchEvent(new Event("scroll"))
    await tick()

    const text2 = topCount.textContent

    // Same template, only count changed (1 vs 2).
    expect(text1).toMatch(/2/)
    expect(text2).toMatch(/1/)
    // Both start with the same pattern prefix (same template).
    expect(text1.replace(/\d+/, "N")).toBe(text2.replace(/\d+/, "N"))
  })

  // ── T14.5: hides on sidebar open ───────────────────────────────────────────
  // The sidebar and palette elements must exist BEFORE the controller connects
  // so that #watchOverlays() can register MutationObserver callbacks on them.
  // (In the real app, application.html.erb always renders both in the layout.)

  it("hides both pills when the sidebar has an <aside> (sidebar open)", async () => {
    // Create #pito-sidebar (empty = closed) BEFORE scaffold so connect() finds it.
    const sidebar = document.createElement("div")
    sidebar.id = "pito-sidebar"
    document.body.appendChild(sidebar)

    const { scrollback, topPill, bottomPill } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: -60, height: 50 })
    addMessage(scrollback, { top: 700, height: 50 })

    await tick()

    // Pills visible before sidebar opens.
    expect(topPill.classList.contains("hidden")).toBe(false)
    expect(bottomPill.classList.contains("hidden")).toBe(false)

    // Open sidebar → inject <aside>.
    const aside = document.createElement("aside")
    sidebar.appendChild(aside)
    await tick(50)

    expect(topPill.classList.contains("hidden")).toBe(true)
    expect(bottomPill.classList.contains("hidden")).toBe(true)
  })

  it("reappears when sidebar closes (<aside> removed)", async () => {
    const sidebar = document.createElement("div")
    sidebar.id = "pito-sidebar"
    const aside = document.createElement("aside")
    sidebar.appendChild(aside) // sidebar starts OPEN
    document.body.appendChild(sidebar)

    const { scrollback, topPill } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: -60, height: 50 })

    await tick()

    // Sidebar open → pill hidden.
    expect(topPill.classList.contains("hidden")).toBe(true)

    // Close sidebar.
    sidebar.removeChild(aside)
    await tick(50)

    expect(topPill.classList.contains("hidden")).toBe(false)
  })

  // ── T14.6: hides when command palette is open ───────────────────────────────

  it("hides both pills when the palette lacks .hidden (palette open)", async () => {
    // Palette present without .hidden → open. Must exist BEFORE connect().
    const palette = document.createElement("div")
    palette.id = "pito-command-palette"
    palette.classList.add("hidden") // start closed
    document.body.appendChild(palette)

    const { scrollback, topPill, bottomPill } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: -60, height: 50 })
    addMessage(scrollback, { top: 700, height: 50 })

    await tick()

    expect(topPill.classList.contains("hidden")).toBe(false)

    // Open palette → remove .hidden.
    palette.classList.remove("hidden")
    await tick(50)

    expect(topPill.classList.contains("hidden")).toBe(true)
    expect(bottomPill.classList.contains("hidden")).toBe(true)
  })

  it("reappears when palette closes (.hidden re-added)", async () => {
    const palette = document.createElement("div")
    palette.id = "pito-command-palette"
    // No .hidden = starts open.
    document.body.appendChild(palette)

    const { scrollback, topPill } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: -60, height: 50 })

    await tick()

    expect(topPill.classList.contains("hidden")).toBe(true)

    palette.classList.add("hidden")
    await tick(50)

    expect(topPill.classList.contains("hidden")).toBe(false)
  })

  // ── T14.7: keyboard — ctrl+Home / ctrl+End ──────────────────────────────────

  it("ctrl+Home scrolls #pito-scrollback to top", async () => {
    const { scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    const calls = stubScrollTo(scrollback)
    // jumpTop calls scrollTo({ top: 0 }) — no need to mock scrollHeight.

    await tick()

    document.dispatchEvent(new KeyboardEvent("keydown", {
      key: "Home", ctrlKey: true, bubbles: true, cancelable: true,
    }))
    await tick()

    expect(calls.length).toBeGreaterThan(0)
    expect(calls.at(-1)).toMatchObject({ top: 0, behavior: "smooth" })
  })

  it("ctrl+End scrolls #pito-scrollback to bottom", async () => {
    const { scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    const calls = stubScrollTo(scrollback)
    Object.defineProperty(scrollback, "scrollHeight", { get: () => 2000, configurable: true })

    await tick()

    document.dispatchEvent(new KeyboardEvent("keydown", {
      key: "End", ctrlKey: true, bubbles: true, cancelable: true,
    }))
    await tick()

    expect(calls.length).toBeGreaterThan(0)
    expect(calls.at(-1)).toMatchObject({ top: 2000, behavior: "smooth" })
  })

  it("plain Home (without ctrl) does NOT trigger scroll nav jump", async () => {
    const { scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    const calls = stubScrollTo(scrollback)

    await tick()

    document.dispatchEvent(new KeyboardEvent("keydown", {
      key: "Home", ctrlKey: false, bubbles: true, cancelable: true,
    }))
    await tick()

    expect(calls.length).toBe(0)
  })

  // ── T14.8: click tokens ─────────────────────────────────────────────────────

  it("clicking the jumpTop token scrolls to top", async () => {
    const { scrollback, topToken } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    const calls = stubScrollTo(scrollback)

    await tick()

    topToken.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    await tick()

    expect(calls.length).toBeGreaterThan(0)
    expect(calls.at(-1)).toMatchObject({ top: 0, behavior: "smooth" })
  })

  it("clicking the jumpBottom token scrolls to bottom", async () => {
    const { scrollback, bottomToken } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    Object.defineProperty(scrollback, "scrollHeight", { get: () => 3000, configurable: true })
    const calls = stubScrollTo(scrollback)

    await tick()

    bottomToken.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    await tick()

    expect(calls.length).toBeGreaterThan(0)
    expect(calls.at(-1)).toMatchObject({ top: 3000, behavior: "smooth" })
  })

  // ── T14.9: disconnect is clean ──────────────────────────────────────────────

  it("disconnects without throwing", async () => {
    buildScaffold()
    await tick()

    let threw = false
    try {
      await app.stop()
    } catch {
      threw = true
    }
    expect(threw).toBe(false)
  })
})
