// spec/javascript/theme_nav_controller.test.js
//
// Tests for pito--theme-nav Stimulus controller (theme_nav_controller.js).
//
// Strategy: mount the real controller on a jsdom document with a minimal
// #pito-sidebar scaffold containing a few .pito-theme-row elements plus a
// #pito-settings element (for currentTheme()).  Assert preview (data-theme),
// PATCH on Enter, and revert-on-disconnect semantics.
//
// jsdom limitations:
//   - scrollIntoView is a no-op stub (no layout engine).
//   - fetch is mocked globally so PATCH assertions don't make real HTTP calls.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import ThemeNavController from "controllers/pito/theme_nav_controller"

// ── stubs ─────────────────────────────────────────────────────────────────────

Element.prototype.scrollIntoView = () => {}

// matchMedia is not implemented in jsdom.
if (typeof window !== "undefined" && !window.matchMedia) {
  window.matchMedia = () => ({
    matches: false,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  })
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Build a minimal DOM scaffold:
 *   #pito-settings[data-theme]  — read by currentTheme()
 *   #pito-sidebar               — wrapper (cleared by #apply mirror)
 *     div[data-controller]      — the controller element
 *       .pito-theme-row × N     — theme rows
 *
 * Returns { sidebar, controller, rows, settings }.
 */
function buildScaffold({ themes = [], currentThemeName = "tokyo-night" } = {}) {
  // #pito-settings (read by currentTheme())
  const settings = document.createElement("div")
  settings.id = "pito-settings"
  settings.dataset.theme = currentThemeName
  document.body.appendChild(settings)

  // CSRF meta tag
  const csrf = document.createElement("meta")
  csrf.name = "csrf-token"
  csrf.content = "test-csrf-token"
  document.head.appendChild(csrf)

  // #pito-sidebar wrapper
  const sidebar = document.createElement("div")
  sidebar.id = "pito-sidebar"
  document.body.appendChild(sidebar)

  // Controller element (mirrors the themes component's wrapper div)
  const controller = document.createElement("div")
  controller.setAttribute("data-controller", "pito--theme-nav")
  sidebar.appendChild(controller)

  // Theme rows
  const rows = themes.map(({ slug, current = false }) => {
    const row = document.createElement("div")
    row.className = "pito-theme-row" + (current ? " is-current" : "")
    row.dataset.themeName = slug
    controller.appendChild(row)
    return row
  })

  return { sidebar, controller, rows, settings }
}

function fireKey(key) {
  document.dispatchEvent(
    new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true })
  )
}

function tick() {
  return new Promise((r) => setTimeout(r, 0))
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito--theme-nav controller", () => {
  let app

  beforeEach(() => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true })
    app = Application.start()
    app.register("pito--theme-nav", ThemeNavController)
    // Reset data-theme on <html> before each test.
    document.documentElement.dataset.theme = ""
  })

  afterEach(async () => {
    vi.clearAllMocks()
    vi.restoreAllMocks()
    if (app) await app.stop()
    document.body.innerHTML = ""
    document.head.innerHTML = ""
    delete document.documentElement.dataset.theme
  })

  // ── connect / initial highlight ───────────────────────────────────────────

  it("highlights the is-current row on connect", async () => {
    const { rows } = buildScaffold({
      themes: [
        { slug: "tokyo-night", current: true },
        { slug: "dracula", current: false },
      ],
      currentThemeName: "tokyo-night",
    })
    await tick()

    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(true)
    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(false)
  })

  it("falls back to the first row when no row is is-current", async () => {
    const { rows } = buildScaffold({
      themes: [
        { slug: "dracula", current: false },
        { slug: "nord", current: false },
      ],
      currentThemeName: "dracula",
    })
    await tick()

    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(true)
  })

  it("sets data-theme to the highlighted row on connect (live preview)", async () => {
    buildScaffold({
      themes: [
        { slug: "tokyo-night", current: true },
        { slug: "dracula", current: false },
      ],
      currentThemeName: "tokyo-night",
    })
    await tick()

    expect(document.documentElement.dataset.theme).toBe("tokyo-night")
  })

  // ── ArrowDown / ArrowUp — preview ─────────────────────────────────────────

  it("ArrowDown moves highlight and sets data-theme", async () => {
    const { rows } = buildScaffold({
      themes: [
        { slug: "tokyo-night", current: true },
        { slug: "dracula", current: false },
      ],
      currentThemeName: "tokyo-night",
    })
    await tick()

    fireKey("ArrowDown")

    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(true)
    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(false)
    expect(document.documentElement.dataset.theme).toBe("dracula")
  })

  it("ArrowUp moves highlight and sets data-theme", async () => {
    const { rows } = buildScaffold({
      themes: [
        { slug: "tokyo-night", current: false },
        { slug: "dracula", current: true },
      ],
      currentThemeName: "dracula",
    })
    await tick()

    fireKey("ArrowUp")

    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(true)
    expect(document.documentElement.dataset.theme).toBe("tokyo-night")
  })

  it("ArrowDown clamps at the last row", async () => {
    const { rows } = buildScaffold({
      themes: [
        { slug: "tokyo-night", current: true },
        { slug: "dracula", current: false },
      ],
      currentThemeName: "tokyo-night",
    })
    await tick()

    fireKey("ArrowDown")
    fireKey("ArrowDown") // stays at row[1]

    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(true)
    expect(document.documentElement.dataset.theme).toBe("dracula")
  })

  it("ArrowUp clamps at the first row", async () => {
    const { rows } = buildScaffold({
      themes: [
        { slug: "tokyo-night", current: true },
        { slug: "dracula", current: false },
      ],
      currentThemeName: "tokyo-night",
    })
    await tick()

    fireKey("ArrowUp") // already at 0 — stays

    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(true)
    expect(document.documentElement.dataset.theme).toBe("tokyo-night")
  })

  // ── Click — highlight + preview ───────────────────────────────────────────

  it("click on a row highlights it and previews its theme", async () => {
    const { rows } = buildScaffold({
      themes: [
        { slug: "tokyo-night", current: true },
        { slug: "dracula", current: false },
        { slug: "nord", current: false },
      ],
      currentThemeName: "tokyo-night",
    })
    await tick()

    rows[2].dispatchEvent(new MouseEvent("click", { bubbles: true }))

    expect(rows[2].classList.contains("pito-resume-highlight")).toBe(true)
    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(false)
    expect(document.documentElement.dataset.theme).toBe("nord")
  })

  it("click on a child element inside a row highlights the row", async () => {
    const { rows } = buildScaffold({
      themes: [
        { slug: "tokyo-night", current: true },
        { slug: "dracula", current: false },
      ],
      currentThemeName: "tokyo-night",
    })
    await tick()

    // Append a child span to row[1] and click on it.
    const child = document.createElement("span")
    rows[1].appendChild(child)
    child.dispatchEvent(new MouseEvent("click", { bubbles: true }))

    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(true)
    expect(document.documentElement.dataset.theme).toBe("dracula")
  })

  // ── Enter — apply (PATCH) ─────────────────────────────────────────────────

  it("Enter sends PATCH /settings/theme with the highlighted slug", async () => {
    buildScaffold({
      themes: [
        { slug: "tokyo-night", current: true },
        { slug: "dracula", current: false },
      ],
      currentThemeName: "tokyo-night",
    })
    await tick()

    fireKey("ArrowDown")  // highlight dracula
    fireKey("Enter")

    expect(globalThis.fetch).toHaveBeenCalledWith(
      "/settings/theme",
      expect.objectContaining({
        method: "PATCH",
        body: JSON.stringify({ theme: "dracula" }),
      })
    )
  })

  it("Enter PATCH includes Content-Type: application/json", async () => {
    buildScaffold({
      themes: [{ slug: "tokyo-night", current: true }],
      currentThemeName: "tokyo-night",
    })
    await tick()

    fireKey("Enter")

    expect(globalThis.fetch).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        headers: expect.objectContaining({ "Content-Type": "application/json" }),
      })
    )
  })

  it("Enter PATCH includes the CSRF token header", async () => {
    buildScaffold({
      themes: [{ slug: "tokyo-night", current: true }],
      currentThemeName: "tokyo-night",
    })
    await tick()

    fireKey("Enter")

    expect(globalThis.fetch).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        headers: expect.objectContaining({ "X-CSRF-Token": "test-csrf-token" }),
      })
    )
  })

  it("Enter clears the sidebar (#pito-sidebar.innerHTML = '')", async () => {
    const { sidebar } = buildScaffold({
      themes: [{ slug: "tokyo-night", current: true }],
      currentThemeName: "tokyo-night",
    })
    await tick()

    fireKey("Enter")

    // The sidebar is cleared — the controller element is gone.
    expect(sidebar.innerHTML).toBe("")
  })

  // ── disconnect — revert WITHOUT apply ─────────────────────────────────────

  it("disconnect WITHOUT apply reverts data-theme to the original theme", async () => {
    const { controller } = buildScaffold({
      themes: [
        { slug: "tokyo-night", current: true },
        { slug: "dracula", current: false },
      ],
      currentThemeName: "tokyo-night",
    })
    await tick()

    fireKey("ArrowDown")  // preview dracula
    expect(document.documentElement.dataset.theme).toBe("dracula")

    // Simulate Esc / sidebar clear: remove the controller element.
    controller.remove()
    await tick()

    expect(document.documentElement.dataset.theme).toBe("tokyo-night")
  })

  // ── disconnect — keep WITH apply ─────────────────────────────────────────

  it("disconnect AFTER apply keeps the applied theme", async () => {
    const { controller } = buildScaffold({
      themes: [
        { slug: "tokyo-night", current: true },
        { slug: "dracula", current: false },
      ],
      currentThemeName: "tokyo-night",
    })
    await tick()

    fireKey("ArrowDown")  // preview dracula
    fireKey("Enter")      // apply dracula — sets applied = true, clears sidebar
    // The sidebar is cleared, but we have a reference to the controller element.
    // Removing it triggers disconnect again if it's still in the DOM — but since
    // Enter already cleared sidebar.innerHTML, the element is detached and
    // Stimulus already called disconnect.  Assert data-theme is the applied one.
    await tick()

    expect(document.documentElement.dataset.theme).toBe("dracula")
  })

  // ── no-rows guard ─────────────────────────────────────────────────────────

  it("arrow keys do not move any highlight when there are no rows", async () => {
    const { controller } = buildScaffold({ themes: [], currentThemeName: "tokyo-night" })
    await tick()

    fireKey("ArrowDown")
    fireKey("ArrowUp")

    // No rows exist, so no element can gain the highlight class.
    const highlighted = controller.querySelectorAll(".pito-resume-highlight")
    expect(highlighted.length).toBe(0)
  })
})
