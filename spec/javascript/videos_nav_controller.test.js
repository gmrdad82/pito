// spec/javascript/videos_nav_controller.test.js
//
// Vitest suite for pito--videos-nav Stimulus controller.
//
// Mirrors games_nav_controller.test.js with video-specific row class
// (.pito-video-row), data attribute (data-video-id), and command
// (`show vid #<id>`).
//
// COVERAGE
//   - connect() highlights first row
//   - ↑/↓ moves the highlight
//   - Arrow keys do not go out of bounds
//   - Click highlights the clicked row
//   - Enter dispatches pito:picker:select with `show vid #<id>`
//   - Selecting clears the sidebar
//   - disconnect() cleans up listeners

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import VideosNavController from "controllers/pito/videos_nav_controller"

// ── DOM scaffold ─────────────────────────────────────────────────────────────

function buildScaffold({ videos = [] } = {}) {
  const sidebar = document.createElement("div")
  sidebar.id = "pito-sidebar"
  document.body.appendChild(sidebar)

  const nav = document.createElement("div")
  nav.setAttribute("data-controller", "pito--videos-nav")

  videos.forEach(({ id, title }) => {
    const row = document.createElement("div")
    row.className = "pito-video-row"
    row.dataset.videoId    = String(id)
    row.dataset.videoTitle = title
    row.textContent = `#${id} ${title}`
    nav.appendChild(row)
  })

  sidebar.appendChild(nav)
  return { nav, sidebar }
}

function key(keyName) {
  const event = new KeyboardEvent("keydown", { key: keyName, bubbles: true, cancelable: true })
  document.dispatchEvent(event)
}

// ── Test suite ────────────────────────────────────────────────────────────────

describe("pito--videos-nav controller", () => {
  let app, nav, sidebar

  beforeEach(() => {
    app = Application.start()
    app.register("pito--videos-nav", VideosNavController)
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
      videos: [{ id: 1, title: "Lies of P" }, { id: 2, title: "Hollow Knight" }]
    }))
    await waitForConnect()

    const rows = nav.querySelectorAll(".pito-video-row")
    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(true)
    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(false)
  })

  it("does not crash with an empty list", async () => {
    ;({ nav } = buildScaffold({ videos: [] }))
    await waitForConnect()
    expect(nav.querySelectorAll(".pito-video-row")).toHaveLength(0)
  })

  // ── Arrow key navigation ────────────────────────────────────────────────────

  it("ArrowDown moves highlight to the second row", async () => {
    ;({ nav } = buildScaffold({
      videos: [{ id: 1, title: "A" }, { id: 2, title: "B" }]
    }))
    await waitForConnect()

    key("ArrowDown")

    const rows = nav.querySelectorAll(".pito-video-row")
    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(false)
    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(true)
  })

  it("ArrowUp does not go below index 0", async () => {
    ;({ nav } = buildScaffold({
      videos: [{ id: 1, title: "A" }, { id: 2, title: "B" }]
    }))
    await waitForConnect()

    key("ArrowUp")

    const rows = nav.querySelectorAll(".pito-video-row")
    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(true)
  })

  it("ArrowDown does not go past the last row", async () => {
    ;({ nav } = buildScaffold({
      videos: [{ id: 1, title: "A" }, { id: 2, title: "B" }]
    }))
    await waitForConnect()

    key("ArrowDown")
    key("ArrowDown")

    const rows = nav.querySelectorAll(".pito-video-row")
    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(true)
  })

  // ── Click navigation ────────────────────────────────────────────────────────

  it("clicking a row highlights it", async () => {
    ;({ nav } = buildScaffold({
      videos: [{ id: 1, title: "A" }, { id: 2, title: "B" }]
    }))
    await waitForConnect()

    const rows = nav.querySelectorAll(".pito-video-row")
    rows[1].dispatchEvent(new MouseEvent("click", { bubbles: true }))

    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(true)
    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(false)
  })

  // ── Enter selection ─────────────────────────────────────────────────────────

  it("#select builds show vid command", async () => {
    ;({ nav, sidebar } = buildScaffold({
      videos: [{ id: 7, title: "Hollow Knight" }]
    }))
    await waitForConnect()

    const ctrl = app.getControllerForElementAndIdentifier(nav, "pito--videos-nav")

    const events = []
    const handler = (e) => events.push(e.detail)
    document.addEventListener("pito:picker:select", handler)
    try {
      const row = nav.querySelector(".pito-video-row")
      ctrl._testSelect(row)
      expect(events).toHaveLength(1)
      expect(events[0].command).toBe("show vid #7")
    } finally {
      document.removeEventListener("pito:picker:select", handler)
    }
  })

  it("selecting a row clears the sidebar", async () => {
    ;({ nav, sidebar } = buildScaffold({
      videos: [{ id: 1, title: "A" }]
    }))
    await waitForConnect()

    const ctrl = app.getControllerForElementAndIdentifier(nav, "pito--videos-nav")
    const handler = () => {}
    document.addEventListener("pito:picker:select", handler)
    try {
      const row = nav.querySelector(".pito-video-row")
      ctrl._testSelect(row)
      expect(sidebar.innerHTML).toBe("")
    } finally {
      document.removeEventListener("pito:picker:select", handler)
    }
  })

  it("highlightIndex is -1 for an empty list", async () => {
    ;({ nav } = buildScaffold({ videos: [] }))
    await waitForConnect()

    const ctrl = app.getControllerForElementAndIdentifier(nav, "pito--videos-nav")
    expect(ctrl.highlightIndex).toBe(-1)
  })

  // ── Disconnect ──────────────────────────────────────────────────────────────

  it("disconnect does not throw", async () => {
    ;({ nav } = buildScaffold({ videos: [{ id: 1, title: "A" }] }))
    await waitForConnect()

    const ctrl = app.getControllerForElementAndIdentifier(nav, "pito--videos-nav")
    expect(() => ctrl.disconnect()).not.toThrow()
  })

  // ── Search: list target isolation ──────────────────────────────────────────

  it("rows() scopes to list target when present", async () => {
    const sidebar = document.createElement("div")
    sidebar.id = "pito-sidebar"
    document.body.appendChild(sidebar)

    const nav = document.createElement("div")
    nav.setAttribute("data-controller", "pito--videos-nav")

    const list = document.createElement("div")
    list.setAttribute("data-pito--videos-nav-target", "list")

    const row = document.createElement("div")
    row.className = "pito-video-row"
    row.dataset.videoId = "42"
    list.appendChild(row)

    // A decoy row outside the list target — should not be picked up
    const decoy = document.createElement("div")
    decoy.className = "pito-video-row"
    decoy.dataset.videoId = "99"
    nav.appendChild(decoy)

    nav.appendChild(list)
    sidebar.appendChild(nav)
    await waitForConnect()

    // Only the row inside the list target should be highlighted
    expect(row.classList.contains("pito-resume-highlight")).toBe(true)
    expect(decoy.classList.contains("pito-resume-highlight")).toBe(false)
  })

  // ── Debounced search ────────────────────────────────────────────────────────

  it("typing in the input triggers a debounced POST /videos/search-local", async () => {
    const mockFetch = vi.fn().mockResolvedValue({
      ok:   true,
      text: () => Promise.resolve(""),
    })
    global.fetch = mockFetch

    const sidebar = document.createElement("div")
    sidebar.id = "pito-sidebar"
    document.body.appendChild(sidebar)

    const nav = document.createElement("div")
    nav.setAttribute("data-controller", "pito--videos-nav")

    const input = document.createElement("input")
    input.setAttribute("data-pito--videos-nav-target", "input")
    nav.appendChild(input)

    const list = document.createElement("div")
    list.setAttribute("data-pito--videos-nav-target", "list")
    nav.appendChild(list)

    sidebar.appendChild(nav)
    await waitForConnect()

    mockFetch.mockClear()

    input.value = "Hollow"
    input.dispatchEvent(new Event("input", { bubbles: true }))

    await new Promise((r) => setTimeout(r, 350))

    expect(mockFetch).toHaveBeenCalledOnce()
    const [url, opts] = mockFetch.mock.calls[0]
    expect(url).toBe("/videos/search-local")
    expect(opts.method).toBe("POST")

    global.fetch = undefined
  })
})
