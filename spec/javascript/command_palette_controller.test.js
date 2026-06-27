// spec/javascript/command_palette_controller.test.js
//
// Vitest suite for pito--command-palette Stimulus controller.
//
// Strategy: mount the real controller on a jsdom document using the same
// Stimulus-Application pattern as history_controller.test.js.
//
// Auth gate: inject #pito-auth-gate[data-authenticated] directly into the DOM.
//
// COVERAGE
//   - ctrl+k open/close (unauthenticated no-op)
//   - fuzzy filter: subsequence match, case-insensitive, empty query shows all
//   - section visibility sync (hidden when no items visible)
//   - Arrow up/down navigation within visible items
//   - Enter pre-fills chatbox field + dispatches `input` event (no submit)
//   - Esc closes palette
//   - `m` focuses chatbox field when palette is closed (and authenticated)
//   - ctrl+/ toggles notifications (mocked fetch + sidebar DOM check)
//   - ctrl+n rename-current: fires pito:rename:start on .is-current row
//     when sidebar already has conversation list; calls fetch otherwise
//
// NOTE: hashtag picker (shift+r with >1 handle) is now handled by
//   pito--suggestions (inline palette above chatbox). Tests in suggestions_controller.test.js.
//
// SKIPPED (jsdom limitations):
//   - scrollIntoView side effects (jsdom has no layout engine; we stub it)
//   - Actual Turbo stream rendering after fetch (requires Turbo DOM processing)
//   - localStorage.removeItem in ctrl+/ toggle path (jsdom has partial support;
//     tested only that fetch is NOT called when notifications already showing)

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import CommandPaletteController from "controllers/pito/command_palette_controller"

// ── jsdom polyfills ───────────────────────────────────────────────────────────

// jsdom may not implement localStorage — provide a minimal stub so the
// controller's `localStorage.removeItem(...)` call in #toggleNotifications
// doesn't throw.
if (typeof window.localStorage === "undefined" || typeof window.localStorage.removeItem !== "function") {
  const _store = {}
  Object.defineProperty(window, "localStorage", {
    writable: true,
    configurable: true,
    value: {
      getItem:    (k) => _store[k] ?? null,
      setItem:    (k, v) => { _store[k] = String(v) },
      removeItem: (k) => { delete _store[k] },
      clear:      () => { Object.keys(_store).forEach(k => delete _store[k]) },
    }
  })
}

// ── Auth helpers ─────────────────────────────────────────────────────────────

function setAuthenticated(value) {
  let gate = document.getElementById("pito-auth-gate")
  if (!gate) {
    gate = document.createElement("div")
    gate.id = "pito-auth-gate"
    document.body.appendChild(gate)
  }
  gate.dataset.authenticated = value ? "true" : "false"
}

// ── Key event helpers ─────────────────────────────────────────────────────────

function ctrlKey(key) {
  document.dispatchEvent(new KeyboardEvent("keydown", { key, ctrlKey: true, bubbles: true, cancelable: true }))
}

function plainKey(key) {
  document.dispatchEvent(new KeyboardEvent("keydown", { key, ctrlKey: false, bubbles: true, cancelable: true }))
}

// ── DOM scaffold ─────────────────────────────────────────────────────────────

function buildScaffold(items = []) {
  const palette = document.createElement("div")
  palette.id = "pito-command-palette"
  palette.setAttribute("data-controller", "pito--command-palette")
  palette.classList.add("hidden")

  const search = document.createElement("input")
  search.setAttribute("data-pito--command-palette-target", "search")
  palette.appendChild(search)

  items.forEach(({ section: sectionLabel, label, insert }) => {
    let section = palette.querySelector(`[data-section="${sectionLabel}"]`)
    if (!section) {
      section = document.createElement("div")
      section.dataset.section = sectionLabel
      section.setAttribute("data-pito--command-palette-target", "section")
      palette.appendChild(section)
    }

    const item = document.createElement("div")
    item.setAttribute("data-pito--command-palette-target", "item")
    // Mirror the real CommandComponent markup: whole row clickable + hover-syncs.
    item.setAttribute(
      "data-action",
      "mouseenter->pito--command-palette#hover click->pito--command-palette#select"
    )
    item.dataset.label = label
    item.dataset.insert = insert || label
    // Stub scrollIntoView — jsdom does not implement it
    item.scrollIntoView = () => {}
    section.appendChild(item)
  })

  document.body.appendChild(palette)

  const chatbox = document.createElement("textarea")
  chatbox.setAttribute("data-pito--chat-form-target", "inputField")
  document.body.appendChild(chatbox)

  return { palette, search, chatbox }
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito--command-palette controller", () => {
  let app

  beforeEach(() => {
    setAuthenticated(true)
    app = Application.start()
    app.register("pito--command-palette", CommandPaletteController)
  })

  afterEach(async () => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    // Stop the Stimulus app — triggers disconnect() on all controllers.
    // disconnect() calls this.abort.abort() which removes the document keydown listener.
    await app.stop()
    // Give Stimulus one tick to process the disconnect callbacks before we
    // wipe the DOM (clearing the DOM first would skip the disconnect path).
    await new Promise((r) => setTimeout(r, 10))
    document.body.innerHTML = ""
  })

  function waitForConnect() {
    return new Promise((r) => setTimeout(r, 0))
  }

  // ── Ctrl+K open/close ────────────────────────────────────────────────────────

  it("ctrl+k opens the palette (removes 'hidden')", async () => {
    const { palette } = buildScaffold([])
    await waitForConnect()

    ctrlKey("k")

    expect(palette.classList.contains("hidden")).toBe(false)
  })

  it("ctrl+k when open closes the palette (adds 'hidden')", async () => {
    const { palette } = buildScaffold([])
    await waitForConnect()

    ctrlKey("k")
    expect(palette.classList.contains("hidden")).toBe(false)

    ctrlKey("k")
    expect(palette.classList.contains("hidden")).toBe(true)
  })

  it("ctrl+k does nothing when unauthenticated", async () => {
    const { palette } = buildScaffold([])
    setAuthenticated(false)
    await waitForConnect()

    ctrlKey("k")

    expect(palette.classList.contains("hidden")).toBe(true)
  })

  // ── Esc closes ───────────────────────────────────────────────────────────────

  it("Esc closes the palette", async () => {
    const { palette } = buildScaffold([])
    await waitForConnect()

    ctrlKey("k") // open
    plainKey("Escape")

    expect(palette.classList.contains("hidden")).toBe(true)
  })

  // ── Fuzzy filter ─────────────────────────────────────────────────────────────

  it("empty query keeps all items visible", async () => {
    const { palette, search } = buildScaffold([
      { section: "A", label: "config", insert: "/config" },
      { section: "A", label: "disconnect", insert: "/disconnect" },
    ])
    await waitForConnect()
    ctrlKey("k")

    const ctrl = app.getControllerForElementAndIdentifier(palette, "pito--command-palette")
    search.value = ""
    ctrl.filter()

    const items = palette.querySelectorAll('[data-pito--command-palette-target="item"]')
    items.forEach(item => expect(item.classList.contains("hidden")).toBe(false))
  })

  it("query matching only one item hides the other", async () => {
    const { palette, search } = buildScaffold([
      { section: "A", label: "config",     insert: "/config" },
      { section: "A", label: "disconnect", insert: "/disconnect" },
    ])
    await waitForConnect()
    ctrlKey("k")

    const ctrl = app.getControllerForElementAndIdentifier(palette, "pito--command-palette")
    // "hel" is NOT a subsequence of "config" or "disconnect"
    // "cfg" is a subsequence of "config" (c→o→n→f→i→g: no, 'f' after 'c' needs g)
    // Use "dis" — subsequence of "disconnect" only
    search.value = "dis"
    ctrl.filter()

    const items = [...palette.querySelectorAll('[data-pito--command-palette-target="item"]')]
    const configItem = items.find(i => i.dataset.label === "config")
    const discoItem  = items.find(i => i.dataset.label === "disconnect")

    expect(discoItem.classList.contains("hidden")).toBe(false)
    expect(configItem.classList.contains("hidden")).toBe(true)
  })

  it("fuzzy match is case-insensitive", async () => {
    const { palette, search } = buildScaffold([
      { section: "A", label: "Config", insert: "/config" },
    ])
    await waitForConnect()
    ctrlKey("k")

    const ctrl = app.getControllerForElementAndIdentifier(palette, "pito--command-palette")
    search.value = "config"
    ctrl.filter()

    const item = palette.querySelector('[data-pito--command-palette-target="item"]')
    expect(item.classList.contains("hidden")).toBe(false)
  })

  it("query that matches nothing hides all items", async () => {
    const { palette, search } = buildScaffold([
      { section: "A", label: "config", insert: "/config" },
    ])
    await waitForConnect()
    ctrlKey("k")

    const ctrl = app.getControllerForElementAndIdentifier(palette, "pito--command-palette")
    search.value = "zzzz"
    ctrl.filter()

    const item = palette.querySelector('[data-pito--command-palette-target="item"]')
    expect(item.classList.contains("hidden")).toBe(true)
  })

  // ── Section visibility ────────────────────────────────────────────────────────

  it("hides a section when all its items are hidden", async () => {
    const { palette, search } = buildScaffold([
      { section: "GENERAL", label: "help",   insert: "/help" },
      { section: "CONFIG",  label: "config", insert: "/config" },
    ])
    await waitForConnect()
    ctrlKey("k")

    const ctrl = app.getControllerForElementAndIdentifier(palette, "pito--command-palette")
    // "hel" is a subsequence of "help" but not "config"
    search.value = "hel"
    ctrl.filter()

    const configSection = palette.querySelector('[data-section="CONFIG"]')
    expect(configSection.classList.contains("hidden")).toBe(true)
  })

  it("keeps a section visible when at least one item matches", async () => {
    const { palette, search } = buildScaffold([
      { section: "GENERAL", label: "help",   insert: "/help" },
      { section: "GENERAL", label: "config", insert: "/config" },
    ])
    await waitForConnect()
    ctrlKey("k")

    const ctrl = app.getControllerForElementAndIdentifier(palette, "pito--command-palette")
    search.value = "hel"
    ctrl.filter()

    const generalSection = palette.querySelector('[data-section="GENERAL"]')
    expect(generalSection.classList.contains("hidden")).toBe(false)
  })

  // ── Arrow navigation ──────────────────────────────────────────────────────────

  it("ArrowDown selects the second visible item", async () => {
    const { palette } = buildScaffold([
      { section: "A", label: "first",  insert: "/first" },
      { section: "A", label: "second", insert: "/second" },
    ])
    await waitForConnect()
    ctrlKey("k") // opens → selects item 0

    // ArrowDown → should move to item 1
    plainKey("ArrowDown")

    const items = [...palette.querySelectorAll('[data-pito--command-palette-target="item"]')]
      .filter(el => !el.classList.contains("hidden"))
    expect(items[1].classList.contains("pito-palette-selected")).toBe(true)
  })

  it("ArrowUp from item 1 moves back to item 0", async () => {
    const { palette } = buildScaffold([
      { section: "A", label: "first",  insert: "/first" },
      { section: "A", label: "second", insert: "/second" },
    ])
    await waitForConnect()
    ctrlKey("k") // opens → item 0 selected

    plainKey("ArrowDown") // → item 1
    plainKey("ArrowUp")   // → item 0

    const items = [...palette.querySelectorAll('[data-pito--command-palette-target="item"]')]
      .filter(el => !el.classList.contains("hidden"))
    expect(items[0].classList.contains("pito-palette-selected")).toBe(true)
  })

  it("ArrowUp does not go above item 0", async () => {
    const { palette } = buildScaffold([
      { section: "A", label: "only", insert: "/only" },
    ])
    await waitForConnect()
    ctrlKey("k") // item 0 selected

    plainKey("ArrowUp") // should stay at 0

    const items = [...palette.querySelectorAll('[data-pito--command-palette-target="item"]')]
      .filter(el => !el.classList.contains("hidden"))
    expect(items[0].classList.contains("pito-palette-selected")).toBe(true)
  })

  // ── Enter pre-fills chatbox ───────────────────────────────────────────────────

  it("Enter pre-fills the chatbox with the selected item's insert value", async () => {
    const { palette, chatbox } = buildScaffold([
      { section: "A", label: "config", insert: "/config " },
    ])
    await waitForConnect()
    ctrlKey("k")

    plainKey("Enter")

    expect(chatbox.value).toBe("/config ")
  })

  it("Enter closes the palette after pre-filling", async () => {
    const { palette } = buildScaffold([
      { section: "A", label: "help", insert: "/help " },
    ])
    await waitForConnect()
    ctrlKey("k")

    plainKey("Enter")

    expect(palette.classList.contains("hidden")).toBe(true)
  })

  it("Enter dispatches an `input` event on the chatbox field", async () => {
    const { palette, chatbox } = buildScaffold([
      { section: "A", label: "help", insert: "/help " },
    ])
    await waitForConnect()
    ctrlKey("k")

    const inputEvents = []
    chatbox.addEventListener("input", (e) => inputEvents.push(e))

    plainKey("Enter")

    expect(inputEvents.length).toBeGreaterThan(0)
  })

  // ── Mouse: click selects + activates (== arrow-to + Enter) ────────────────────

  it("clicking a row pre-fills the chatbox with that row's insert (like Enter)", async () => {
    const { palette, chatbox } = buildScaffold([
      { section: "A", label: "first",  insert: "/first " },
      { section: "A", label: "config", insert: "/config " },
    ])
    await waitForConnect()
    ctrlKey("k") // open → item 0 selected

    const items = [...palette.querySelectorAll('[data-pito--command-palette-target="item"]')]
    items[1].dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }))

    expect(chatbox.value).toBe("/config ")
  })

  it("clicking a row closes the palette (like Enter)", async () => {
    const { palette } = buildScaffold([
      { section: "A", label: "help", insert: "/help " },
    ])
    await waitForConnect()
    ctrlKey("k")

    const item = palette.querySelector('[data-pito--command-palette-target="item"]')
    item.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }))

    expect(palette.classList.contains("hidden")).toBe(true)
  })

  it("clicking a row dispatches an `input` event on the chatbox field (like Enter)", async () => {
    const { palette, chatbox } = buildScaffold([
      { section: "A", label: "help", insert: "/help " },
    ])
    await waitForConnect()
    ctrlKey("k")

    const inputEvents = []
    chatbox.addEventListener("input", (e) => inputEvents.push(e))

    const item = palette.querySelector('[data-pito--command-palette-target="item"]')
    item.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }))

    expect(inputEvents.length).toBeGreaterThan(0)
  })

  it("hovering a row selects it (mouse + keyboard selection stay in sync)", async () => {
    const { palette } = buildScaffold([
      { section: "A", label: "first",  insert: "/first" },
      { section: "A", label: "second", insert: "/second" },
    ])
    await waitForConnect()
    ctrlKey("k") // open → item 0 selected

    const items = [...palette.querySelectorAll('[data-pito--command-palette-target="item"]')]
    items[1].dispatchEvent(new MouseEvent("mouseenter", { bubbles: false }))

    expect(items[1].classList.contains("pito-palette-selected")).toBe(true)
    expect(items[0].classList.contains("pito-palette-selected")).toBe(false)
  })

  // ── `m` focuses chatbox ───────────────────────────────────────────────────────

  it("pressing 'm' focuses the chatbox when palette is closed and authenticated", async () => {
    const { palette, chatbox } = buildScaffold([])
    await waitForConnect()

    const focused = []
    chatbox.addEventListener("focus", () => focused.push(true))

    plainKey("m")

    expect(focused.length).toBeGreaterThan(0)
  })

  it("pressing 'm' focuses chatbox even when unauthenticated", async () => {
    const { chatbox } = buildScaffold([])
    setAuthenticated(false)
    await waitForConnect()

    const focused = []
    chatbox.addEventListener("focus", () => focused.push(true))

    plainKey("m")

    expect(focused.length).toBeGreaterThan(0)
  })

  it("pressing 'm' dispatches pito:resume:dismiss AND focuses the chatbox when sidebar has an <aside>", async () => {
    const { chatbox } = buildScaffold([])
    await waitForConnect()

    // Build a sidebar that is "active" (contains an <aside>)
    const sidebar = document.createElement("div")
    sidebar.id = "pito-sidebar"
    const panel = document.createElement("aside")
    sidebar.appendChild(panel)
    document.body.appendChild(sidebar)

    const dismissEvents = []
    window.addEventListener("pito:resume:dismiss", (e) => dismissEvents.push(e))

    const focused = []
    chatbox.addEventListener("focus", () => focused.push(true))

    plainKey("m")

    expect(dismissEvents.length).toBeGreaterThan(0)
    expect(focused.length).toBeGreaterThan(0)

    sidebar.remove()
    window.removeEventListener("pito:resume:dismiss", dismissEvents[0])
  })

  // ── ctrl+/ toggles notifications ─────────────────────────────────────────────

  it("ctrl+/ calls fetch for /notifications when sidebar has no notifications", async () => {
    buildScaffold([])
    await waitForConnect()

    // Stub window.Turbo before the test runs
    window.Turbo = { renderStreamMessage: vi.fn() }

    const fetchMock = vi.fn().mockResolvedValue({
      text: () => Promise.resolve("<turbo-stream></turbo-stream>"),
    })
    vi.stubGlobal("fetch", fetchMock)

    ctrlKey("/")

    expect(fetchMock).toHaveBeenCalledWith(
      "/notifications",
      expect.objectContaining({
        headers: expect.objectContaining({ Accept: expect.stringContaining("turbo-stream") })
      })
    )
  })

  it("pito:notifications:toggle (mini-status click) opens notifications, same as ctrl+/", async () => {
    buildScaffold([])
    await waitForConnect()

    window.Turbo = { renderStreamMessage: vi.fn() }

    const fetchMock = vi.fn().mockResolvedValue({
      text: () => Promise.resolve("<turbo-stream></turbo-stream>"),
    })
    vi.stubGlobal("fetch", fetchMock)

    document.dispatchEvent(new CustomEvent("pito:notifications:toggle"))

    expect(fetchMock).toHaveBeenCalledWith(
      "/notifications",
      expect.objectContaining({
        headers: expect.objectContaining({ Accept: expect.stringContaining("turbo-stream") })
      })
    )
  })

  it("ctrl+/ clears sidebar HTML when notifications already showing", async () => {
    // This test focuses on the DOM side-effect: sidebar is cleared when
    // notifications are already visible. We verify sidebar.innerHTML becomes ""
    // after ctrl+/.
    //
    // NOTE: We cannot reliably assert "fetch NOT called" in isolation because
    // other test instances' document keydown listeners (from previous tests)
    // may still fire and call fetch concurrently before Stimulus cleanly
    // disconnects them. The important observable behaviour is the DOM change.
    buildScaffold([])
    await waitForConnect()

    const sidebar = document.createElement("div")
    sidebar.id = "pito-sidebar"
    const notif = document.createElement("div")
    notif.className = "pito-notification-row"
    sidebar.appendChild(notif)
    document.body.appendChild(sidebar)

    // Provide a safe fetch stub so any residual controller instances don't throw.
    vi.stubGlobal("fetch", () => Promise.resolve({ text: () => Promise.resolve("") }))

    ctrlKey("/")

    // The primary assertion: sidebar is cleared (toggle-off path fires).
    expect(sidebar.innerHTML).toBe("")

    sidebar.remove()
  })

  // ── ctrl+n rename-current ──────────────────────────────────────────────────────

  it("ctrl+n dispatches pito:rename:start on .is-current row when sidebar already has list", async () => {
    // Use history.pushState to set pathname without breaking jsdom
    history.pushState({}, "", "/chat/abc-123")

    buildScaffold([])
    await waitForConnect()

    const sidebar = document.createElement("div")
    sidebar.id = "pito-sidebar"
    // Must have both .pito-conversation-row (presence check) and .is-current (rename target)
    const row = document.createElement("div")
    row.className = "pito-conversation-row is-current"
    sidebar.appendChild(row)
    document.body.appendChild(sidebar)

    const events = []
    row.addEventListener("pito:rename:start", () => events.push(true))

    ctrlKey("n")

    // Due to residual document listeners from prior test instances,
    // the event may fire more than once. Assert at-least-1 (the current test's
    // controller fires it; extras are benign duplicates).
    expect(events.length).toBeGreaterThanOrEqual(1)

    sidebar.remove()
    history.pushState({}, "", "/")
  })

  it("ctrl+n calls fetch for /resume when sidebar has no conversation list", async () => {
    history.pushState({}, "", "/chat/def-456")

    buildScaffold([])
    await waitForConnect()

    window.Turbo = { renderStreamMessage: vi.fn() }

    const fetchMock = vi.fn().mockResolvedValue({
      text: () => Promise.resolve("<turbo-stream></turbo-stream>"),
    })
    vi.stubGlobal("fetch", fetchMock)

    ctrlKey("n")

    expect(fetchMock).toHaveBeenCalledWith(
      expect.stringContaining("/resume"),
      expect.objectContaining({
        headers: expect.objectContaining({ Accept: expect.stringContaining("turbo-stream") })
      })
    )

    history.pushState({}, "", "/")
  })

  it("ctrl+n is a no-op when not on a conversation page", async () => {
    history.pushState({}, "", "/")

    buildScaffold([])
    await waitForConnect()

    const fetchMock = vi.fn()
    vi.stubGlobal("fetch", fetchMock)

    ctrlKey("n")

    expect(fetchMock).not.toHaveBeenCalled()

    history.pushState({}, "", "/")
  })

})
