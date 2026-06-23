// spec/javascript/games_nav_controller.test.js
//
// Vitest suite for pito--games-nav Stimulus controller.
//
// Strategy: mount the real controller on a jsdom document using the same
// Stimulus-Application pattern as theme_nav_controller.test.js.
//
// COVERAGE
//   - connect() highlights first row
//   - ↑/↓ moves the highlight
//   - Arrow keys do not go out of bounds
//   - Click highlights the clicked row
//   - Enter on a row dispatches pito:picker:select with the correct command
//   - Mode "show" → `show game #<id>`
//   - Mode "delete" → `rm game #<id>`
//   - Selecting clears the sidebar
//   - disconnect() cleans up listeners

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import GamesNavController from "controllers/pito/games_nav_controller"

// ── DOM scaffold ─────────────────────────────────────────────────────────────

function buildScaffold({ mode = "show", games = [] } = {}) {
  // Sidebar container
  const sidebar = document.createElement("div")
  sidebar.id = "pito-sidebar"
  document.body.appendChild(sidebar)

  // Nav container — controller mounts here
  const nav = document.createElement("div")
  nav.setAttribute("data-controller", "pito--games-nav")
  nav.setAttribute("data-pito--games-nav-mode-value", mode)

  // Game rows
  games.forEach(({ id, title }) => {
    const row = document.createElement("div")
    row.className = "pito-game-row"
    row.dataset.gameId    = String(id)
    row.dataset.gameTitle = title
    row.textContent = `#${id} ${title}`
    nav.appendChild(row)
  })

  sidebar.appendChild(nav)
  return { nav, sidebar }
}

function key(el, keyName, opts = {}) {
  const event = new KeyboardEvent("keydown", { key: keyName, bubbles: true, cancelable: true, ...opts })
  document.dispatchEvent(event)
}

// ── Test suite ────────────────────────────────────────────────────────────────

describe("pito--games-nav controller", () => {
  let app, nav, sidebar

  beforeEach(() => {
    app = Application.start()
    app.register("pito--games-nav", GamesNavController)
  })

  afterEach(async () => {
    vi.restoreAllMocks()
    await app.stop()
    document.body.innerHTML = ""
  })

  function waitForConnect() {
    return new Promise((r) => setTimeout(r, 0))
  }

  // ── Highlight initialisation ────────────────────────────────────────────────

  it("highlights the first row on connect", async () => {
    ;({ nav } = buildScaffold({
      games: [{ id: 1, title: "Lies of P" }, { id: 2, title: "Hollow Knight" }]
    }))
    await waitForConnect()

    const rows = nav.querySelectorAll(".pito-game-row")
    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(true)
    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(false)
  })

  it("does not crash with an empty list", async () => {
    ;({ nav } = buildScaffold({ games: [] }))
    await waitForConnect()
    expect(nav.querySelectorAll(".pito-game-row")).toHaveLength(0)
  })

  // ── Arrow key navigation ────────────────────────────────────────────────────

  it("ArrowDown moves highlight to the second row", async () => {
    ;({ nav } = buildScaffold({
      games: [{ id: 1, title: "A" }, { id: 2, title: "B" }]
    }))
    await waitForConnect()

    key(nav, "ArrowDown")

    const rows = nav.querySelectorAll(".pito-game-row")
    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(false)
    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(true)
  })

  it("ignores arrow keys while the ctrl+k palette is open (no dual cursor)", async () => {
    const palette = document.createElement("div")
    palette.id = "pito-command-palette" // open = NOT hidden
    document.body.appendChild(palette)

    ;({ nav } = buildScaffold({
      games: [{ id: 1, title: "A" }, { id: 2, title: "B" }]
    }))
    await waitForConnect()

    key(nav, "ArrowDown") // should be ignored — palette owns the keys

    const rows = nav.querySelectorAll(".pito-game-row")
    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(true)
    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(false)

    palette.remove()
  })

  it("ArrowUp does not go below index 0", async () => {
    ;({ nav } = buildScaffold({
      games: [{ id: 1, title: "A" }, { id: 2, title: "B" }]
    }))
    await waitForConnect()

    key(nav, "ArrowUp")

    const rows = nav.querySelectorAll(".pito-game-row")
    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(true)
  })

  it("ArrowDown does not go past the last row", async () => {
    ;({ nav } = buildScaffold({
      games: [{ id: 1, title: "A" }, { id: 2, title: "B" }]
    }))
    await waitForConnect()

    key(nav, "ArrowDown")
    key(nav, "ArrowDown") // try to go past the end

    const rows = nav.querySelectorAll(".pito-game-row")
    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(true)
  })

  // ── Click navigation ────────────────────────────────────────────────────────

  it("clicking a row highlights it", async () => {
    ;({ nav } = buildScaffold({
      games: [{ id: 1, title: "A" }, { id: 2, title: "B" }]
    }))
    await waitForConnect()

    const rows = nav.querySelectorAll(".pito-game-row")
    rows[1].dispatchEvent(new MouseEvent("click", { bubbles: true }))

    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(true)
    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(false)
  })

  it("clicking a row selects it (like arrow-to-it + Enter)", async () => {
    ;({ nav, sidebar } = buildScaffold({
      mode:  "show",
      games: [{ id: 1, title: "A" }, { id: 2, title: "B" }]
    }))
    await waitForConnect()

    const events = []
    const handler = (e) => events.push(e.detail)
    document.addEventListener("pito:picker:select", handler)
    try {
      const rows = nav.querySelectorAll(".pito-game-row")
      rows[1].dispatchEvent(new MouseEvent("click", { bubbles: true }))

      // Same command Enter on row 1 would build, and the sidebar is cleared.
      expect(events).toHaveLength(1)
      expect(events[0].command).toBe("show game #2")
      expect(sidebar.innerHTML).toBe("")
    } finally {
      document.removeEventListener("pito:picker:select", handler)
    }
  })

  // ── Focus guard ───────────────────────────────────────────────────────────
  // Regression: while a picker is open, Enter-to-send in the chatbox was hijacked
  // and the highlighted game got injected as `show/rm game #id`. The guard skips
  // keys when focus is in a text field OUTSIDE the picker.
  it("does not hijack Enter while focus is in a field outside the picker (chatbox)", async () => {
    ;({ nav, sidebar } = buildScaffold({
      mode:  "show",
      games: [{ id: 1, title: "A" }, { id: 2, title: "B" }]
    }))
    await waitForConnect()

    const chatbox = document.createElement("textarea") // stands in for the chatbox
    document.body.appendChild(chatbox)
    chatbox.focus()

    const events = []
    const handler = (e) => events.push(e.detail)
    document.addEventListener("pito:picker:select", handler)
    try {
      key(document, "Enter")
      expect(events).toHaveLength(0)         // not hijacked
      expect(sidebar.innerHTML).not.toBe("") // picker stays open
    } finally {
      document.removeEventListener("pito:picker:select", handler)
      chatbox.remove()
    }
  })

  // ── Enter selection ─────────────────────────────────────────────────────────
  // We call #select directly on the controller instance to avoid cross-test
  // pollution from document-level keydown listeners that haven't been torn down
  // yet by the async afterEach.

  it("Enter (show mode): #select builds show game command", async () => {
    ;({ nav, sidebar } = buildScaffold({
      mode:  "show",
      games: [{ id: 7, title: "Hollow Knight" }]
    }))
    await waitForConnect()

    const ctrl = app.getControllerForElementAndIdentifier(nav, "pito--games-nav")

    const events = []
    const handler = (e) => events.push(e.detail)
    document.addEventListener("pito:picker:select", handler)
    try {
      const row = nav.querySelector(".pito-game-row")
      ctrl._testSelect(row)   // call private via public test shim
      expect(events).toHaveLength(1)
      expect(events[0].command).toBe("show game #7")
    } finally {
      document.removeEventListener("pito:picker:select", handler)
    }
  })

  it("Enter (delete mode): #select builds rm game command", async () => {
    ;({ nav, sidebar } = buildScaffold({
      mode:  "delete",
      games: [{ id: 3, title: "Celeste" }]
    }))
    await waitForConnect()

    const ctrl = app.getControllerForElementAndIdentifier(nav, "pito--games-nav")

    const events = []
    const handler = (e) => events.push(e.detail)
    document.addEventListener("pito:picker:select", handler)
    try {
      const row = nav.querySelector(".pito-game-row")
      ctrl._testSelect(row)
      expect(events).toHaveLength(1)
      expect(events[0].command).toBe("rm game #3")
    } finally {
      document.removeEventListener("pito:picker:select", handler)
    }
  })

  it("selecting a row clears the sidebar", async () => {
    ;({ nav, sidebar } = buildScaffold({
      mode:  "show",
      games: [{ id: 1, title: "A" }]
    }))
    await waitForConnect()

    const ctrl = app.getControllerForElementAndIdentifier(nav, "pito--games-nav")
    const handler = () => {}
    document.addEventListener("pito:picker:select", handler)
    try {
      const row = nav.querySelector(".pito-game-row")
      ctrl._testSelect(row)
      expect(sidebar.innerHTML).toBe("")
    } finally {
      document.removeEventListener("pito:picker:select", handler)
    }
  })

  it("highlightIndex is -1 for an empty list (no selection possible)", async () => {
    ;({ nav } = buildScaffold({ games: [] }))
    await waitForConnect()

    const ctrl = app.getControllerForElementAndIdentifier(nav, "pito--games-nav")
    expect(ctrl.highlightIndex).toBe(-1)
  })

  // ── Disconnect ──────────────────────────────────────────────────────────────

  it("disconnect does not throw", async () => {
    ;({ nav } = buildScaffold({ games: [{ id: 1, title: "A" }] }))
    await waitForConnect()

    const ctrl = app.getControllerForElementAndIdentifier(nav, "pito--games-nav")
    expect(() => ctrl.disconnect()).not.toThrow()
  })

  // ── Search: list target isolation ──────────────────────────────────────────

  it("rows() scopes to list target when present", async () => {
    const sidebar = document.createElement("div")
    sidebar.id = "pito-sidebar"
    document.body.appendChild(sidebar)

    const nav = document.createElement("div")
    nav.setAttribute("data-controller", "pito--games-nav")
    nav.setAttribute("data-pito--games-nav-mode-value", "show")

    const list = document.createElement("div")
    list.setAttribute("data-pito--games-nav-target", "list")

    const row = document.createElement("div")
    row.className = "pito-game-row"
    row.dataset.gameId = "42"
    list.appendChild(row)

    // A decoy row outside the list target — should not be picked up
    const decoy = document.createElement("div")
    decoy.className = "pito-game-row"
    decoy.dataset.gameId = "99"
    nav.appendChild(decoy)

    nav.appendChild(list)
    sidebar.appendChild(nav)
    await waitForConnect()

    // Only the row inside the list target should be highlighted
    expect(row.classList.contains("pito-resume-highlight")).toBe(true)
    expect(decoy.classList.contains("pito-resume-highlight")).toBe(false)
  })

  // ── Debounced search ────────────────────────────────────────────────────────

  it("typing in the input triggers a debounced POST /games/search-local", async () => {
    const mockFetch = vi.fn().mockResolvedValue({
      ok:   true,
      text: () => Promise.resolve(""),
    })
    global.fetch = mockFetch

    const sidebar = document.createElement("div")
    sidebar.id = "pito-sidebar"
    document.body.appendChild(sidebar)

    const nav = document.createElement("div")
    nav.setAttribute("data-controller", "pito--games-nav")
    nav.setAttribute("data-pito--games-nav-mode-value", "show")

    const input = document.createElement("input")
    input.setAttribute("data-pito--games-nav-target", "input")
    nav.appendChild(input)

    const list = document.createElement("div")
    list.setAttribute("data-pito--games-nav-target", "list")
    nav.appendChild(list)

    sidebar.appendChild(nav)
    await waitForConnect()

    mockFetch.mockClear()

    input.value = "Hollow"
    input.dispatchEvent(new Event("input", { bubbles: true }))

    await new Promise((r) => setTimeout(r, 350))

    expect(mockFetch).toHaveBeenCalledOnce()
    const [url, opts] = mockFetch.mock.calls[0]
    expect(url).toBe("/games/search-local")
    expect(opts.method).toBe("POST")

    global.fetch = undefined
  })
})
