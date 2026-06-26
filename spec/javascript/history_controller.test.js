// spec/javascript/history_controller.test.js
//
// Tests for pito--history Stimulus controller (history_controller.js).
//
// Strategy: mount the real controller on a jsdom document with a minimal
// #pito-chatbox + textarea scaffold, then dispatch keyboard events and
// assert textarea.value cycles through history entries.

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import HistoryController from "controllers/pito/history_controller"

// ── Helpers ──────────────────────────────────────────────────────────────────

function arrowUp(el) {
  el.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowUp", bubbles: true }))
}

function arrowDown(el) {
  el.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }))
}

// Build the minimal DOM scaffold expected by the controller and return the key
// elements.  entriesJson is the JSON-encoded history array (newest-first).
function buildScaffold(entriesJson = "[]") {
  const chatbox = document.createElement("div")
  chatbox.id = "pito-chatbox"
  chatbox.setAttribute("data-controller", "pito--history")
  chatbox.setAttribute("data-pito--history-entries-value", entriesJson)

  const textarea = document.createElement("textarea")
  chatbox.appendChild(textarea)

  document.body.appendChild(chatbox)

  return { chatbox, textarea }
}

// ── Test suite ────────────────────────────────────────────────────────────────

describe("pito--history controller", () => {
  let app

  beforeEach(() => {
    // Fresh Stimulus application for each test.
    app = Application.start()
    app.register("pito--history", HistoryController)
  })

  afterEach(async () => {
    // Tear down Stimulus and clean the DOM.
    await app.stop()
    document.body.innerHTML = ""
  })

  // Give Stimulus a tick to connect the controller after DOM insertion.
  function waitForConnect() {
    return new Promise((r) => setTimeout(r, 0))
  }

  // ── Basic cycling ──────────────────────────────────────────────────────────

  it("ArrowUp cycles to the most-recent entry", async () => {
    const { chatbox, textarea } = buildScaffold(JSON.stringify(["last", "first"]))
    await waitForConnect()

    arrowUp(chatbox)

    expect(textarea.value).toBe("last")
  })

  it("ArrowUp then ArrowUp moves to the older entry", async () => {
    const { chatbox, textarea } = buildScaffold(JSON.stringify(["second", "first"]))
    await waitForConnect()

    arrowUp(chatbox)
    arrowUp(chatbox)

    expect(textarea.value).toBe("first")
  })

  it("ArrowDown after ArrowUp returns to the (prefix) draft", async () => {
    const { chatbox, textarea } = buildScaffold(JSON.stringify(["cmd1"]))
    await waitForConnect()

    textarea.value = "cm"   // a prefix of "cmd1"
    arrowUp(chatbox)

    expect(textarea.value).toBe("cmd1")

    arrowDown(chatbox)

    expect(textarea.value).toBe("cm")
  })

  it("ArrowDown at the current draft is a no-op", async () => {
    const { chatbox, textarea } = buildScaffold(JSON.stringify(["cmd1"]))
    await waitForConnect()

    textarea.value = "still draft"
    arrowDown(chatbox)

    expect(textarea.value).toBe("still draft")
  })

  it("ArrowUp does nothing when entries is empty", async () => {
    const { chatbox, textarea } = buildScaffold("[]")
    await waitForConnect()

    textarea.value = "unchanged"
    arrowUp(chatbox)

    expect(textarea.value).toBe("unchanged")
  })

  it("ArrowUp does not go past the oldest entry", async () => {
    const { chatbox, textarea } = buildScaffold(JSON.stringify(["only"]))
    await waitForConnect()

    arrowUp(chatbox)  // → "only"
    arrowUp(chatbox)  // should stay at "only"

    expect(textarea.value).toBe("only")
  })

  // ── Guard: suggestions palette open ───────────────────────────────────────

  it("ignores ArrowUp when the suggestions palette is visible", async () => {
    const { chatbox, textarea } = buildScaffold(JSON.stringify(["blocked"]))
    await waitForConnect()

    // Insert a visible (not hidden) suggestions palette.
    const palette = document.createElement("div")
    palette.className = "pito-suggestions-palette"  // no "hidden" class → visible
    document.body.appendChild(palette)

    textarea.value = "initial"
    arrowUp(chatbox)

    expect(textarea.value).toBe("initial")

    palette.remove()
  })

  it("ignores ArrowUp when the sidebar has children (is open)", async () => {
    const { chatbox, textarea } = buildScaffold(JSON.stringify(["blocked"]))
    await waitForConnect()

    // Create an open sidebar (has at least one child element).
    const sidebar = document.createElement("div")
    sidebar.id = "pito-sidebar"
    const child = document.createElement("div")
    sidebar.appendChild(child)
    document.body.appendChild(sidebar)

    textarea.value = "initial"
    arrowUp(chatbox)

    expect(textarea.value).toBe("initial")

    sidebar.remove()
  })

  it("allows ArrowUp when the sidebar exists but is empty (closed)", async () => {
    const { chatbox, textarea } = buildScaffold(JSON.stringify(["cmd"]))
    await waitForConnect()

    // Sidebar present but no children → treated as closed.
    const sidebar = document.createElement("div")
    sidebar.id = "pito-sidebar"
    document.body.appendChild(sidebar)

    textarea.value = ""
    arrowUp(chatbox)

    expect(textarea.value).toBe("cmd")

    sidebar.remove()
  })

  // ── Prefix matching (oh-my-zsh) ─────────────────────────────────────────────

  describe("prefix-matched recall", () => {
    // newest-first; "/connect" does NOT start with "/conf" (4th char n≠f).
    const ENTRIES = JSON.stringify(["/config google", "/connect", "/config fx"])

    it("ArrowUp recalls only entries starting with the typed prefix", async () => {
      const { chatbox, textarea } = buildScaffold(ENTRIES)
      await waitForConnect()

      textarea.value = "/conf"
      arrowUp(chatbox)
      expect(textarea.value).toBe("/config google")   // newest match
      arrowUp(chatbox)
      expect(textarea.value).toBe("/config fx")        // older match (skips /connect)
    })

    it("does not wrap past the oldest match", async () => {
      const { chatbox, textarea } = buildScaffold(ENTRIES)
      await waitForConnect()

      textarea.value = "/conf"
      arrowUp(chatbox)  // /config google
      arrowUp(chatbox)  // /config fx
      arrowUp(chatbox)  // stays at oldest match
      expect(textarea.value).toBe("/config fx")
    })

    it("ArrowDown returns to the typed prefix", async () => {
      const { chatbox, textarea } = buildScaffold(ENTRIES)
      await waitForConnect()

      textarea.value = "/conf"
      arrowUp(chatbox)
      expect(textarea.value).toBe("/config google")
      arrowDown(chatbox)
      expect(textarea.value).toBe("/conf")
    })

    it("ArrowUp does nothing when no entry matches the prefix", async () => {
      const { chatbox, textarea } = buildScaffold(ENTRIES)
      await waitForConnect()

      textarea.value = "/zzz"
      arrowUp(chatbox)
      expect(textarea.value).toBe("/zzz")
    })

    it("typing a character ends recall and re-snapshots the new prefix", async () => {
      const { chatbox, textarea } = buildScaffold(ENTRIES)
      await waitForConnect()

      textarea.value = "/conf"
      arrowUp(chatbox)
      expect(textarea.value).toBe("/config google")

      // A real user edit (input event) ends the session; next ↑ re-snapshots.
      textarea.value = "/conn"
      textarea.dispatchEvent(new Event("input", { bubbles: true }))

      arrowUp(chatbox)
      expect(textarea.value).toBe("/connect")
    })
  })
})
