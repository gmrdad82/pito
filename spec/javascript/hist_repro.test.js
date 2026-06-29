// Reproduce test for HIST1: ArrowUp on the TEXTAREA (not wrapper) should
// still recall history when pito--history, pito--suggestions, and
// pito--chat-showcase are all connected on the same #pito-chatbox.
//
// The existing history tests fire the event on the chatbox WRAPPER which
// bypasses data-action handlers (suggestions, chat-form). The real app
// fires on the TEXTAREA and it bubbles. This test reproduces the real flow.
//
// Root cause (HIST1): history#applyEntry dispatches a synthetic `input` event
// so other controllers (draft, caret, type-fx) rerender. The suggestions
// controller's onInput fires and opens the verb palette for slash commands
// (e.g. "/games" is in verb-stage when catalog has "games"). The NEXT arrow
// key then hits suggestions#handleKeydown with _paletteOpen=true →
// stopImmediatePropagation → history never sees it.

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import HistoryController from "controllers/pito/history_controller"
import SuggestionsController from "controllers/pito/suggestions_controller"
import ChatShowcaseController from "controllers/pito/chat_showcase_controller"

// Catalog with "games" and "sync" — these are verb-stage entries, so applying
// "/games" from history would open the suggestions palette (that's the bug).
const CATALOG_JSON = JSON.stringify({
  slash: [
    { name: "games",  description: "game commands" },
    { name: "sync",   description: "sync" },
    { name: "config", description: "configure" },
  ],
  hashtag: [],
  chat: [],
  vocabularies: { fillers: { fillers: [] } },
})

const SHOWCASE_JSON = JSON.stringify(["list games", "show last vid"])

function buildFullChatbox(entriesJson = "[]") {
  // Mirrors the real chatbox_component.html.erb structure
  const chatbox = document.createElement("div")
  chatbox.id = "pito-chatbox"
  chatbox.setAttribute("data-controller", "pito--suggestions pito--history pito--chat-showcase")
  chatbox.setAttribute("data-pito--history-entries-value", entriesJson)

  // Catalog script (suggestions target)
  const catalog = document.createElement("script")
  catalog.type = "application/json"
  catalog.setAttribute("data-pito--suggestions-target", "catalog")
  catalog.textContent = CATALOG_JSON
  chatbox.appendChild(catalog)

  // Showcase data script
  const showcaseData = document.createElement("script")
  showcaseData.type = "application/json"
  showcaseData.id = "pito-showcase-data"
  showcaseData.setAttribute("data-pito--chat-showcase-target", "data")
  showcaseData.textContent = SHOWCASE_JSON
  chatbox.appendChild(showcaseData)

  // Palette (suggestions target) — starts hidden
  const palette = document.createElement("div")
  palette.className = "pito-suggestions-palette hidden"
  palette.setAttribute("data-pito--suggestions-target", "palette")
  chatbox.appendChild(palette)

  // Field-wrap
  const fieldWrap = document.createElement("div")
  fieldWrap.className = "pito-chatbox__field-wrap"
  chatbox.appendChild(fieldWrap)

  // Textarea with data-action (real app order: suggestions FIRST)
  const textarea = document.createElement("textarea")
  textarea.setAttribute(
    "data-action",
    "keydown->pito--suggestions#handleKeydown keydown->pito--chat-form#handleKeydown input->pito--suggestions#onInput"
  )
  textarea.setAttribute("data-pito--suggestions-target", "field")
  textarea.setAttribute("data-pito--chat-showcase-target", "field")
  fieldWrap.appendChild(textarea)

  // Showcase ghost (chat-showcase item target)
  const ghost = document.createElement("div")
  ghost.className = "pito-showcase-ghost"
  ghost.setAttribute("data-pito--chat-showcase-target", "item")
  fieldWrap.appendChild(ghost)

  document.body.appendChild(chatbox)
  return { chatbox, textarea, palette, ghost }
}

function arrowUp(el) {
  el.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowUp", bubbles: true, cancelable: true }))
}

function arrowDown(el) {
  el.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }))
}

async function waitForConnect() {
  return new Promise((r) => setTimeout(r, 0))
}

describe("HIST1 reproduce: history works when arrows fire on the TEXTAREA", () => {
  let app

  beforeEach(() => {
    app = Application.start()
    app.register("pito--history", HistoryController)
    app.register("pito--suggestions", SuggestionsController)
    app.register("pito--chat-showcase", ChatShowcaseController)
  })

  afterEach(async () => {
    await app.stop()
    document.body.innerHTML = ""
  })

  it("ArrowUp on textarea (empty field) recalls the most-recent history entry", async () => {
    const { textarea } = buildFullChatbox(JSON.stringify(["last", "first"]))
    await waitForConnect()

    // Real-app scenario: keydown fires on the textarea (not on the chatbox wrapper)
    arrowUp(textarea)

    expect(textarea.value).toBe("last")
  })

  it("ArrowUp on textarea (non-empty field) recalls entries matching the prefix", async () => {
    const { textarea } = buildFullChatbox(JSON.stringify(["/config google", "/games", "/config fx"]))
    await waitForConnect()

    textarea.value = "/conf"
    arrowUp(textarea)

    expect(textarea.value).toBe("/config google")
  })

  // HIST1 regression: applying a slash entry via ArrowUp opens the verb palette,
  // and the NEXT arrow (ArrowDown to return to draft) is consumed by suggestions
  // instead of reaching the history controller. Must fail BEFORE the fix.
  it("ArrowDown after ArrowUp (slash entry) returns to the draft — not caught by palette (HIST1)", async () => {
    const { textarea, palette } = buildFullChatbox(JSON.stringify(["/games"]))
    await waitForConnect()

    textarea.value = ""
    arrowUp(textarea)
    expect(textarea.value).toBe("/games")   // first arrow works

    // After applying "/games", the synthetic input event would open the verb
    // palette (catalog has "games"). The fix must prevent this.
    expect(palette.classList.contains("hidden")).toBe(true)

    // ArrowDown must restore the empty draft, not navigate the palette.
    arrowDown(textarea)
    expect(textarea.value).toBe("")
  })

  it("ArrowUp twice on textarea steps through two slash history entries (HIST1)", async () => {
    const { textarea, palette } = buildFullChatbox(JSON.stringify(["/games", "/sync"]))
    await waitForConnect()

    textarea.value = ""
    arrowUp(textarea)
    expect(textarea.value).toBe("/games")

    // After applying "/games", palette must stay hidden so next arrow reaches history.
    expect(palette.classList.contains("hidden")).toBe(true)

    arrowUp(textarea)
    expect(textarea.value).toBe("/sync")
  })

  it("ArrowUp does nothing when the suggestions palette is visible", async () => {
    const { textarea, palette } = buildFullChatbox(JSON.stringify(["blocked"]))
    await waitForConnect()

    // Manually mark the palette as open (not hidden) to simulate the guard
    palette.classList.remove("hidden")
    textarea.value = "initial"
    arrowUp(textarea)

    expect(textarea.value).toBe("initial")
    palette.classList.add("hidden")
  })
})
