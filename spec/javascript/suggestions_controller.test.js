// spec/javascript/suggestions_controller.test.js
//
// Vitest suite for pito--suggestions Stimulus controller.
//
// Strategy: mount the real controller on a jsdom document using the same
// Stimulus-Application pattern as history_controller.test.js.  We mock
// pito/auth so isAuthenticated() returns a controllable value, and mock
// global fetch for arg-stage palette fetch tests.
//
// COVERAGE
//   Verb-stage palette:
//     - slash catalog filter + Arrow nav + Enter accept + Tab no-op + Esc close
//     - Space dismisses palette (lets space type normally)
//   External hashtag picker (pito:hashtag-picker:open from shift+r):
//     - opens inline palette with handle rows
//     - Arrow nav + Enter accept inserts `#handle ` at position 0
//     - Escape closes without inserting
//     - ignores event when unauthenticated or empty handles
//   Fetched palettes:
//     - hashtag reply-verb palette render (stage:"verb" fetch)
//     - slash /config arg-stage palette render (stage:"verb" fetch)
//   I3 — Enter sends complete slash commands:
//     - exact verb Enter falls through to submit; partial verb accepts palette row
//   Stage classifiers:
//     - _isHashtagReplyVerbStage
//   Misc:
//     - modeFor classification
//     - connect / disconnect lifecycle

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import SuggestionsController from "controllers/pito/suggestions_controller"

// ── Auth mock ────────────────────────────────────────────────────────────────
// The controller imports isAuthenticated from "pito/auth" which reads a DOM element.
// We inject the auth-gate element directly into the document before each test.

function setAuthenticated(value) {
  let gate = document.getElementById("pito-auth-gate")
  if (!gate) {
    gate = document.createElement("div")
    gate.id = "pito-auth-gate"
    document.body.appendChild(gate)
  }
  gate.dataset.authenticated = value ? "true" : "false"
}

// ── Catalog JSON ─────────────────────────────────────────────────────────────

const CATALOG_JSON = JSON.stringify({
  slash: [
    { name: "config",     insert: "/config ",     description: "Configure a provider" },
    { name: "connect",    insert: "/connect ",    description: "Connect a channel" },
    { name: "disconnect", insert: "/disconnect ", description: "Disconnect a channel" },
    { name: "help",       insert: "/help ",       description: "Show help" },
  ],
  hashtag: [],
  chat: [
    { name: "list",       aliases: ["ls"],        insert: "list ",       description: "List entities" },
    { name: "breakdowns", aliases: ["breakdown", "lifetime", "life"], insert: "breakdowns ", description: "Lifetime breakdowns" },
  ],
  vocabularies: {},
})

// ── DOM scaffold ─────────────────────────────────────────────────────────────

function buildScaffold() {
  // Chatbox root — controller attaches here
  const chatbox = document.createElement("div")
  chatbox.id = "pito-chatbox"
  chatbox.setAttribute("data-controller", "pito--suggestions")

  // field-wrap
  const fieldWrap = document.createElement("div")
  fieldWrap.className = "pito-chatbox__field-wrap"
  fieldWrap.style.position = "relative"

  // textarea (field target)
  const textarea = document.createElement("textarea")
  textarea.setAttribute("data-pito--suggestions-target", "field")
  textarea.setAttribute("data-action", [
    "keydown->pito--suggestions#handleKeydown",
    "input->pito--suggestions#onInput",
  ].join(" "))
  fieldWrap.appendChild(textarea)

  // catalog script (catalog target)
  const catalog = document.createElement("script")
  catalog.type = "application/json"
  catalog.setAttribute("data-pito--suggestions-target", "catalog")
  catalog.textContent = CATALOG_JSON

  // palette div (palette target)
  const palette = document.createElement("div")
  palette.className = "pito-suggestions-palette hidden"
  palette.setAttribute("data-pito--suggestions-target", "palette")

  chatbox.appendChild(fieldWrap)
  chatbox.appendChild(catalog)
  chatbox.appendChild(palette)
  document.body.appendChild(chatbox)

  return { chatbox, textarea, palette }
}

// ── Key-event helpers ─────────────────────────────────────────────────────────

function key(el, keyName, opts = {}) {
  el.dispatchEvent(new KeyboardEvent("keydown", { key: keyName, bubbles: true, ...opts }))
}

function input(el, value) {
  el.value = value
  el.dispatchEvent(new Event("input", { bubbles: true }))
}

// ── Test suite ────────────────────────────────────────────────────────────────

describe("pito--suggestions controller", () => {
  let app, textarea, palette, chatbox

  beforeEach(() => {
    setAuthenticated(true)
    app = Application.start()
    app.register("pito--suggestions", SuggestionsController)
    ;({ chatbox, textarea, palette } = buildScaffold())
  })

  afterEach(async () => {
    vi.restoreAllMocks()
    await app.stop()
    document.body.innerHTML = ""
  })

  function waitForConnect() {
    return new Promise((r) => setTimeout(r, 0))
  }

  // ── modeFor ─────────────────────────────────────────────────────────────────

  describe("modeFor", () => {
    let ctrl

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
    })

    it("returns 'slash' for input starting with /", () => {
      expect(ctrl.modeFor("/config", 7)).toBe("slash")
    })

    it("returns 'hashtag' for input starting with #", () => {
      expect(ctrl.modeFor("#handle add", 11)).toBe("hashtag")
    })

    it("returns 'free' for plain text", () => {
      expect(ctrl.modeFor("list upcoming", 13)).toBe("free")
    })

    it("returns 'none' for empty string", () => {
      expect(ctrl.modeFor("", 0)).toBe("none")
    })

    it("returns 'none' for whitespace-only text before cursor", () => {
      expect(ctrl.modeFor("   ", 3)).toBe("none")
    })

    it("uses only the text before cursor (cursor mid-word)", () => {
      // cursor at 3 in "/config" → before = "/co" → still slash
      expect(ctrl.modeFor("/config", 3)).toBe("slash")
    })
  })

  // ── Verb-stage palette — filter + navigation ──────────────────────────────

  describe("verb-stage palette", () => {
    beforeEach(async () => {
      await waitForConnect()
    })

    it("opens the palette when / is typed", async () => {
      input(textarea, "/")
      await waitForConnect()
      expect(palette.classList.contains("hidden")).toBe(false)
    })

    it("filters entries by prefix — '/co' shows config and connect", async () => {
      input(textarea, "/co")
      await waitForConnect()
      const labels = [...palette.querySelectorAll(".pito-suggestions-cmd")].map(el => el.textContent)
      expect(labels).toContain("/config")
      expect(labels).toContain("/connect")
    })

    it("does not show /disconnect for '/co'", async () => {
      input(textarea, "/co")
      await waitForConnect()
      const labels = [...palette.querySelectorAll(".pito-suggestions-cmd")].map(el => el.textContent)
      expect(labels).not.toContain("/disconnect")
    })

    it("first row has is-selected class", async () => {
      input(textarea, "/co")
      await waitForConnect()
      const rows = palette.querySelectorAll(".pito-suggestions-row")
      expect(rows[0].classList.contains("is-selected")).toBe(true)
    })

    it("ArrowDown moves selection to second row", async () => {
      input(textarea, "/co")
      await waitForConnect()
      key(textarea, "ArrowDown")
      const rows = palette.querySelectorAll(".pito-suggestions-row")
      expect(rows[1].classList.contains("is-selected")).toBe(true)
    })

    it("ArrowUp at first row does not go below index 0", async () => {
      input(textarea, "/co")
      await waitForConnect()
      key(textarea, "ArrowUp")
      const rows = palette.querySelectorAll(".pito-suggestions-row")
      expect(rows[0].classList.contains("is-selected")).toBe(true)
    })

    it("Enter accepts the highlighted item and inserts its text", async () => {
      input(textarea, "/co")
      await waitForConnect()
      // First row is selected (index 0 = config or connect depending on catalog order)
      key(textarea, "Enter")
      // After accept, palette should be hidden and field updated
      expect(palette.classList.contains("hidden")).toBe(true)
      expect(textarea.value.startsWith("/")).toBe(true)
    })

    it("Tab does not accept a palette selection (Tab is no longer handled — #9)", async () => {
      input(textarea, "/co")
      await waitForConnect()
      const valueBefore = textarea.value
      key(textarea, "Tab")
      // Tab is not intercepted at all anymore — it never accepts/inserts anything.
      expect(textarea.value).toBe(valueBefore)
    })

    it("Escape closes the palette", async () => {
      input(textarea, "/co")
      await waitForConnect()
      key(textarea, "Escape")
      expect(palette.classList.contains("hidden")).toBe(true)
    })

    it("Space dismisses the palette", async () => {
      input(textarea, "/co")
      await waitForConnect()
      // Space key without preventDefault — dispatch a space key event
      key(textarea, " ")
      expect(palette.classList.contains("hidden")).toBe(true)
    })

    it("closes the palette when no entries match", async () => {
      input(textarea, "/zzz")
      await waitForConnect()
      expect(palette.classList.contains("hidden")).toBe(true)
    })

    it("Tab with no palette open does nothing (not intercepted, no insertion — #9)", async () => {
      input(textarea, "list upcoming")
      await waitForConnect()
      const before = textarea.value
      key(textarea, "Tab")
      // Tab is no longer handled — free input has no palette and no completion.
      expect(textarea.value).toBe(before)
      expect(palette.classList.contains("hidden")).toBe(true)
    })
  })

  // ── External hashtag picker (shift+r with >1 live handle) ───────────────
  //
  // When chat_form dispatches `pito:hashtag-picker:open` with an array of handles,
  // suggestions_controller opens the inline suggestions palette (above the chatbox)
  // pre-populated with those handles. Accepting inserts `#<handle> ` at position 0
  // of the (empty) input — same UX as the slash palette.

  describe("external hashtag picker via pito:hashtag-picker:open", () => {
    let ctrl

    function openHashtagPicker(handles) {
      document.dispatchEvent(new CustomEvent("pito:hashtag-picker:open", {
        detail: { handles }
      }))
    }

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
    })

    it("opens the inline palette with one row per handle", async () => {
      openHashtagPicker(["kappa-5874", "doomguy-21"])

      expect(palette.classList.contains("hidden")).toBe(false)
      const rows = palette.querySelectorAll(".pito-suggestions-row")
      expect(rows.length).toBe(2)
    })

    it("displays handles with # trigger glyph", async () => {
      openHashtagPicker(["kappa-5874", "doomguy-21"])

      const cmds = [...palette.querySelectorAll(".pito-suggestions-cmd")].map(el => el.textContent)
      expect(cmds).toContain("#kappa-5874")
      expect(cmds).toContain("#doomguy-21")
    })

    it("Enter accepts first handle and inserts `#handle ` at position 0", async () => {
      textarea.value = ""
      textarea.selectionStart = textarea.selectionEnd = 0
      openHashtagPicker(["kappa-5874", "doomguy-21"])

      ctrl.handleKeydown(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))

      expect(textarea.value).toBe("#kappa-5874 ")
    })

    it("palette closes after accepting", async () => {
      openHashtagPicker(["kappa-5874", "doomguy-21"])

      ctrl.handleKeydown(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))

      expect(palette.classList.contains("hidden")).toBe(true)
    })

    it("ArrowDown + Enter accepts the second handle", async () => {
      textarea.value = ""
      textarea.selectionStart = textarea.selectionEnd = 0
      openHashtagPicker(["kappa-5874", "doomguy-21"])

      ctrl.handleKeydown(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }))
      ctrl.handleKeydown(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))

      expect(textarea.value).toBe("#doomguy-21 ")
    })

    it("Escape closes the picker without inserting", async () => {
      textarea.value = ""
      openHashtagPicker(["kappa-5874", "doomguy-21"])

      ctrl.handleKeydown(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }))

      expect(palette.classList.contains("hidden")).toBe(true)
      expect(textarea.value).toBe("")
    })

    it("ignores the event when unauthenticated", async () => {
      setAuthenticated(false)
      ctrl._authenticated = false

      openHashtagPicker(["kappa-5874", "doomguy-21"])

      expect(palette.classList.contains("hidden")).toBe(true)
    })

    it("ignores the event when handles array is empty", async () => {
      openHashtagPicker([])

      expect(palette.classList.contains("hidden")).toBe(true)
    })

    it("three handles produce three rows", async () => {
      openHashtagPicker(["alpha-1", "bravo-2", "charlie-3"])

      const rows = palette.querySelectorAll(".pito-suggestions-row")
      expect(rows.length).toBe(3)
    })
  })

  // ── Hashtag reply-verb palette (stage:"verb" fetch) ──────────────────────
  //
  // Regression: typing `#<handle> ` for a follow-up-able message lands at the
  // reply-VERB stage. Even though a space follows the handle (which trips the
  // arg-stage space heuristic), the engine tags the response stage:"verb" and the
  // controller must render the WHOLE allowed-verb list as a selectable palette —
  // not just menu_items[0] as a single inline ghost. This is the bug fix.

  describe("hashtag reply-verb palette (stage:'verb' fetch)", () => {
    let ctrl

    const VERB_RESPONSE = () => ({
      ok: true,
      json: async () => ({
        mode: "hashtag",
        stage: "verb",
        menu_items: [
          { label: "show",     insert: "show ",     description: "" },
          { label: "with",     insert: "with ",     description: "" },
          { label: "without",  insert: "without ",  description: "" },
          { label: "shinies",  insert: "shinies ",  description: "" },
          { label: "schedule", insert: "schedule ", description: "" },
        ],
        ghost: { complete_current: "show", next_hint: "" },
      }),
    })

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
      ctrl._mode = "hashtag"
    })

    it("renders a MULTI-item palette (not a single ghost) for `#handle `", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(VERB_RESPONSE()))
      await ctrl._fetchArgSuggestions("#kappa-5874 ", 12)

      expect(palette.classList.contains("hidden")).toBe(false)
      const rows = palette.querySelectorAll(".pito-suggestions-row")
      expect(rows.length).toBe(5)
    })

    it("surfaces with/without/shinies/schedule (the verbs the old ghost hid)", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(VERB_RESPONSE()))
      await ctrl._fetchArgSuggestions("#kappa-5874 ", 12)

      const labels = [...palette.querySelectorAll(".pito-suggestions-cmd")].map(el => el.textContent)
      expect(labels).toEqual(expect.arrayContaining(["show", "with", "without", "shinies", "schedule"]))
    })

    it("shows verb labels verbatim — no leading '#' glyph", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(VERB_RESPONSE()))
      await ctrl._fetchArgSuggestions("#kappa-5874 ", 12)

      const labels = [...palette.querySelectorAll(".pito-suggestions-cmd")].map(el => el.textContent)
      expect(labels).toContain("with")
      expect(labels).not.toContain("#with")
    })

    it("Enter accepts the highlighted verb → `#handle <verb> `", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(VERB_RESPONSE()))
      textarea.value = "#kappa-5874 "
      textarea.selectionStart = textarea.selectionEnd = 12
      await ctrl._fetchArgSuggestions("#kappa-5874 ", 12)

      // First row ("show") is selected by default.
      ctrl.handleKeydown(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
      expect(textarea.value).toBe("#kappa-5874 show ")
    })

    it("ArrowDown + Enter inserts the second verb token", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(VERB_RESPONSE()))
      textarea.value = "#kappa-5874 "
      textarea.selectionStart = textarea.selectionEnd = 12
      await ctrl._fetchArgSuggestions("#kappa-5874 ", 12)

      ctrl.handleKeydown(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true }))
      ctrl.handleKeydown(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
      expect(textarea.value).toBe("#kappa-5874 with ")
    })

    it("replaces a partially-typed verb token (`#handle wi` → `#handle with `)", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          mode: "hashtag",
          stage: "verb",
          menu_items: [
            { label: "with",    insert: "with ",    description: "" },
            { label: "without", insert: "without ", description: "" },
          ],
          ghost: { complete_current: "th", next_hint: "" },
        }),
      }))
      textarea.value = "#kappa-5874 wi"
      textarea.selectionStart = textarea.selectionEnd = 14
      await ctrl._fetchArgSuggestions("#kappa-5874 wi", 14)

      ctrl.handleKeydown(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
      expect(textarea.value).toBe("#kappa-5874 with ")
    })

    it("arg-stage (stage:'arg') keeps the palette CLOSED", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          mode: "hashtag",
          stage: "arg",
          menu_items: [{ label: "channel", insert: "channel ", description: "" }],
          ghost: { complete_current: "channel", next_hint: "" },
        }),
      }))
      await ctrl._fetchArgSuggestions("#kappa-5874 with ", 17)
      expect(palette.classList.contains("hidden")).toBe(true)
    })
  })

  // ── Slash /config arg-stage palette (stage:"verb" fetch) ─────────────────
  //
  // Restoration: typing `/config ` (and `/config <provider> `) lands at the slash
  // ARG stage (a space follows the verb, tripping _isArgStage) — but the engine
  // tags the response stage:"verb" so the client must render the provider/key
  // list as a browsable PALETTE, not just the top hit as a single inline ghost.

  describe("slash /config arg-stage palette (stage:'verb' fetch)", () => {
    let ctrl

    const CONFIG_PROVIDERS = () => ({
      ok: true,
      json: async () => ({
        mode: "slash",
        stage: "verb",
        menu_items: [
          { label: "google",  insert: "google ",  description: "" },
          { label: "voyage",  insert: "voyage ",  description: "" },
          { label: "igdb",    insert: "igdb ",    description: "" },
          { label: "webhook", insert: "webhook ", description: "" },
        ],
        ghost: { complete_current: "", next_hint: "" },
      }),
    })

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
      ctrl._mode = "slash"
    })

    it("classifies '/config ' as a slash-config arg stage", () => {
      expect(ctrl._isSlashConfigArgStage("/config ", 8)).toBe(true)
      expect(ctrl._isSlashConfigArgStage("/config google ", 15)).toBe(true)
    })

    it("does NOT classify other slash args as config arg stage", () => {
      expect(ctrl._isSlashConfigArgStage("/games import x", 14)).toBe(false)
      expect(ctrl._isSlashConfigArgStage("/disconnect @al", 15)).toBe(false)
      expect(ctrl._isSlashConfigArgStage("/config", 7)).toBe(false) // still typing verb
    })

    it("renders a MULTI-item palette (not a single ghost) for '/config '", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(CONFIG_PROVIDERS()))
      await ctrl._fetchArgSuggestions("/config ", 8)

      expect(palette.classList.contains("hidden")).toBe(false)
      const rows = palette.querySelectorAll(".pito-suggestions-row")
      expect(rows.length).toBe(4)
    })

    it("surfaces the provider names in the palette", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(CONFIG_PROVIDERS()))
      await ctrl._fetchArgSuggestions("/config ", 8)

      const labels = [...palette.querySelectorAll(".pito-suggestions-cmd")].map(el => el.textContent)
      expect(labels).toEqual(expect.arrayContaining(["google", "voyage", "igdb", "webhook"]))
    })

    it("Enter accepts the highlighted provider → '/config google '", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(CONFIG_PROVIDERS()))
      textarea.value = "/config "
      textarea.selectionStart = textarea.selectionEnd = 8
      await ctrl._fetchArgSuggestions("/config ", 8)

      // First row ("google") is selected by default.
      ctrl.handleKeydown(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
      expect(textarea.value).toBe("/config google ")
    })

    // ── I3: trailing-space gate — a complete token with NO trailing space must
    // NOT pop the palette, so Enter can SEND the read/default version. ──────────
    it("does NOT classify a complete token with no trailing space as arg-stage", () => {
      expect(ctrl._isSlashConfigArgStage("/config google", 14)).toBe(false)
      expect(ctrl._isSlashConfigArgStage("/config goo", 11)).toBe(false)
      expect(ctrl._isSlashConfigArgStage("/config", 7)).toBe(false)
    })

    it("keeps the palette CLOSED for a complete token with no trailing space", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(CONFIG_PROVIDERS()))
      textarea.value = "/config google"
      textarea.selectionStart = textarea.selectionEnd = 14
      await ctrl._fetchArgSuggestions("/config google", 14)
      // stage:"verb" came back, but no trailing space → palette must stay hidden
      // so Enter submits the bare command.
      expect(palette.classList.contains("hidden")).toBe(true)
    })
  })

  // ── I3: verb-stage Enter sends a complete slash command ───────────────────
  // A complete command with no trailing space ("/connect", "/config") is
  // Enter-sendable; a partial verb ("/conn") still accepts the palette row.
  describe("verb-stage Enter sends complete slash commands (I3)", () => {
    let ctrl

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
      ctrl._mode = "slash"
    })

    it("_isExactCompleteSlashVerb: true for an exact command, false for a partial", () => {
      textarea.value = "/connect"; textarea.selectionStart = textarea.selectionEnd = 8
      expect(ctrl._isExactCompleteSlashVerb()).toBe(true)
      textarea.value = "/config"; textarea.selectionStart = textarea.selectionEnd = 7
      expect(ctrl._isExactCompleteSlashVerb()).toBe(true)
      textarea.value = "/conn"; textarea.selectionStart = textarea.selectionEnd = 5
      expect(ctrl._isExactCompleteSlashVerb()).toBe(false)
    })

    it("_isExactCompleteSlashVerb: false once a space follows the verb", () => {
      textarea.value = "/config "; textarea.selectionStart = textarea.selectionEnd = 8
      expect(ctrl._isExactCompleteSlashVerb()).toBe(false)
    })

    it("Enter on an exact command closes the palette and falls through to submit", () => {
      textarea.value = "/connect"; textarea.selectionStart = textarea.selectionEnd = 8
      ctrl._refreshVerbPalette("/connect", 8)
      expect(ctrl._paletteOpen).toBe(true)

      const ev = new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })
      ctrl.handleKeydown(ev)

      expect(ctrl._paletteOpen).toBe(false)     // palette closed
      expect(ev.defaultPrevented).toBe(false)   // Enter not swallowed → form submits
      expect(textarea.value).toBe("/connect")   // command NOT mutated by a palette accept
    })

    it("Enter on a partial verb still accepts the palette selection", () => {
      textarea.value = "/conn"; textarea.selectionStart = textarea.selectionEnd = 5
      ctrl._refreshVerbPalette("/conn", 5)
      expect(ctrl._paletteOpen).toBe(true)

      const ev = new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })
      ctrl.handleKeydown(ev)

      expect(ev.defaultPrevented).toBe(true)    // palette intercepted Enter
      expect(textarea.value).toBe("/connect ")  // completed to the full command
    })
  })

  // ── _isHashtagReplyVerbStage classification ──────────────────────────────

  describe("_isHashtagReplyVerbStage", () => {
    let ctrl

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
    })

    it("true right after the handle space (`#h `)", () => {
      expect(ctrl._isHashtagReplyVerbStage("#h ", 3)).toBe(true)
    })

    it("true while typing the verb (`#h sh`)", () => {
      expect(ctrl._isHashtagReplyVerbStage("#h sh", 5)).toBe(true)
    })

    it("false once the verb is finalised by a space (`#h show `)", () => {
      expect(ctrl._isHashtagReplyVerbStage("#h show ", 8)).toBe(false)
    })

    it("false while still typing the handle (no space yet)", () => {
      expect(ctrl._isHashtagReplyVerbStage("#han", 4)).toBe(false)
    })

    it("false for slash input", () => {
      expect(ctrl._isHashtagReplyVerbStage("/config ", 8)).toBe(false)
    })
  })

  // ── Hashtag reply-ARG palette (G26.5) ────────────────────────────────────
  //
  // Regression: `#<handle> with ` fetched the column menu (the engine tags it
  // stage:"verb") but the stage:"verb" render gate only covered the reply-VERB
  // and /config positions — the fetched items were discarded and the palette
  // never opened for reply ARGUMENTS (columns, sort keys, metrics, row ids).

  describe("hashtag reply-ARG palette (stage:'verb' fetch at a fresh arg token)", () => {
    let ctrl

    const ARG_RESPONSE = () => ({
      ok: true,
      json: async () => ({
        mode: "hashtag",
        stage: "verb",
        menu_items: [
          { label: "category", insert: "category ", description: "" },
          { label: "duration", insert: "duration ", description: "" },
          { label: "views",    insert: "views ",    description: "" },
        ],
        ghost: { complete_current: "", next_hint: "" },
      }),
    })

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
      ctrl._mode = "hashtag"
    })

    it("renders the argument palette for `#handle with ` (fresh token)", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(ARG_RESPONSE()))
      await ctrl._fetchArgSuggestions("#kappa-5874 with ", 17)

      expect(palette.classList.contains("hidden")).toBe(false)
      const rows = palette.querySelectorAll(".pito-suggestions-row")
      expect(rows.length).toBe(3)
    })

    it("keeps the palette CLOSED mid-token (`#handle with cat`) so Enter sends", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(ARG_RESPONSE()))
      await ctrl._fetchArgSuggestions("#kappa-5874 with cat", 20)

      expect(palette.classList.contains("hidden")).toBe(true)
    })

    it("_isHashtagReplyArgStage: true at a fresh arg token, false elsewhere", () => {
      expect(ctrl._isHashtagReplyArgStage("#h with ", 8)).toBe(true)
      expect(ctrl._isHashtagReplyArgStage("#h with cat, ", 13)).toBe(true)
      expect(ctrl._isHashtagReplyArgStage("#h with cat", 11)).toBe(false)
      expect(ctrl._isHashtagReplyArgStage("#h ", 3)).toBe(false)      // verb stage
      expect(ctrl._isHashtagReplyArgStage("#han", 4)).toBe(false)     // handle stage
      expect(ctrl._isHashtagReplyArgStage("/config ", 8)).toBe(false) // slash
    })
  })

  // ── FREE-mode chat-verb argument palette (G31) ───────────────────────────
  //
  // Regression: `list ` (free input) fetched the noun menu (stage:"verb":
  // channels/games/vids) but no gate rendered free-mode items — discarded,
  // palette never opened for chat verbs' arguments.

  describe("free-mode chat-verb argument palette (stage:'verb' fetch)", () => {
    let ctrl

    const FREE_RESPONSE = () => ({
      ok: true,
      json: async () => ({
        mode: "free",
        stage: "verb",
        menu_items: [
          { label: "channels", insert: "channels ", description: "" },
          { label: "games",    insert: "games ",    description: "" },
          { label: "vids",     insert: "vids ",     description: "" },
        ],
        ghost: { complete_current: "", next_hint: "" },
      }),
    })

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
      ctrl._mode = "free"
    })

    it("renders the argument palette for `list ` (fresh token)", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(FREE_RESPONSE()))
      await ctrl._fetchArgSuggestions("list ", 5)

      expect(palette.classList.contains("hidden")).toBe(false)
      const rows = palette.querySelectorAll(".pito-suggestions-row")
      expect(rows.length).toBe(3)
    })

    it("keeps the palette CLOSED mid-token (`list ga`) so Enter sends", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(FREE_RESPONSE()))
      await ctrl._fetchArgSuggestions("list ga", 7)

      expect(palette.classList.contains("hidden")).toBe(true)
    })

    it("_isFreeArgFreshToken: fresh free token only", () => {
      expect(ctrl._isFreeArgFreshToken("list ", 5)).toBe(true)
      expect(ctrl._isFreeArgFreshToken("show game 5 with ", 17)).toBe(true)
      expect(ctrl._isFreeArgFreshToken("list ga", 7)).toBe(false)
      expect(ctrl._isFreeArgFreshToken("   ", 3)).toBe(false)
      expect(ctrl._isFreeArgFreshToken("#h with ", 8)).toBe(false)
      expect(ctrl._isFreeArgFreshToken("/config ", 8)).toBe(false)
    })
  })

  // ── G75: free-mode VERB-stage palette (1.1.0) ────────────────────────────
  //
  // The FIRST word of a chat message is a verb in progress — the palette
  // stays open WHILE TYPING mid-token (slash-style discovery, unlike the
  // arg stage's fresh-token rule), and Enter on an exact-complete verb —
  // canonical OR alias — sends instead of accepting a row.

  describe("free-mode VERB-stage palette (G75)", () => {
    let ctrl

    const VERB_RESPONSE = () => ({
      ok: true,
      json: async () => ({
        mode: "free",
        stage: "verb",
        menu_items: [
          { label: "link", insert: "link ", description: "" },
          { label: "list", insert: "list ", description: "" },
        ],
        ghost: { complete_current: "", next_hint: "" },
      }),
    })

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
      ctrl._mode = "free"
    })

    it("renders the verb palette MID-TOKEN (`li`) — discovery like slash verbs", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(VERB_RESPONSE()))
      textarea.value = "li"; textarea.selectionStart = textarea.selectionEnd = 2
      await ctrl._fetchArgSuggestions("li", 2)

      expect(palette.classList.contains("hidden")).toBe(false)
      expect(palette.querySelectorAll(".pito-suggestions-row").length).toBe(2)
    })

    it("_isFreeVerbStage: first word only, free mode only", () => {
      expect(ctrl._isFreeVerbStage("l", 1)).toBe(true)
      expect(ctrl._isFreeVerbStage("lis", 3)).toBe(true)
      expect(ctrl._isFreeVerbStage("list ", 5)).toBe(false)
      expect(ctrl._isFreeVerbStage("list ga", 7)).toBe(false)
      expect(ctrl._isFreeVerbStage("#h l", 4)).toBe(false)
      expect(ctrl._isFreeVerbStage("/con", 4)).toBe(false)
      expect(ctrl._isFreeVerbStage("  ", 2)).toBe(false)
    })

    it("_isExactCompleteChatVerb: canonical name, every alias, never past a space", () => {
      textarea.value = "list"; textarea.selectionStart = textarea.selectionEnd = 4
      expect(ctrl._isExactCompleteChatVerb()).toBe(true)
      textarea.value = "ls"; textarea.selectionStart = textarea.selectionEnd = 2
      expect(ctrl._isExactCompleteChatVerb()).toBe(true)
      textarea.value = "lifetime"; textarea.selectionStart = textarea.selectionEnd = 8
      expect(ctrl._isExactCompleteChatVerb()).toBe(true)
      textarea.value = "lis"; textarea.selectionStart = textarea.selectionEnd = 3
      expect(ctrl._isExactCompleteChatVerb()).toBe(false)
      textarea.value = "list "; textarea.selectionStart = textarea.selectionEnd = 5
      expect(ctrl._isExactCompleteChatVerb()).toBe(false)
      textarea.value = "/list"; textarea.selectionStart = textarea.selectionEnd = 5
      expect(ctrl._isExactCompleteChatVerb()).toBe(false)
    })

    it("Enter on an exact chat verb (alias incl.) closes the palette and falls through to submit", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(VERB_RESPONSE()))
      textarea.value = "ls"; textarea.selectionStart = textarea.selectionEnd = 2
      await ctrl._fetchArgSuggestions("ls", 2)
      expect(ctrl._paletteOpen).toBe(true)

      const ev = new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })
      textarea.dispatchEvent(ev)

      expect(ctrl._paletteOpen).toBe(false)
      expect(ev.defaultPrevented).toBe(false)   // falls through → chat-form submits
      expect(textarea.value).toBe("ls")          // row NOT accepted
    })

    it("Enter mid-token accepts the highlighted row (discovery preserved)", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue(VERB_RESPONSE()))
      textarea.value = "li"; textarea.selectionStart = textarea.selectionEnd = 2
      await ctrl._fetchArgSuggestions("li", 2)
      expect(ctrl._paletteOpen).toBe(true)

      const ev = new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })
      textarea.dispatchEvent(ev)

      expect(ev.defaultPrevented).toBe(true)     // palette consumed Enter
      expect(textarea.value).toBe("link ")       // first row accepted
    })
  })

  // ── Lifecycle ────────────────────────────────────────────────────────────

  describe("lifecycle", () => {
    it("controller connects and initialises without error", async () => {
      await waitForConnect()
      const ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
      expect(ctrl).toBeTruthy()
      expect(ctrl._mode).toBe("none")
      expect(ctrl._paletteOpen).toBe(false)
    })

    it("disconnect clears palette and removes event listeners", async () => {
      await waitForConnect()
      const ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
      // Should not throw on disconnect
      expect(() => ctrl.disconnect()).not.toThrow()
    })
  })
})
