// spec/javascript/games_search_controller.test.js
//
// Vitest suite for pito--games-search Stimulus controller.
//
// Covers: connect() auto-focus, prefill search, shimmer toggle,
// debounce, ↑/↓/Enter navigation, step rows on import, disconnect.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import GamesSearchController from "controllers/pito/games_search_controller"

// ── DOM scaffold ──────────────────────────────────────────────────────────────

function buildScaffold({ prefill = "", uuid = "test-uuid" } = {}) {
  const sidebar = document.createElement("div")
  sidebar.id = "pito-sidebar"
  document.body.appendChild(sidebar)

  const wrapper = document.createElement("div")
  wrapper.setAttribute("data-controller", "pito--games-search")
  wrapper.setAttribute("data-pito--games-search-conversation-uuid-value", uuid)
  wrapper.setAttribute("data-pito--games-search-prefill-value", prefill)
  wrapper.setAttribute("data-pito--games-search-i18n-searching-value", "Searching IGDB…")
  wrapper.setAttribute("data-pito--games-search-i18n-no-results-value", "Nothing found.")
  wrapper.setAttribute("data-pito--games-search-i18n-error-value", "IGDB failed.")
  wrapper.setAttribute("data-pito--games-search-i18n-in-library-value", "In Library")
  wrapper.setAttribute("data-pito--games-search-i18n-in-library-hint-value", "(will resync)")
  wrapper.setAttribute(
    "data-pito--games-search-i18n-step-labels-value",
    JSON.stringify([
      "Fetching game info…",
      "Downloading cover art…",
      "Computing score…",
      "Indexing for recommendations…",
      "Preparing recommendations…",
    ])
  )

  const input = document.createElement("input")
  input.type = "text"
  input.value = prefill
  input.setAttribute("data-pito--games-search-target", "input")
  wrapper.appendChild(input)

  const shimmer = document.createElement("p")
  shimmer.setAttribute("data-pito--games-search-target", "shimmer")
  shimmer.classList.add("hidden")
  shimmer.innerHTML = '<span class="pito-network-shimmer">. . . . .</span>'
  wrapper.appendChild(shimmer)

  const status = document.createElement("p")
  status.setAttribute("data-pito--games-search-target", "status")
  status.classList.add("hidden")
  wrapper.appendChild(status)

  const results = document.createElement("div")
  results.setAttribute("data-pito--games-search-target", "results")
  wrapper.appendChild(results)

  sidebar.appendChild(wrapper)
  return { wrapper, input, shimmer, status, results, sidebar }
}

function addRow(results, { igdbId, title }) {
  const row = document.createElement("div")
  row.className = "pito-igdb-row"
  row.dataset.igdbId = String(igdbId)
  row.dataset.title  = title
  results.appendChild(row)
  return row
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito--games-search controller", () => {
  let app

  beforeEach(() => {
    // Provide a default no-op fetch so connect() + prefill search never throws
    global.fetch = vi.fn().mockResolvedValue({
      ok:   true,
      json: () => Promise.resolve({ hits: [], error: null, library_ids: [] }),
    })

    app = Application.start()
    app.register("pito--games-search", GamesSearchController)
  })

  afterEach(async () => {
    vi.restoreAllMocks()
    await app.stop()
    document.body.innerHTML = ""
    global.fetch = undefined
  })

  // Flush Stimulus mutation-observer callbacks + microtasks + rAF
  function tick(ms = 50) {
    return new Promise((r) => setTimeout(r, ms))
  }

  // ── T16.1: connect() auto-focus ───────────────────────────────────────────

  it("focuses the input after connect()", async () => {
    const { input } = buildScaffold()
    const focusSpy = vi.spyOn(input, "focus")
    await tick()
    expect(focusSpy).toHaveBeenCalled()
  })

  it("calls select() on the input when prefill is non-empty", async () => {
    const { input } = buildScaffold({ prefill: "Hollow Knight" })
    const selectSpy = vi.spyOn(input, "select")
    await tick()
    expect(selectSpy).toHaveBeenCalled()
  })

  it("does NOT call select() when prefill is empty", async () => {
    const { input } = buildScaffold({ prefill: "" })
    const selectSpy = vi.spyOn(input, "select")
    await tick()
    expect(selectSpy).not.toHaveBeenCalled()
  })

  // ── Prefill search ────────────────────────────────────────────────────────

  it("triggers an immediate search when prefill is non-empty", async () => {
    const mockFetch = vi.fn().mockResolvedValue({
      ok:   true,
      json: () => Promise.resolve({ hits: [], error: null, library_ids: [] }),
    })
    global.fetch = mockFetch

    buildScaffold({ prefill: "Hollow Knight" })
    await tick()

    expect(mockFetch).toHaveBeenCalledOnce()
    const body = JSON.parse(mockFetch.mock.calls[0][1].body)
    expect(body.query).toBe("Hollow Knight")
  })

  it("does NOT trigger a search when prefill is empty", async () => {
    const mockFetch = vi.fn()
    global.fetch = mockFetch

    buildScaffold({ prefill: "" })
    await tick()

    expect(mockFetch).not.toHaveBeenCalled()
  })

  // ── T16.5: shimmer toggle during search ──────────────────────────────────

  it("shows shimmer while search is in flight", async () => {
    let resolveFetch
    global.fetch = vi.fn().mockReturnValue(
      new Promise((r) => { resolveFetch = r })
    )

    const { input, shimmer } = buildScaffold()
    await tick()

    input.value = "Celeste"
    input.dispatchEvent(new Event("input", { bubbles: true }))

    // Before debounce fires, shimmer should still be hidden
    expect(shimmer.classList.contains("hidden")).toBe(true)

    // After debounce fires, shimmer should appear
    await tick(300)
    expect(shimmer.classList.contains("hidden")).toBe(false)

    // Resolve the fetch — shimmer should hide again
    resolveFetch({ ok: true, json: () => Promise.resolve({ hits: [], library_ids: [] }) })
    await tick()
    expect(shimmer.classList.contains("hidden")).toBe(true)
  })

  // ── Input event → search ──────────────────────────────────────────────────

  it("calls /games/search when input value changes (after debounce)", async () => {
    const mockFetch = vi.fn().mockResolvedValue({
      ok:   true,
      json: () => Promise.resolve({ hits: [], error: null, library_ids: [] }),
    })
    global.fetch = mockFetch

    const { input } = buildScaffold()
    await tick()  // let connect() run; no prefill → no initial fetch

    mockFetch.mockClear()

    // Simulate user typing
    input.value = "Celeste"
    input.dispatchEvent(new Event("input", { bubbles: true }))

    // Wait longer than DEBOUNCE_MS (250ms)
    await tick(350)

    expect(mockFetch).toHaveBeenCalledOnce()
    const body = JSON.parse(mockFetch.mock.calls[0][1].body)
    expect(body.query).toBe("Celeste")
  })

  // ── Clear input → reset ───────────────────────────────────────────────────

  it("clears results when input is emptied", async () => {
    const { input, results } = buildScaffold()
    await tick()

    // Add a row manually
    addRow(results, { igdbId: 1, title: "Some Game" })
    expect(results.children.length).toBe(1)

    // Clear input
    input.value = ""
    input.dispatchEvent(new Event("input", { bubbles: true }))
    await tick()

    expect(results.children.length).toBe(0)
  })

  // ── T16.5: witty copy via data attr ──────────────────────────────────────

  it("shows the i18n no-results text when IGDB returns empty hits", async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok:   true,
      json: () => Promise.resolve({ hits: [], error: null, library_ids: [] }),
    })
    const { input, status } = buildScaffold()
    await tick()

    input.value = "Something"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    await tick(350)

    expect(status.textContent).toBe("Nothing found.")
    expect(status.classList.contains("hidden")).toBe(false)
  })

  // ── Keyboard navigation ───────────────────────────────────────────────────

  it("ArrowDown highlights first row (from no selection)", async () => {
    const { results } = buildScaffold()
    await tick()

    const row0 = addRow(results, { igdbId: 1, title: "Alpha" })
    addRow(results, { igdbId: 2, title: "Beta" })

    document.dispatchEvent(new KeyboardEvent("keydown", {
      key: "ArrowDown", bubbles: true, cancelable: true
    }))
    await tick()

    expect(row0.classList.contains("pito-resume-highlight")).toBe(true)
  })

  it("ArrowDown then ArrowDown highlights second row", async () => {
    const { results } = buildScaffold()
    await tick()

    const row0 = addRow(results, { igdbId: 1, title: "Alpha" })
    const row1 = addRow(results, { igdbId: 2, title: "Beta" })

    document.dispatchEvent(new KeyboardEvent("keydown", {
      key: "ArrowDown", bubbles: true, cancelable: true
    }))
    document.dispatchEvent(new KeyboardEvent("keydown", {
      key: "ArrowDown", bubbles: true, cancelable: true
    }))
    await tick()

    expect(row0.classList.contains("pito-resume-highlight")).toBe(false)
    expect(row1.classList.contains("pito-resume-highlight")).toBe(true)
  })

  it("ignores arrow keys while the ctrl+k palette is open (no dual cursor)", async () => {
    const { results } = buildScaffold()
    await tick()

    // Command palette open over the sidebar: present + not `.hidden` → paletteOpen() true.
    const palette = document.createElement("div")
    palette.id = "pito-command-palette"
    document.body.appendChild(palette)

    const row0 = addRow(results, { igdbId: 1, title: "Alpha" })
    addRow(results, { igdbId: 2, title: "Beta" })

    document.dispatchEvent(new KeyboardEvent("keydown", {
      key: "ArrowDown", bubbles: true, cancelable: true
    }))
    await tick()

    // The palette owns the keys — the import picker bails, so NO row is highlighted.
    expect(row0.classList.contains("pito-resume-highlight")).toBe(false)
  })

  // ── T16.8: step rows rendered on import (sidebar stays open) ─────────────

  // Helper: trigger a search that returns one hit, then use ArrowDown+Enter to select it.
  async function selectFirstResult({ fetch: mockFetch, results, input }) {
    global.fetch = mockFetch

    // Trigger a search
    input.value = "Elden Ring"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    await tick(350)  // wait for debounce + fetch

    // Manually render a result row as the controller would (after a real fetch)
    // The controller's #renderResults attaches click listeners — simulate via keyboard.
    // Arrow down to highlight row 0, then Enter to select.
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }))
    await tick()
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
    await tick()
  }

  it("replaces results with 5 step rows after ArrowDown+Enter import", async () => {
    // First fetch = search results with one hit; second fetch = /games/import 204
    let callCount = 0
    global.fetch = vi.fn().mockImplementation((url) => {
      callCount++
      if (url.includes("/games/search")) {
        return Promise.resolve({
          ok: true,
          json: async () => ({
            hits: [ { id: 42, name: "Elden Ring", cover: { image_id: "abc123" } } ],
            library_ids: [],
          }),
        })
      }
      return Promise.resolve({ ok: true, json: async () => ({}) })
    })

    const { input, results } = buildScaffold()
    await tick()

    // Trigger search
    input.value = "Elden Ring"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    await tick(350)

    // ArrowDown to select first result
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }))
    await tick()

    // Enter triggers import
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
    await tick()

    // Results region should now have 5 step rows
    const stepRows = results.querySelectorAll("[id^='import-step-']")
    expect(stepRows.length).toBe(5)
    expect(Array.from(stepRows).map((r) => r.id)).toEqual([
      "import-step-1", "import-step-2", "import-step-3", "import-step-4", "import-step-5",
    ])
  })

  it("renders search rows AND step rows at the base font size (no text-size utilities)", async () => {
    global.fetch = vi.fn().mockImplementation((url) => {
      if (url.includes("/games/search")) {
        return Promise.resolve({
          ok: true,
          json: async () => ({
            hits: [ { id: 42, name: "Elden Ring", type_note: "(remake)", cover: { image_id: "abc123" } } ],
            library_ids: [ 42 ], // also renders the in-library badge
          }),
        })
      }
      return Promise.resolve({ ok: true, json: async () => ({}) })
    })

    const { input, results } = buildScaffold()
    await tick()

    input.value = "Elden Ring"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    await tick(350)

    // Design rule: one 14px base size, NO text-size utilities (text-xs/sm/base/lg/xl).
    const SIZE_RE = /\btext-(xs|sm|base|lg|xl|2xl|3xl)\b/
    const anySized = (root) =>
      Array.from(root.querySelectorAll("*")).some((el) => SIZE_RE.test(el.className || ""))

    expect(anySized(results), "search rows must use the base size").toBe(false)

    // Import → step rows must also be base size.
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }))
    await tick()
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
    await tick()

    expect(results.querySelectorAll("[id^='import-step-']").length).toBe(5)
    expect(anySized(results), "step rows must use the base size").toBe(false)
  })

  it("does NOT clear the sidebar element on import (keeps sidebar open)", async () => {
    global.fetch = vi.fn().mockImplementation((url) => {
      if (url.includes("/games/search")) {
        return Promise.resolve({
          ok: true,
          json: async () => ({
            hits: [ { id: 1, name: "Celeste", cover: { image_id: "xyz" } } ],
            library_ids: [],
          }),
        })
      }
      return Promise.resolve({ ok: true, json: async () => ({}) })
    })

    const { input, sidebar, results } = buildScaffold()
    await tick()

    input.value = "Celeste"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    await tick(350)

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }))
    await tick()
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
    await tick()

    // The sidebar element itself should still have content
    expect(sidebar.innerHTML).not.toBe("")
  })

  it("each step row has a .pito-network-shimmer span with an animation-delay", async () => {
    global.fetch = vi.fn().mockImplementation((url) => {
      if (url.includes("/games/search")) {
        return Promise.resolve({
          ok: true,
          json: async () => ({
            hits: [ { id: 1, name: "Test Game", cover: { image_id: "img1" } } ],
            library_ids: [],
          }),
        })
      }
      return Promise.resolve({ ok: true, json: async () => ({}) })
    })

    const { input, results } = buildScaffold()
    await tick()

    input.value = "Test Game"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    await tick(350)

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }))
    await tick()
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
    await tick()

    const stepRows = Array.from(results.querySelectorAll("[id^='import-step-']"))
    expect(stepRows.length).toBe(5)
    stepRows.forEach((r, i) => {
      const dot = r.querySelector(".pito-network-shimmer")
      expect(dot, `step ${i + 1} should have .pito-network-shimmer`).not.toBeNull()
      // animationDelay should be set (stagger)
      expect(dot.style.animationDelay).toBeTruthy()
    })
  })

  // ── Click selection (= arrow-to-it + Enter) ───────────────────────────────

  it("clicking a rendered result row selects+imports it (like ArrowDown+Enter)", async () => {
    const importCalls = []
    global.fetch = vi.fn().mockImplementation((url, opts) => {
      if (url.includes("/games/search")) {
        return Promise.resolve({
          ok: true,
          json: async () => ({
            hits: [
              { id: 11, name: "Alpha", cover: { image_id: "a" } },
              { id: 22, name: "Beta",  cover: { image_id: "b" } },
            ],
            library_ids: [],
          }),
        })
      }
      if (url.includes("/games/import")) importCalls.push(JSON.parse(opts.body))
      return Promise.resolve({ ok: true, json: async () => ({}) })
    })

    const { input, results } = buildScaffold()
    await tick()

    input.value = "A"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    await tick(350)

    const rows = results.querySelectorAll(".pito-igdb-row")
    expect(rows.length).toBe(2)

    // Click the SECOND row — should highlight it and run the import path.
    rows[1].dispatchEvent(new MouseEvent("click", { bubbles: true }))
    await tick()

    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(true)
    expect(importCalls).toHaveLength(1)
    expect(importCalls[0].igdb_id).toBe("22")
    // Results region is replaced with the 5 shimmer step rows.
    expect(results.querySelectorAll("[id^='import-step-']").length).toBe(5)
  })

  // ── Enter with no rows is a no-op ─────────────────────────────────────────

  it("does NOT call /games/search when Enter is pressed (not ArrowDown+Enter)", async () => {
    const { results } = buildScaffold({ prefill: "" })
    await tick()

    // No rows in results → Enter should do nothing
    expect(results.querySelectorAll(".pito-igdb-row").length).toBe(0)
    document.dispatchEvent(new KeyboardEvent("keydown", {
      key: "Enter", bubbles: true, cancelable: true
    }))
    await tick()
    expect(results.querySelectorAll(".pito-igdb-row").length).toBe(0)
  })

  // ── Disconnect cleanup ────────────────────────────────────────────────────

  it("controller disconnects cleanly without throwing", async () => {
    const { input } = buildScaffold()
    await tick()

    // Set up a pending debounce timer by typing (timer will be cancelled by disconnect)
    input.value = "foo"
    input.dispatchEvent(new Event("input", { bubbles: true }))

    // Stop cleanly — should not throw
    let threw = false
    try {
      await app.stop()
    } catch {
      threw = true
    }
    expect(threw).toBe(false)
  })
})
