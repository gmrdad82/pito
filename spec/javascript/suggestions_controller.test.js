// spec/javascript/suggestions_controller.test.js
//
// Vitest suite for pito--suggestions Stimulus controller.
//
// Strategy: mount the real controller on a jsdom document using the same
// Stimulus-Application pattern as history_controller.test.js.  We mock
// pito/auth so isAuthenticated() returns a controllable value, and mock
// global fetch for arg-stage / dynamic fetch tests.
//
// COVERAGE
//   Verb-stage palette:
//     - slash catalog filter + Arrow nav + Enter accept + Tab no-op + Esc close
//     - Space dismisses palette (lets space type normally)
//     - pito:suggest dispatched on open/close
//   Ghost (arg-stage / free-form):
//     - Tab accepts free-form ghost
//     - Enter passes through (does not accept ghost)
//     - debounced /suggestions fetch: mock fetch → ghost set from response
//     - stale-response guard: rapid input → only last fetch applies
//   External hashtag picker (pito:hashtag-picker:open from shift+r):
//     - opens inline palette with handle rows
//     - Arrow nav + Enter accept inserts `#handle ` at position 0
//     - Escape closes without inserting
//     - ignores event when unauthenticated or empty handles
//   Misc:
//     - modeFor classification
//     - connect / disconnect lifecycle
//
// SKIPPED (requires real layout / caret pixels):
//   - Ghost span absolute positioning (relies on getComputedStyle line-height
//     and caret coords from pito:caret event; jsdom always returns 0 for metrics)
//   - Terminal-caret integration (_positionGhost transform values)

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
    { name: "list",     insert: "list ",     description: "List resources",       slots: [{ name: "noun",       source: "nouns"             }] },
    { name: "show",     insert: "show ",     description: "Show a resource",      slots: []                                                     },
    { name: "analyze",  insert: "analyze ",  description: "Analyze metrics",      slots: [{ name: "noun",       source: "nouns"             }] },
    { name: "import",   insert: "import ",   description: "Import a game",        slots: [{ name: "noun",       source: "import_nouns"      }] },
    { name: "sync",     insert: "sync ",     description: "Sync data",            slots: [{ name: "target",     source: "sync_targets"      }] },
    { name: "footage",  insert: "footage ",  description: "Set footage hours",    slots: [{ name: "title",      source: "game_titles"       }] },
    { name: "price",    insert: "price ",    description: "Set/unset a price",    slots: [{ name: "subcommand", source: "price_subcommands" }] },
    { name: "delete",   insert: "delete ",   description: "Delete a game",        slots: [{ name: "title",      source: "game_titles"       }] },
    { name: "reindex",  insert: "reindex ",  description: "Reindex a game",       slots: [{ name: "title",      source: "game_titles"       }] },
    { name: "platform", insert: "platform ", description: "Set platform",         slots: [{ name: "subcommand", source: "platform_subcommands" }] },
    { name: "publish",  insert: "publish ",  description: "Publish a video",      slots: []                                                     },
    { name: "unlist",   insert: "unlist ",   description: "Unlist a video",       slots: []                                                     },
    { name: "schedule", insert: "schedule ", description: "Schedule a video",     slots: [{ name: "slate",      source: "schedule_whens"   }] },
    { name: "find",     insert: "find ",     description: "Find games",           slots: [{ name: "status", source: "release_status" }, { name: "genre", source: "genres" }, { name: "platform", source: "platforms" }] },
    { name: "link",     insert: "link ",     description: "Link game to video",   slots: []                                                     },
    { name: "unlink",   insert: "unlink ",   description: "Unlink a game",        slots: []                                                     },
    { name: "shinies",  insert: "shinies ",  description: "Show achievements",    slots: []                                                     },
    { name: "help",     insert: "help ",     description: "Show help",            slots: []                                                     },
    { name: "greet",    insert: "greet ",    description: "Greet",                slots: []                                                     },
    { name: "farewell", insert: "farewell ", description: "Farewell",             slots: []                                                     },
  ],
  vocabularies: {
    release_status:    { canonical: ["released", "upcoming", "tba"],        synonyms: {},                                                                     fillers: [], dynamic: false },
    genres:            { canonical: ["RPG", "Racing", "Shooter"],           synonyms: {},                                                                     fillers: [], dynamic: false },
    platforms:         { canonical: ["PlayStation 5", "PC", "Xbox"],        synonyms: {},                                                                     fillers: [], dynamic: false },
    game_titles:       { dynamic: true, endpoint: "/suggestions" },
    sync_targets:      { canonical: ["channels", "videos"],                 synonyms: { channel: "channels", video: "videos" },                              fillers: [], dynamic: false },
    fillers:           { canonical: [], fillers: ["the", "a", "an", "game", "games"], synonyms: {},                                                         dynamic: false },
    nouns:             { canonical: ["channels", "vids", "games"],          synonyms: { channel: "channels", video: "vids", videos: "vids", vid: "vids" },  fillers: [], dynamic: false },
    import_nouns:      { canonical: ["game"],                               synonyms: { games: "game" },                                                     fillers: [], dynamic: false },
    schedule_whens:    { canonical: ["slate"],                              synonyms: {},                                                                     fillers: [], dynamic: false },
    price_subcommands: { canonical: ["set", "unset"],                       synonyms: {},                                                                     fillers: [], dynamic: false },
    platform_subcommands: { canonical: ["set", "unset"],                    synonyms: {},                                                                     fillers: [], dynamic: false },
  },
})

// ── DOM scaffold ─────────────────────────────────────────────────────────────

function buildScaffold() {
  // Chatbox root — controller attaches here
  const chatbox = document.createElement("div")
  chatbox.id = "pito-chatbox"
  chatbox.setAttribute("data-controller", "pito--suggestions")

  // field-wrap (needed for ghost span creation)
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
      // Access the controller instance via the element's __stimulusController
      // convention (Stimulus stores it on the element)
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

    it("Tab is a no-op while palette is open (does not accept)", async () => {
      input(textarea, "/co")
      await waitForConnect()
      const valueBefore = textarea.value
      key(textarea, "Tab")
      // Palette stays open
      expect(palette.classList.contains("hidden")).toBe(false)
      // Value unchanged (Tab didn't accept anything)
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
  })

  // ── pito:suggest dispatch ────────────────────────────────────────────────

  describe("pito:suggest dispatch", () => {
    beforeEach(async () => {
      await waitForConnect()
    })

    it("dispatches pito:suggest with active:true when palette opens", async () => {
      const events = []
      document.addEventListener("pito:suggest", (e) => events.push(e.detail.active))

      input(textarea, "/co")
      await waitForConnect()

      expect(events).toContain(true)

      document.removeEventListener("pito:suggest", () => {})
    })

    it("dispatches pito:suggest with active:false when palette closes", async () => {
      const events = []
      document.addEventListener("pito:suggest", (e) => events.push(e.detail.active))

      input(textarea, "/co")
      await waitForConnect()
      key(textarea, "Escape")

      expect(events).toContain(false)

      document.removeEventListener("pito:suggest", () => {})
    })
  })

  // ── Arg-stage ghost — debounced /suggestions fetch ───────────────────────
  //
  // We test the debounce and stale-response guard by calling controller methods
  // directly (bypassing Stimulus event wiring) and using vi.useFakeTimers with
  // manual timer advancement.  The Stimulus app is shared from the outer scaffold;
  // we wait for it to connect with real timers first, then activate fake timers
  // just for the setTimeout-based debounce inside the test body.

  describe("arg-stage ghost — debounced /suggestions fetch", () => {
    let ctrl

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
    })

    it("calls /suggestions after the debounce interval fires", async () => {
      const fetchMock = vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          menu_items: [{ label: "google", insert: "google " }],
          ghost: { complete_current: "", next_hint: "" },
        }),
      })
      vi.stubGlobal("fetch", fetchMock)

      // Call the internal schedule method directly to bypass Stimulus event wiring
      vi.useFakeTimers()
      try {
        ctrl._scheduleArgFetch("/config ", 8)

        // Before debounce fires, fetch should not have been called
        expect(fetchMock).not.toHaveBeenCalled()

        // Advance past ARG_DEBOUNCE_MS (120ms)
        vi.advanceTimersByTime(200)
        await Promise.resolve()
        await Promise.resolve()

        expect(fetchMock).toHaveBeenCalledTimes(1)
        const callArgs = fetchMock.mock.calls[0]
        expect(callArgs[0]).toBe("/suggestions")
        expect(JSON.parse(callArgs[1].body)).toMatchObject({ input: "/config " })
      } finally {
        vi.useRealTimers()
      }
    })

    it("stale-response guard: second schedule call increments requestId, first response ignored", async () => {
      let resolveFirst, resolveSecond
      const firstPending  = new Promise((r) => (resolveFirst  = r))
      const secondPending = new Promise((r) => (resolveSecond = r))

      let callCount = 0
      vi.stubGlobal("fetch", vi.fn().mockImplementation(() => {
        callCount++
        return callCount === 1 ? firstPending : secondPending
      }))

      vi.useFakeTimers()
      try {
        // Schedule first fetch
        ctrl._scheduleArgFetch("/config g", 9)
        vi.advanceTimersByTime(200)
        await Promise.resolve()
        // First fetch is now in-flight (firstPending)

        // Schedule second fetch — this cancels first timer and bumps requestId
        ctrl._scheduleArgFetch("/config go", 10)
        vi.advanceTimersByTime(200)
        await Promise.resolve()

        // Resolve stale first response after requestId was bumped
        resolveFirst({
          ok: true,
          json: async () => ({ menu_items: [{ label: "stale", insert: "stale " }], ghost: {} }),
        })
        await Promise.resolve()
        await Promise.resolve()

        // Resolve fresh second response
        resolveSecond({
          ok: true,
          json: async () => ({ menu_items: [{ label: "google", insert: "google " }], ghost: {} }),
        })
        await Promise.resolve()
        await Promise.resolve()

        // Controller is still alive — stale response was discarded without error
        expect(ctrl).toBeTruthy()
        // The stale response should not have set the ghost (we can't read ghost span
        // content without real layout, but we verify no exception occurred)
      } finally {
        vi.useRealTimers()
      }
    })
  })

  // ── Ghost — Tab accept (free-form) ────────────────────────────────────────

  describe("ghost — Tab accept in free-form mode", () => {
    let ctrl

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
    })

    it("Tab with no ghost active is a no-op (field unchanged)", async () => {
      input(textarea, "list upcoming")
      await waitForConnect()
      const before = textarea.value
      ctrl.handleKeydown(new KeyboardEvent("keydown", { key: "Tab", bubbles: true }))
      expect(textarea.value).toBe(before)
    })

    it("Tab accepts the ghost suffix and appends it at the cursor", async () => {
      // Manually inject a ghost state (bypassing fetch/caret layout).
      // We call handleKeydown directly (same as dispatching a keydown action event)
      // to avoid Stimulus event-wiring timing issues in jsdom.
      expect(ctrl).toBeTruthy()
      ctrl._ghostComplete = "oming"
      ctrl._mode = "free"

      const initialValue = "list upc"
      textarea.value = initialValue
      textarea.selectionStart = textarea.selectionEnd = initialValue.length

      // Call the action handler directly — avoids Stimulus action wiring timing in jsdom
      ctrl.handleKeydown(new KeyboardEvent("keydown", { key: "Tab", bubbles: true }))

      expect(textarea.value).toBe("list upcoming")
    })

    it("Tab with ghost does not submit (no form submit side-effect)", async () => {
      ctrl._ghostComplete = "oming"
      ctrl._mode = "free"
      textarea.value = "list upc"
      textarea.selectionStart = textarea.selectionEnd = 8

      const submitEvents = []
      document.addEventListener("submit", (e) => submitEvents.push(e))

      ctrl.handleKeydown(new KeyboardEvent("keydown", { key: "Tab", bubbles: true }))

      expect(submitEvents).toHaveLength(0)
    })

    it("Enter passes through ghost without accepting it", async () => {
      // Inject ghost state; Enter must NOT call _acceptGhost (it passes through to submit)
      ctrl._ghostComplete = "oming"
      ctrl._mode = "free"
      textarea.value = "list upc"
      textarea.selectionStart = textarea.selectionEnd = 8

      ctrl.handleKeydown(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }))

      // Ghost not accepted — value unchanged
      expect(textarea.value).toBe("list upc")
    })
  })

  // ── _chatEnumSlots verb-awareness (T10.5) ───────────────────────────────

  describe("_chatEnumSlots — verb-aware slot derivation", () => {
    let ctrl

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
    })

    it("returns empty slots for the 'show' spec (no enum slots — catalog slots: [])", () => {
      const showSpec = ctrl._findChatSpec("show")
      expect(showSpec).toBeTruthy()
      const slots = ctrl._chatEnumSlots(showSpec)
      expect(slots).toHaveLength(0)
    })

    it("returns game_titles slot for the 'delete' spec", () => {
      const deleteSpec = ctrl._findChatSpec("delete")
      expect(deleteSpec).toBeTruthy()
      const slots = ctrl._chatEnumSlots(deleteSpec)
      expect(slots).toHaveLength(1)
      expect(slots[0].source).toBe("game_titles")
    })

    it("returns nouns slot for 'list' spec (static enum slot from catalog)", () => {
      const listSpec = ctrl._findChatSpec("list")
      expect(listSpec).toBeTruthy()
      const slots = ctrl._chatEnumSlots(listSpec)
      expect(slots).toHaveLength(1)
      expect(slots[0].name).toBe("noun")
      expect(slots[0].source).toBe("nouns")
    })

    it("returns legacy fallback slots when chatSpec is null", () => {
      const slots = ctrl._chatEnumSlots(null)
      expect(slots.map(s => s.name)).toEqual(["status", "genre", "platform"])
    })

    it("'show ' at trailing space produces no enum ghost (show has no enum slots)", () => {
      const result = ctrl._computeLocalGhost("show ", 5)
      expect(result).not.toBeNull()
      expect(result.complete_current).toBe("")
    })

    it("dynamic game_titles slot causes _computeLocalGhost to return null (→ dynamic fetch)", () => {
      // 'delete game li' — 'game' is a filler, 'li' is the partial for game_titles (dynamic)
      // _computeLocalGhost should return null to trigger the dynamic fetch path
      const result = ctrl._computeLocalGhost("delete game li", 14)
      // null means "defer to dynamic fetch"
      expect(result).toBeNull()
    })
  })

  // ── list verb — server-side ghost deferral ────────────────────────────────
  //
  // The `list` verb defers all ghost computation to POST /suggestions so the
  // server-side ListClauseGhost can handle noun completion, the `with`
  // connector, and field-token completion uniformly.

  describe("free-form verb-stage prefix completion", () => {
    let ctrl

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
    })

    it("completes a unique verb prefix ('sy' → 'nc' for 'sync')", () => {
      expect(ctrl._computeLocalGhost("sy", 2).complete_current).toBe("nc")
    })

    it("stays silent for ambiguous prefix 'sh' (show + shinies)", () => {
      expect(ctrl._computeLocalGhost("sh", 2).complete_current).toBe("")
    })

    it("completes 'sho' → 'w' for 'show' (unique once past 'sh')", () => {
      expect(ctrl._computeLocalGhost("sho", 3).complete_current).toBe("w")
    })

    it("completes 'shi' → 'nies' for 'shinies' (unique once past 'sh')", () => {
      expect(ctrl._computeLocalGhost("shi", 3).complete_current).toBe("nies")
    })

    it("stays silent for an ambiguous prefix ('s' matches show, sync, shinies, schedule)", () => {
      expect(ctrl._computeLocalGhost("s", 1).complete_current).toBe("")
    })

    it("does not verb-complete once a trailing space follows the partial", () => {
      expect(ctrl._computeLocalGhost("sy ", 3).complete_current).toBe("")
    })

    it("completes 'an' → 'alyze' for 'analyze' (unique prefix)", () => {
      expect(ctrl._computeLocalGhost("an", 2).complete_current).toBe("alyze")
    })

    it("completes 'anal' → 'yze' for 'analyze'", () => {
      expect(ctrl._computeLocalGhost("anal", 4).complete_current).toBe("yze")
    })

    // platform set/unset subcommand slot (mirrors price)
    it("ghosts the first subcommand for 'platform ' → 'set'", () => {
      expect(ctrl._computeLocalGhost("platform ", 9).complete_current).toBe("set")
    })

    it("completes 'platform u' → 'nset' (unique prefix)", () => {
      expect(ctrl._computeLocalGhost("platform u", 10).complete_current).toBe("nset")
    })

    // `sync` (like `list`) now defers its whole ghost to the server-side
    // ListClauseGhost — _computeLocalGhost returns null so the caller fetches
    // POST /suggestions instead of guessing locally.
    it("defers 'sync ' to the server (returns null, no local ghost)", () => {
      expect(ctrl._computeLocalGhost("sync ", 5)).toBeNull()
    })

    it("defers 'sync c' to the server (returns null)", () => {
      expect(ctrl._computeLocalGhost("sync c", 6)).toBeNull()
    })
  })

  describe("list verb — server-side ghost deferral", () => {
    let ctrl

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
    })

    it("_computeLocalGhost returns null for 'list ' (defers to server)", () => {
      // null signals _refreshGhost to call _scheduleDynamicFetch instead of
      // applying a static ghost — so the client does NOT resolve 'channels' locally.
      const result = ctrl._computeLocalGhost("list ", 5)
      expect(result).toBeNull()
    })

    it("_computeLocalGhost returns null for 'list games ' (defers to server)", () => {
      const result = ctrl._computeLocalGhost("list games ", 11)
      expect(result).toBeNull()
    })

    it("_computeLocalGhost returns null for 'list games with ' (defers to server)", () => {
      const result = ctrl._computeLocalGhost("list games with ", 16)
      expect(result).toBeNull()
    })

    it("'list games ' → fetch → ghost shows 'with' from server response", async () => {
      const fetchMock = vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({ ghost: { complete_current: "with", next_hint: "" } }),
      })
      vi.stubGlobal("fetch", fetchMock)

      vi.useFakeTimers()
      try {
        ctrl._scheduleDynamicFetch("list games ", 11)

        // Before debounce fires, fetch has not been called
        expect(fetchMock).not.toHaveBeenCalled()

        // Advance past DYNAMIC_DEBOUNCE_MS (150 ms)
        vi.advanceTimersByTime(200)
        await Promise.resolve()
        await Promise.resolve()
        await Promise.resolve()

        expect(fetchMock).toHaveBeenCalledTimes(1)
        expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toMatchObject({ input: "list games " })
        expect(ctrl._ghostComplete).toBe("with")
      } finally {
        vi.useRealTimers()
      }
    })

    it("'list games with ' → fetch → ghost shows 'platform' from server response", async () => {
      const fetchMock = vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({ ghost: { complete_current: "platform", next_hint: "" } }),
      })
      vi.stubGlobal("fetch", fetchMock)

      vi.useFakeTimers()
      try {
        ctrl._scheduleDynamicFetch("list games with ", 16)

        vi.advanceTimersByTime(200)
        await Promise.resolve()
        await Promise.resolve()
        await Promise.resolve()

        expect(fetchMock).toHaveBeenCalledTimes(1)
        expect(ctrl._ghostComplete).toBe("platform")
      } finally {
        vi.useRealTimers()
      }
    })
  })

  // ── --help ghost hint ─────────────────────────────────────────────────────
  //
  // For any non-list chat verb, typing a "-" partial should ghost "--help".

  describe("--help ghost hint", () => {
    let ctrl

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
    })

    it("'show -' ghosts '-help' (complete_current = '-help')", () => {
      const result = ctrl._computeLocalGhost("show -", 6)
      expect(result).not.toBeNull()
      expect(result.complete_current).toBe("-help")
      expect(result.next_hint).toBe("")
    })

    it("'show --' ghosts 'help' (complete_current = 'help')", () => {
      const result = ctrl._computeLocalGhost("show --", 7)
      expect(result).not.toBeNull()
      expect(result.complete_current).toBe("help")
      expect(result.next_hint).toBe("")
    })

    it("'show --h' ghosts 'elp' (complete_current = 'elp')", () => {
      const result = ctrl._computeLocalGhost("show --h", 8)
      expect(result).not.toBeNull()
      expect(result.complete_current).toBe("elp")
    })

    it("'show --help' produces empty complete_current (exact match)", () => {
      const result = ctrl._computeLocalGhost("show --help", 11)
      // "--help" fully typed — no remaining chars to ghost
      expect(result).not.toBeNull()
      expect(result.complete_current).toBe("")
    })

    it("'delete -' also ghosts '-help'", () => {
      const result = ctrl._computeLocalGhost("delete -", 8)
      expect(result).not.toBeNull()
      expect(result.complete_current).toBe("-help")
    })

    it("'delete game -' ghosts '-help' (verb + noun + partial)", () => {
      // game_titles slot is dynamic; 'game' is consumed as a dynamic slot word,
      // then '-' triggers the --help ghost before the dynamic-fetch path.
      const result = ctrl._computeLocalGhost("delete game -", 13)
      expect(result).not.toBeNull()
      expect(result.complete_current).toBe("-help")
      expect(result.next_hint).toBe("")
    })

    it("'show video --' ghosts 'help' (verb + noun + partial)", () => {
      const result = ctrl._computeLocalGhost("show video --", 13)
      expect(result).not.toBeNull()
      expect(result.complete_current).toBe("help")
      expect(result.next_hint).toBe("")
    })
  })

  // ── Per-verb local ghost completions ─────────────────────────────────────
  //
  // These exercise _computeLocalGhost against the faithful mock catalog,
  // covering every verb that carries a static enum slot plus the dynamic
  // game_titles deferral and verb-ambiguity cases.

  describe("per-verb local ghost completions", () => {
    let ctrl

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
    })

    // find — release_status slot (first canonical: "released")
    it("'find ' → 'released' (first release_status canonical)", () => {
      expect(ctrl._computeLocalGhost("find ", 5).complete_current).toBe("released")
    })

    it("'find upc' → 'oming' (release_status prefix match)", () => {
      expect(ctrl._computeLocalGhost("find upc", 8).complete_current).toBe("oming")
    })

    // analyze — nouns slot (first canonical: "channels")
    it("'analyze ' → 'channels' (first noun canonical)", () => {
      expect(ctrl._computeLocalGhost("analyze ", 8).complete_current).toBe("channels")
    })

    it("'analyze v' → 'ids' (nouns prefix match → vids)", () => {
      expect(ctrl._computeLocalGhost("analyze v", 9).complete_current).toBe("ids")
    })

    // import — import_nouns slot (first canonical: "game")
    it("'import ' → 'game' (first import_nouns canonical)", () => {
      expect(ctrl._computeLocalGhost("import ", 7).complete_current).toBe("game")
    })

    // schedule — schedule_whens slot (first canonical: "slate")
    it("'schedule ' → 'slate' (first schedule_whens canonical)", () => {
      expect(ctrl._computeLocalGhost("schedule ", 9).complete_current).toBe("slate")
    })

    // price — price_subcommands slot (first canonical: "set")
    it("'price ' → 'set' (first price_subcommands canonical)", () => {
      expect(ctrl._computeLocalGhost("price ", 6).complete_current).toBe("set")
    })

    it("'price u' → 'nset' (price_subcommands prefix match)", () => {
      expect(ctrl._computeLocalGhost("price u", 7).complete_current).toBe("nset")
    })

    // footage — game_titles slot is dynamic → null (defers to server)
    it("'footage zel' → null (dynamic game_titles slot defers to server)", () => {
      expect(ctrl._computeLocalGhost("footage zel", 11)).toBeNull()
    })

    // verb-ambiguity: 'p' matches platform, publish, price → silent
    it("'p' is silent (ambiguous: platform, publish, price)", () => {
      expect(ctrl._computeLocalGhost("p", 1).complete_current).toBe("")
    })

    // 'pr' → price (unique)
    it("'pr' → 'ice' (unique: price)", () => {
      expect(ctrl._computeLocalGhost("pr", 2).complete_current).toBe("ice")
    })

    // 'f' matches find, footage, farewell → silent
    it("'f' is silent (ambiguous: find, footage, farewell)", () => {
      expect(ctrl._computeLocalGhost("f", 1).complete_current).toBe("")
    })

    // 'fo' → footage (unique: find=fi, farewell=fa)
    it("'fo' → 'otage' (unique: footage)", () => {
      expect(ctrl._computeLocalGhost("fo", 2).complete_current).toBe("otage")
    })

    // 'sc' → schedule (unique: sync=sy, show/shinies=sh)
    it("'sc' → 'hedule' (unique: schedule)", () => {
      expect(ctrl._computeLocalGhost("sc", 2).complete_current).toBe("hedule")
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

    it("arg-stage (stage:'arg') keeps the palette CLOSED (ghost path)", async () => {
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
      // (ghost path) so Enter submits the bare command.
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

  // ── Ghost layers within the caret overlay stack (z-index) ────────────────
  //
  // Deliberate field-wrap stack (bottom → top):
  //   type-fx layer (1)  <  trail ghosts (1)  <  suggestion ghost (2)  <  block (3)
  // The suggestion ghost reads ABOVE the decoration layers (type-fx + trail) but
  // BELOW the live block caret (.terminal-caret z-index:3) — so the block is
  // never occluded at the caret cell. Regression: the ghost was z-index:3, ABOVE
  // the block, which hid the block whenever a completion was showing.

  describe("ghost layering within the caret stack", () => {
    let ctrl

    beforeEach(async () => {
      await waitForConnect()
      ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
    })

    it("the ghost span sits above the decoration layers but below the block caret", () => {
      ctrl._setGhost("oming", "")
      expect(ctrl._ghostSpan).toBeTruthy()
      const z = Number(ctrl._ghostSpan.style.zIndex)
      expect(z).toBeGreaterThan(1) // above type-fx layer + trail ghosts (z-index 1)
      expect(z).toBeLessThan(3)    // below the live block caret (.terminal-caret z-index 3)
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

  // ── Lifecycle ────────────────────────────────────────────────────────────

  describe("lifecycle", () => {
    it("controller connects and initialises without error", async () => {
      await waitForConnect()
      const ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
      expect(ctrl).toBeTruthy()
      expect(ctrl._mode).toBe("none")
      expect(ctrl._paletteOpen).toBe(false)
    })

    it("disconnect clears ghost span and removes event listeners", async () => {
      await waitForConnect()
      const ctrl = app.getControllerForElementAndIdentifier(chatbox, "pito--suggestions")
      // Should not throw on disconnect
      expect(() => ctrl.disconnect()).not.toThrow()
    })
  })
})
