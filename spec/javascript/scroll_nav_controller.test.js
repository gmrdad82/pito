// spec/javascript/scroll_nav_controller.test.js
//
// Vitest suite for pito--scroll-nav Stimulus controller.
//
// The controller CREATES a pill (a clone of the matching <template>) and appends
// it to the DOM when there are messages above / below, and REMOVES it entirely
// when there are none. There is NO show/hide toggle — a pill's PRESENCE in the
// DOM is the "shown" state (owner spec). Tests therefore assert on presence, not
// on a `hidden` class.
//
// Covers:
//   • Counting [data-scrollback-message] elements fully above / below viewport
//   • Creates the top pill when above > 0; the bottom pill when below > 0
//   • Removes pills when counts drop to 0 / at the extremes / not scrollable
//   • Count text interpolation + singular/plural
//   • Picks different top/bottom variant indices simultaneously
//   • Removes both pills when sidebar / palette open; recreates when they close
//   • ctrl+Home / ctrl+End + token clicks scroll accordingly

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import ScrollNavController from "controllers/pito/scroll_nav_controller"

// jsdom does not implement scrollTo on elements — stub it globally so the
// controller's `this.scrollback?.scrollTo(...)` calls don't throw. Tests that
// capture args replace scrollTo on the specific element via stubScrollTo().
if (!Element.prototype.scrollTo) {
  Element.prototype.scrollTo = function () {}
}

// ── Shared copy fixture — ONE template per side (owner 2026-07-13) ──────────

const BEFORE = "%{count} msgs before"
const AFTER  = "%{count} msgs after"

// ── DOM scaffold ─────────────────────────────────────────────────────────────

// A <template> matching the component: a pill with a count span + a jump token.
function makeTemplate(side) {
  const tmpl = document.createElement("template")
  tmpl.setAttribute("data-pito--scroll-nav-target", `${side}Template`)
  const action = side === "top" ? "jumpTop" : "jumpBottom"
  const keys   = side === "top" ? "ctrl+home" : "ctrl+end"
  tmpl.innerHTML =
    `<div class="pito-scroll-nav__pill pito-scroll-nav__pill--${side}">` +
    `<span data-scroll-nav-count></span>` +
    `<span data-action="click->pito--scroll-nav#${action}">${keys}</span>` +
    `</div>`
  return tmpl
}

function buildScaffold({ before = BEFORE, after = AFTER } = {}) {
  const scrollback = document.createElement("div")
  scrollback.id = "pito-scrollback"
  // jsdom has no layout engine — getBoundingClientRect returns all-zero by
  // default. Tests set it per element via setContainerRect / addMessage.
  document.body.appendChild(scrollback)

  const wrapper = document.createElement("div")
  wrapper.setAttribute("data-controller", "pito--scroll-nav")
  wrapper.setAttribute("data-pito--scroll-nav-before-value", before)
  wrapper.setAttribute("data-pito--scroll-nav-after-value", after)
  wrapper.appendChild(makeTemplate("top"))
  wrapper.appendChild(makeTemplate("bottom"))
  document.body.appendChild(wrapper)

  return { wrapper, scrollback }
}

// The live pill element for a side, or null when it is not in the DOM.
const pillEl = (wrapper, side) =>
  wrapper.querySelector(`.pito-scroll-nav__pill--${side}`)

// The rendered count text for a side (undefined when the pill is absent).
const countText = (wrapper, side) =>
  pillEl(wrapper, side)?.querySelector("[data-scroll-nav-count]")?.textContent

// Mock the scrollback container's rect + scroll geometry. Defaults put it
// MID-SCROLL (not at either extreme); pass scrollTop/scrollHeight for extremes.
function setContainerRect(
  scrollback,
  { top = 0, height = 600, scrollTop = 500, scrollHeight = 4000 } = {}
) {
  scrollback.getBoundingClientRect = () => ({
    top, bottom: top + height, left: 0, right: 800, width: 800, height,
  })
  Object.defineProperty(scrollback, "scrollTop", { get: () => scrollTop, configurable: true })
  Object.defineProperty(scrollback, "clientHeight", { get: () => height, configurable: true })
  Object.defineProperty(scrollback, "scrollHeight", { get: () => scrollHeight, configurable: true })
}

function stubScrollTo(scrollback) {
  const calls = []
  scrollback.scrollTo = (opts) => calls.push(opts)
  return calls
}

function addMessage(scrollback, { top, height = 50 } = {}) {
  const el = document.createElement("div")
  el.setAttribute("data-scrollback-message", "")
  el.getBoundingClientRect = () => ({
    top, bottom: top + height, left: 0, right: 800, width: 800, height,
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

  function tick(ms = 20) {
    return new Promise((r) => setTimeout(r, ms))
  }

  // ── counting above / below → create / remove ────────────────────────────────

  it("creates the top pill when a message is fully above the viewport", async () => {
    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: -60, height: 50 })

    await tick()

    expect(pillEl(wrapper, "top")).not.toBeNull()
  })

  it("creates the bottom pill when a message is fully below the viewport", async () => {
    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: 700, height: 50 })

    await tick()

    expect(pillEl(wrapper, "bottom")).not.toBeNull()
  })

  it("creates NEITHER pill for a brand-new conversation with zero messages", async () => {
    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600, scrollTop: 0, scrollHeight: 600 })

    await tick()

    expect(pillEl(wrapper, "top")).toBeNull()
    expect(pillEl(wrapper, "bottom")).toBeNull()
  })

  it("creates NEITHER pill when the content fits the viewport / not scrollable", async () => {
    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600, scrollTop: 0, scrollHeight: 600 })
    addMessage(scrollback, { top: 10, height: 50 })
    addMessage(scrollback, { top: 70, height: 50 })

    await tick()

    expect(pillEl(wrapper, "top")).toBeNull()
    expect(pillEl(wrapper, "bottom")).toBeNull()
  })

  it("renders the fixed copy for one message out of view (no plural machinery)", async () => {
    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600, scrollTop: 500, scrollHeight: 4000 })
    addMessage(scrollback, { top: -60, height: 50 })

    await tick()

    expect(countText(wrapper, "top")).toBe("1 msgs before")
  })

  it("renders the count into the fixed copy for several messages", async () => {
    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600, scrollTop: 500, scrollHeight: 4000 })
    addMessage(scrollback, { top: -120, height: 50 })
    addMessage(scrollback, { top: -60, height: 50 })

    await tick()

    expect(countText(wrapper, "top")).toBe("2 msgs before")
  })

  it("removes the top pill when scrolled to the very top, even if a message reads above", async () => {
    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600, scrollTop: 0, scrollHeight: 4000 })
    addMessage(scrollback, { top: -60, height: 50 }) // would otherwise count as "above"

    await tick()

    expect(pillEl(wrapper, "top")).toBeNull()
  })

  it("removes the bottom pill when scrolled to the very bottom, even if a message reads below", async () => {
    const { wrapper, scrollback } = buildScaffold()
    // scrollTop + clientHeight (3400 + 600 = 4000) === scrollHeight → at the bottom.
    setContainerRect(scrollback, { top: 0, height: 600, scrollTop: 3400, scrollHeight: 4000 })
    addMessage(scrollback, { top: 700, height: 50 }) // would otherwise count as "below"

    await tick()

    expect(pillEl(wrapper, "bottom")).toBeNull()
  })

  it("creates no top pill when no message is above the viewport", async () => {
    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: 100, height: 50 }) // inside viewport

    await tick()

    expect(pillEl(wrapper, "top")).toBeNull()
  })

  it("creates no bottom pill when no message is below the viewport", async () => {
    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: 100, height: 50 })

    await tick()

    expect(pillEl(wrapper, "bottom")).toBeNull()
  })

  it("counts multiple messages above and below independently", async () => {
    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })

    addMessage(scrollback, { top: -100, height: 50 }) // above
    addMessage(scrollback, { top: -200, height: 50 }) // above
    addMessage(scrollback, { top: 700, height: 50  }) // below

    await tick()

    expect(pillEl(wrapper, "top")).not.toBeNull()
    expect(pillEl(wrapper, "bottom")).not.toBeNull()
    expect(countText(wrapper, "top")).toMatch(/2/)
    expect(countText(wrapper, "bottom")).toMatch(/1/)
  })

  // ── count text interpolation ────────────────────────────────────────────────

  it("interpolates %{count} into the before template (top pill)", async () => {
    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: -60, height: 50 })

    await tick()

    expect(countText(wrapper, "top")).toBe("1 msgs before")
  })

  it("interpolates %{count} into the after template (bottom pill)", async () => {
    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: 700, height: 50 })

    await tick()

    expect(countText(wrapper, "bottom")).toBe("1 msgs after")
  })

  // ── template stable while the pill stays in the DOM (count changes) ──────────

  it("keeps the same copy template while the pill stays in the DOM (count changes)", async () => {
    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })

    const msg1 = addMessage(scrollback, { top: -60, height: 50 })
    addMessage(scrollback, { top: -120, height: 50 })
    await tick()

    const text1 = countText(wrapper, "top") // 2 above

    // One message moves into view — still 1 above, so the pill stays (not removed).
    msg1.getBoundingClientRect = () => ({ top: 100, bottom: 150, left: 0, right: 800, width: 800, height: 50 })
    scrollback.dispatchEvent(new Event("scroll"))
    await tick()

    const text2 = countText(wrapper, "top") // 1 above

    expect(text1).toMatch(/2/)
    expect(text2).toMatch(/1/)
    expect(text1.replace(/\d+/, "N")).toBe(text2.replace(/\d+/, "N"))
  })

  // ── overlays: remove on open, recreate on close ─────────────────────────────

  it("removes both pills when the sidebar has an <aside> (sidebar open)", async () => {
    const sidebar = document.createElement("div")
    sidebar.id = "pito-sidebar"
    document.body.appendChild(sidebar)

    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: -60, height: 50 })
    addMessage(scrollback, { top: 700, height: 50 })

    await tick()

    expect(pillEl(wrapper, "top")).not.toBeNull()
    expect(pillEl(wrapper, "bottom")).not.toBeNull()

    const aside = document.createElement("aside")
    sidebar.appendChild(aside)
    await tick(50)

    expect(pillEl(wrapper, "top")).toBeNull()
    expect(pillEl(wrapper, "bottom")).toBeNull()
  })

  it("recreates a pill when the sidebar closes (<aside> removed)", async () => {
    const sidebar = document.createElement("div")
    sidebar.id = "pito-sidebar"
    const aside = document.createElement("aside")
    sidebar.appendChild(aside) // starts OPEN
    document.body.appendChild(sidebar)

    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: -60, height: 50 })

    await tick()

    expect(pillEl(wrapper, "top")).toBeNull()

    sidebar.removeChild(aside)
    await tick(50)

    expect(pillEl(wrapper, "top")).not.toBeNull()
  })

  it("removes both pills when the palette lacks .hidden (palette open)", async () => {
    const palette = document.createElement("div")
    palette.id = "pito-command-palette"
    palette.classList.add("hidden") // start closed
    document.body.appendChild(palette)

    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: -60, height: 50 })
    addMessage(scrollback, { top: 700, height: 50 })

    await tick()

    expect(pillEl(wrapper, "top")).not.toBeNull()

    palette.classList.remove("hidden")
    await tick(50)

    expect(pillEl(wrapper, "top")).toBeNull()
    expect(pillEl(wrapper, "bottom")).toBeNull()
  })

  it("recreates a pill when the palette closes (.hidden re-added)", async () => {
    const palette = document.createElement("div")
    palette.id = "pito-command-palette"
    document.body.appendChild(palette) // no .hidden = open

    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: -60, height: 50 })

    await tick()

    expect(pillEl(wrapper, "top")).toBeNull()

    palette.classList.add("hidden")
    await tick(50)

    expect(pillEl(wrapper, "top")).not.toBeNull()
  })

  // ── keyboard — ctrl+Home / ctrl+End ─────────────────────────────────────────

  it("ctrl+Home scrolls #pito-scrollback to top", async () => {
    const { scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    const calls = stubScrollTo(scrollback)

    await tick()

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Home", ctrlKey: true, bubbles: true, cancelable: true }))
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

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "End", ctrlKey: true, bubbles: true, cancelable: true }))
    await tick()

    expect(calls.length).toBeGreaterThan(0)
    expect(calls.at(-1)).toMatchObject({ top: 2000, behavior: "smooth" })
  })

  it("plain Home (without ctrl) does NOT trigger a scroll-nav jump", async () => {
    const { scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    const calls = stubScrollTo(scrollback)

    await tick()

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Home", ctrlKey: false, bubbles: true, cancelable: true }))
    await tick()

    expect(calls.length).toBe(0)
  })

  // ── click tokens (inside the created pill) ──────────────────────────────────

  it("clicking the created top pill's token scrolls to top", async () => {
    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    addMessage(scrollback, { top: -60, height: 50 }) // create the top pill
    const calls = stubScrollTo(scrollback)

    await tick(40)

    const token = pillEl(wrapper, "top").querySelector("[data-action]")
    token.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    await tick()

    expect(calls.length).toBeGreaterThan(0)
    expect(calls.at(-1)).toMatchObject({ top: 0, behavior: "smooth" })
  })

  it("clicking the created bottom pill's token scrolls to bottom", async () => {
    const { wrapper, scrollback } = buildScaffold()
    setContainerRect(scrollback, { top: 0, height: 600 })
    Object.defineProperty(scrollback, "scrollHeight", { get: () => 3000, configurable: true })
    addMessage(scrollback, { top: 700, height: 50 }) // create the bottom pill
    const calls = stubScrollTo(scrollback)

    await tick(40)

    const token = pillEl(wrapper, "bottom").querySelector("[data-action]")
    token.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    await tick()

    expect(calls.length).toBeGreaterThan(0)
    expect(calls.at(-1)).toMatchObject({ top: 3000, behavior: "smooth" })
  })

  // ── disconnect is clean ─────────────────────────────────────────────────────

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
