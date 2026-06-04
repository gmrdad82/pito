// pito--autosuggest
//
// Float-above autocomplete palette for the chatbox textarea.
//
// Implements tasks ad+ae+af+ag+aj+ak:
//   ad — skeleton: connect, modeFor, onInput
//   ae — slash/hashtag palette (menu, filter, navigate, insert)
//   af — key coordination (handleKeydown intercepts BEFORE chat-form + home-transition)
//   ag — auth re-filter on Turbo auth-update
//   aj — free-form inline ghost text (locally computed, grammar-gated)
//   ak — debounced dynamic fetch for dynamic vocab slots (e.g. game_titles)
//
// DOM Contract (set by chatbox ERB — build against this exactly):
//   Controller:  pito--autosuggest  on  #pito-chatbox
//   Target field:    <textarea>  (data-pito--autosuggest-target="field")
//   Target catalog:  <script type="application/json">  (data-pito--autosuggest-target="catalog")
//   Target palette:  <div class="pito-autosuggest-palette hidden">  (data-pito--autosuggest-target="palette")
//
//   data-action order on the textarea (autosuggest FIRST so handleKeydown fires first):
//     keydown->pito--autosuggest#handleKeydown
//     keydown->pito--chat-form#handleKeydown
//     input->pito--autosuggest#onInput
//
// Key-suppression strategy (af):
//   When palette is open → preventDefault + stopImmediatePropagation so that
//   chat-form#handleKeydown (Enter=submit) and home-transition#interceptEnter
//   never see the event.  Stimulus fires data-action handlers for the same
//   event type in listed order on the same element; stopImmediatePropagation
//   prevents later handlers in that list from running.
//   When palette is closed → do NOT suppress; let everything pass through so
//   Enter submits, Shift+Tab/Shift+Space (chat-form) still work, plain Tab is
//   a no-op as documented in chat-form.
//
//   aj extension — when a ghost completion is active and the user presses TAB:
//     preventDefault + stopImmediatePropagation so chat-form#handleKeydown and
//     home-transition never see the Tab.  Enter always passes through in free mode
//     (no ghost palette), so chat-form submission works normally.
//
// Auth re-filter (ag):
//   The catalog <script> is rendered server-side with the correct auth-aware
//   slash list.  After /login or /logout the server replaces #pito-chatbox via
//   Turbo Stream → Stimulus calls connect() again on the new element and re-parses
//   the fresh catalog automatically.  As a belt-and-suspenders measure we also
//   listen for turbo:before-stream-render to re-read isAuthenticated() so that if
//   the palette happens to be open during the swap it collapses cleanly.
//
// aj — free-form inline ghost text:
//   When mode is "free", renders a <span class="pito-ghost"> positioned absolutely
//   at the caret (using pito:caret CustomEvent coords from terminal-caret controller).
//   Ghost is computed locally (grammar-gated, static vocabs) or via debounced POST
//   (dynamic vocabs, task ak).  TAB accepts the complete_current completion; Enter
//   passes through to submit.

import { Controller } from "@hotwired/stimulus"
import { isAuthenticated } from "pito/auth"

// ── Dynamic fetch debounce delay (ms) ─────────────────────────────────────────
const DYNAMIC_DEBOUNCE_MS = 150
const ARG_DEBOUNCE_MS     = 120

export default class extends Controller {
  // ── Targets ────────────────────────────────────────────────────────────────
  static targets = ["field", "catalog", "palette"]

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  connect() {
    // ad: parse the embedded catalog JSON (auth-aware; rendered server-side)
    this._catalog      = this._parseCatalog()
    this._authenticated = isAuthenticated()

    // ad: initialise state
    this._open          = false
    this._items         = []   // [{label, description, insert}]
    this._selectedIndex = 0
    this._mode          = "none"

    // aj: ghost text state
    this._ghostSpan          = null   // lazily created <span class="pito-ghost">
    this._ghostComplete      = ""     // current complete_current value
    this._caretLeft          = 0
    this._caretTop           = 0

    // ak: dynamic fetch state (free-mode ghost)
    this._dynamicTimer       = null   // debounce timer id
    this._dynamicRequestId   = 0      // monotonic counter to ignore stale responses
    this._dynamicAbort       = null   // AbortController for in-flight fetch

    // arg-stage fetch state (slash/hashtag arg completion via /autocomplete)
    this._argTimer           = null
    this._argRequestId       = 0
    this._argAbort           = null

    // aj: listen for caret position events from terminal-caret controller
    this._onCaret = (e) => {
      this._caretLeft = e.detail.left
      this._caretTop  = e.detail.top
      this._positionGhost()
    }
    this.element.addEventListener("pito:caret", this._onCaret)

    // ag: belt-and-suspenders listener for Turbo stream renders that may swap
    // #pito-auth-gate (and therefore change auth state) without replacing the
    // chatbox.  If the chatbox IS replaced, connect() re-runs automatically.
    this._onTurboStream = () => {
      const wasAuthenticated = this._authenticated
      this._authenticated = isAuthenticated()
      if (wasAuthenticated !== this._authenticated) {
        // Re-parse catalog in case it was also replaced in the same stream.
        this._catalog = this._parseCatalog()
        if (this._open) this._refreshPalette()
      }
    }
    document.addEventListener("turbo:before-stream-render", this._onTurboStream)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this._onTurboStream)
    this.element.removeEventListener("pito:caret", this._onCaret)
    this._cancelDynamicFetch()
    this._cancelArgFetch()
    // Remove ghost span if it was created
    if (this._ghostSpan && this._ghostSpan.parentNode) {
      this._ghostSpan.parentNode.removeChild(this._ghostSpan)
    }
    this._ghostSpan = null
  }

  // ── Public actions (wired via data-action on the textarea) ─────────────────

  // af: MUST be listed FIRST in data-action so it fires before chat-form#handleKeydown.
  handleKeydown(event) {
    if (this._open) {
      switch (event.key) {
        case "ArrowUp":
          event.preventDefault()
          event.stopImmediatePropagation()
          this._move(-1)
          return

        case "ArrowDown":
          event.preventDefault()
          event.stopImmediatePropagation()
          this._move(1)
          return

        case "Tab":
          // Tab accepts the highlighted suggestion (B)
          event.preventDefault()
          event.stopImmediatePropagation()
          this._accept()
          return

        case "Enter":
          // Enter closes the palette and falls through to chat-form#handleKeydown
          // so the message is submitted as-is — do NOT accept, do NOT suppress (B)
          this._close()
          return

        case "Escape":
          event.preventDefault()
          event.stopImmediatePropagation()
          this._close()
          return
      }
    }

    // aj: when a ghost completion is active and TAB is pressed, accept it.
    // Enter always passes through so chat-form can submit.
    if (!this._open && this._ghostComplete && event.key === "Tab" && !event.shiftKey) {
      event.preventDefault()
      event.stopImmediatePropagation()
      this._acceptGhost()
      return
    }

    // Palette is closed (or key is not a palette/ghost key) → let the event pass through
    // so chat-form#handleKeydown and home-transition#interceptEnter can handle it.
  }

  // ad: recompute mode and refresh palette/ghost on every input event
  onInput(event) {
    const field  = this.fieldTarget
    const value  = field.value
    const cursor = field.selectionStart ?? value.length

    this._mode = this.modeFor(value, cursor)
    this._refreshPalette()
  }

  // ── ad: modeFor ────────────────────────────────────────────────────────────

  // Returns one of "slash" | "hashtag" | "free" | "none".
  // Looks at the text from the start of the field up to the cursor position.
  modeFor(value, cursor) {
    const before = value.slice(0, cursor)
    if (before.startsWith("/")) return "slash"
    if (before.startsWith("#")) return "hashtag"
    if (before.trim().length > 0) return "free"
    return "none"
  }

  // ── ae: palette rendering + filtering ─────────────────────────────────────

  _refreshPalette() {
    const field  = this.fieldTarget
    const value  = field.value
    const cursor = field.selectionStart ?? value.length

    if (this._mode === "slash") {
      this._clearGhost()
      this._cancelDynamicFetch()
      if (this._isArgStage(value, cursor)) {
        // Arg-stage: delegate to debounced /autocomplete endpoint (A)
        this._scheduleArgFetch(value, cursor)
        return
      }
      this._cancelArgFetch()
      this._items = this._buildSlashItems(value, cursor)
    } else if (this._mode === "hashtag") {
      this._clearGhost()
      this._cancelDynamicFetch()
      if (this._isArgStage(value, cursor)) {
        // Arg-stage: delegate to debounced /autocomplete endpoint (A)
        this._scheduleArgFetch(value, cursor)
        return
      }
      this._cancelArgFetch()
      this._items = this._buildHashtagItems(value, cursor)
    } else if (this._mode === "free") {
      // aj: free mode — no palette, only ghost text
      this._items = []
      this._cancelArgFetch()
      this._close()
      this._refreshGhost(value, cursor)
      return
    } else {
      // none — clear everything
      this._items = []
      this._clearGhost()
      this._cancelDynamicFetch()
      this._cancelArgFetch()
    }

    if (this._items.length === 0) {
      this._close()
      return
    }

    // Clamp selectedIndex if the list shrank
    if (this._selectedIndex >= this._items.length) {
      this._selectedIndex = 0
    }

    this._renderRows()
    this._open = true
    this.paletteTarget.classList.remove("hidden")
  }

  // ae: build slash items by prefix-matching the typed partial after "/"
  _buildSlashItems(value, cursor) {
    // Extract the partial command name (text after "/" up to cursor, no spaces)
    const partial = value.slice(1, cursor).split(" ")[0].toLowerCase()

    return (this._catalog.slash || [])
      .filter(entry => entry.name.toLowerCase().startsWith(partial))
      .map(entry => ({
        label:       "/" + entry.name,
        description: entry.description || "",
        insert:      entry.insert,     // e.g. "/config " (with trailing space)
      }))
  }

  // ae: build hashtag items by prefix-matching the typed partial after "#"
  _buildHashtagItems(value, cursor) {
    const partial = value.slice(1, cursor).split(" ")[0].toLowerCase()

    return (this._catalog.hashtag || [])
      .filter(entry => entry.name.toLowerCase().startsWith(partial))
      .map(entry => ({
        label:       "#" + entry.name,
        description: entry.description || "",
        insert:      "#" + entry.insert, // insert already contains the verb; prefix # so it replaces correctly
      }))
  }

  // A: returns true when the cursor is past the verb + at least one space
  // i.e. the user has typed "/config " or "/config goo" (space exists after verb)
  _isArgStage(value, cursor) {
    const before = value.slice(0, cursor)
    // After the trigger char (/ or #), look for at least one space
    return before.length > 1 && before.slice(1).includes(" ")
  }

  // ── A: arg-stage palette fetch (debounced POST /autocomplete) ─────────────

  _scheduleArgFetch(value, cursor) {
    // Cancel previous pending timer or in-flight request
    this._cancelArgFetch()

    this._argTimer = setTimeout(() => {
      this._argTimer = null
      this._fetchArgSuggestions(value, cursor)
    }, ARG_DEBOUNCE_MS)
  }

  async _fetchArgSuggestions(value, cursor) {
    const myRequestId = ++this._argRequestId

    const abortCtrl    = new AbortController()
    this._argAbort     = abortCtrl

    const csrfToken      = document.querySelector('meta[name="csrf-token"]')?.content
    const uuidInput      = document.querySelector('input[name="uuid"]')
    const conversationId = uuidInput ? uuidInput.value : undefined

    const body = { input: value, cursor }
    if (conversationId) body.uuid = conversationId

    try {
      const resp = await fetch("/autocomplete", {
        method:  "POST",
        signal:  abortCtrl.signal,
        headers: {
          "Content-Type": "application/json",
          "Accept":        "application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {}),
        },
        body: JSON.stringify(body),
      })

      if (myRequestId !== this._argRequestId) return

      if (!resp.ok) {
        this._items = []
        this._close()
        return
      }

      const data = await resp.json()

      if (myRequestId !== this._argRequestId) return

      const menuItems = data.menu_items || []
      this._items = menuItems.map(item => ({
        label:       item.label       || item.insert || "",
        description: item.description || "",
        insert:      item.insert      || "",
        masked:      item.masked      || false,
      }))

      if (this._items.length === 0) {
        this._close()
        return
      }

      if (this._selectedIndex >= this._items.length) {
        this._selectedIndex = 0
      }

      this._renderRows()
      this._open = true
      this.paletteTarget.classList.remove("hidden")
    } catch (err) {
      if (myRequestId === this._argRequestId) {
        this._items = []
        this._close()
      }
    }
  }

  _cancelArgFetch() {
    if (this._argTimer !== null) {
      clearTimeout(this._argTimer)
      this._argTimer = null
    }
    if (this._argAbort) {
      this._argAbort.abort()
      this._argAbort = null
    }
    this._argRequestId++
  }

  // ae: render rows matching the server component's classes exactly
  // (pito-autosuggest-row, data-index, is-selected; label in 16ch column + dim description)
  _renderRows() {
    const palette = this.paletteTarget
    palette.innerHTML = ""

    this._items.forEach((item, i) => {
      const row = document.createElement("div")
      row.className  = "pito-autosuggest-row py-0.5 px-2.5"
      if (i === this._selectedIndex) row.classList.add("is-selected")
      row.dataset.index = i

      const labelEl = document.createElement("span")
      labelEl.className   = "text-fg inline-block"
      labelEl.style.width = "16ch"
      labelEl.textContent = item.label

      const descEl = document.createElement("span")
      descEl.className   = "text-fg-dim"
      descEl.textContent = item.description

      row.appendChild(labelEl)
      row.appendChild(descEl)

      // ae: mouse support — click a row to accept it
      row.addEventListener("mousedown", (e) => {
        // mousedown (not click) so we fire before the textarea blur
        e.preventDefault()
        this._selectedIndex = i
        this._accept()
      })

      palette.appendChild(row)
    })
  }

  // ── ae: navigation ─────────────────────────────────────────────────────────

  _move(delta) {
    if (!this._items.length) return
    this._selectedIndex = (this._selectedIndex + delta + this._items.length) % this._items.length
    this._renderRows()
  }

  // ae: accept the currently highlighted item
  _accept() {
    const item = this._items[this._selectedIndex]
    if (!item) { this._close(); return }

    this._insertToken(item.insert)
    this._close()
  }

  // ae: replace the active token (the prefix that triggered the palette) with insert
  //
  // Verb-stage (no space after trigger char yet):
  //   Replace from position 0 up to the cursor — the whole "/foo" partial — with
  //   insertText (e.g. "/config " which already has a trailing space).
  //
  // Arg-stage (space exists between trigger and cursor):
  //   The verb is already finalised. Replace only the current partial arg token
  //   (from after the last space before the cursor to the cursor) with insertText.
  //   The engine's insert value already contains a trailing space, so we never
  //   inject an extra one — just splice in insertText and keep text after the cursor.
  _insertToken(insertText) {
    const field  = this.fieldTarget
    const value  = field.value
    const cursor = field.selectionStart ?? value.length
    const mode   = this._mode

    let tokenStart, tokenEnd

    if (mode === "slash" || mode === "hashtag") {
      if (this._isArgStage(value, cursor)) {
        // Arg-stage: find the last space before the cursor — that is where the
        // current partial arg token begins.
        const beforeCursor = value.slice(0, cursor)
        const lastSpace    = beforeCursor.lastIndexOf(" ")
        tokenStart = lastSpace + 1          // char after the last space
        tokenEnd   = cursor                 // replace up to the cursor only
      } else {
        // Verb-stage: replace from position 0 (the trigger char) to cursor.
        tokenStart = 0
        tokenEnd   = cursor
      }
    } else {
      tokenStart = cursor
      tokenEnd   = cursor
    }

    field.value = value.slice(0, tokenStart) + insertText + value.slice(tokenEnd)

    // Place cursor at end of inserted text
    const newPos = tokenStart + insertText.length
    field.selectionStart = field.selectionEnd = newPos

    // Notify other controllers (chat-form hiddenInput sync, etc.)
    field.dispatchEvent(new Event("input", { bubbles: true }))
    field.focus({ preventScroll: true })
  }

  // ── palette open/close helpers ─────────────────────────────────────────────

  _close() {
    this._open = false
    this.paletteTarget.classList.add("hidden")
    this.paletteTarget.innerHTML = ""
    this._items         = []
    this._selectedIndex = 0
    // Reset mode so next onInput recomputes cleanly — but only if not in free mode
    // (free mode ghost does its own cleanup via _clearGhost)
    if (this._mode !== "free") {
      this._mode = "none"
    }
  }

  // ── ag: catalog parsing (called on connect + on auth change) ───────────────

  _parseCatalog() {
    try {
      return JSON.parse(this.catalogTarget.textContent)
    } catch (e) {
      console.warn("[pito--autosuggest] Failed to parse catalog JSON:", e)
      return { slash: [], hashtag: [], chat: [], vocabularies: {} }
    }
  }

  // ── aj: ghost text ─────────────────────────────────────────────────────────

  // Main entry point for free-mode ghost: determine if we should fetch dynamically
  // or compute locally, then update the ghost span.
  _refreshGhost(value, cursor) {
    const ghost = this._computeLocalGhost(value, cursor)

    if (ghost === null) {
      // The active slot is a dynamic vocab — defer to debounced fetch (task ak)
      this._scheduleDynamicFetch(value, cursor)
      return
    }

    // Static result — cancel any pending dynamic fetch and show immediately
    this._cancelDynamicFetch()
    this._setGhost(ghost.complete_current, ghost.next_hint)
  }

  // Compute ghost text locally from the catalog.
  // Returns { complete_current, next_hint } for static vocab slots.
  // Returns null if the active slot is dynamic (triggers ak path).
  // Returns { complete_current: "", next_hint: "" } if grammar gate fails or no match.
  _computeLocalGhost(value, cursor) {
    const before = value.slice(0, cursor)
    const words  = this._lexWords(before)

    // Grammar gate: first word must be a known chat verb
    if (words.length === 0) return { complete_current: "", next_hint: "" }

    const verbWord = words[0].toLowerCase()
    const chatSpec = this._findChatSpec(verbWord)
    if (!chatSpec) return { complete_current: "", next_hint: "" }

    const endsWithSpace = before.endsWith(" ")
    const typedSlotWords = endsWithSpace ? words.slice(1) : words.slice(1, -1)
    const currentPartial = endsWithSpace ? "" : (words[words.length - 1] || "")

    // Get enum slots from chat spec (mirrors engine.rb chat_shared_slots)
    const enumSlots = this._chatEnumSlots()

    // Walk already-typed words to track which slots are consumed
    const alreadyFilled = {}
    const fillerWords = this._fillerSet()

    for (const word of typedSlotWords) {
      const wl = word.toLowerCase()
      if (fillerWords.has(wl)) continue

      for (const slot of enumSlots) {
        if (alreadyFilled[slot.name] && !slot.repeatable) continue
        const vocab = this._getVocab(slot.source)
        if (!vocab) continue
        if (vocab.dynamic) {
          // Dynamic: treat any word as consuming this slot (mirror server logic)
          alreadyFilled[slot.name] = true
          break
        }
        const resolved = this._resolveVocab(vocab, wl)
        if (resolved !== null) {
          alreadyFilled[slot.name] = true
          break
        }
      }
    }

    // Find active slot: first enum slot not yet fully consumed (or repeatable)
    const activeSlot = enumSlots.find(s => !alreadyFilled[s.name] || s.repeatable)

    if (endsWithSpace) {
      // next_hint: show hint for next expected slot
      const hint = this._nextHintForSlot(activeSlot)
      return { complete_current: "", next_hint: hint }
    } else {
      // complete_current: if currentPartial uniquely prefixes one vocab member
      if (!currentPartial) return { complete_current: "", next_hint: "" }

      // Check if the active slot's vocab is dynamic
      if (activeSlot) {
        const vocab = this._getVocab(activeSlot.source)
        if (vocab && vocab.dynamic) {
          // Signal caller to use dynamic fetch (task ak)
          return null
        }
      }

      const completion = this._computeCurrentCompletion(activeSlot, currentPartial)
      return { complete_current: completion, next_hint: "" }
    }
  }

  // Lex the text into word tokens, splitting on whitespace and skipping empty strings.
  _lexWords(text) {
    return text.split(/\s+/).filter(w => w.length > 0)
  }

  // Find a chat spec by verb name (case-insensitive).
  _findChatSpec(verbWord) {
    const chatSpecs = this._catalog.chat || []
    return chatSpecs.find(s => s.name.toLowerCase() === verbWord) || null
  }

  // Extract the ordered enum slots from the chat grammar.
  // Mirrors chat_shared_slots from specs.rb:
  //   status   → release_status
  //   genre    → genres (repeatable)
  //   platform → platforms
  _chatEnumSlots() {
    return [
      { name: "status",   source: "release_status", repeatable: false },
      { name: "genre",    source: "genres",          repeatable: true  },
      { name: "platform", source: "platforms",       repeatable: false },
    ]
  }

  // Get vocabulary entry from catalog by name (string key).
  _getVocab(sourceName) {
    const vocabs = this._catalog.vocabularies || {}
    return vocabs[sourceName] || null
  }

  // Get the set of filler words from the catalog.
  _fillerSet() {
    const fillers = this._catalog.vocabularies && this._catalog.vocabularies.fillers
    if (!fillers || !fillers.fillers) return new Set()
    return new Set(fillers.fillers.map(f => f.toLowerCase()))
  }

  // Resolve a word against a static vocab's canonical members and synonyms.
  // Returns canonical form string if found, null otherwise.
  _resolveVocab(vocab, wordLower) {
    if (!vocab) return null
    const canonical = vocab.canonical || []
    // Check canonical members (case-insensitive)
    const canonMatch = canonical.find(c => c.toLowerCase() === wordLower)
    if (canonMatch) return canonMatch
    // Check synonyms
    const synonyms = vocab.synonyms || {}
    if (synonyms[wordLower] !== undefined) return synonyms[wordLower]
    return null
  }

  // Compute the remaining chars if currentPartial uniquely prefixes exactly one
  // candidate in the active slot's vocab (canonical + synonym keys).
  _computeCurrentCompletion(activeSlot, partial) {
    if (!partial || !activeSlot) return ""
    const vocab = this._getVocab(activeSlot.source)
    if (!vocab || vocab.dynamic) return ""

    const partialLower = partial.toLowerCase()
    const candidates   = this._vocabAllForms(vocab)

    const matches = candidates.filter(c => c.toLowerCase().startsWith(partialLower))
    if (matches.length !== 1) return ""

    // Return the remaining characters after the partial
    return matches[0].slice(partial.length)
  }

  // All completable forms of a static vocab: canonical members only.
  // (Synonyms are accepted input but we complete to canonical forms.)
  _vocabAllForms(vocab) {
    return (vocab.canonical || [])
  }

  // Generate a next_hint string for the active slot.
  _nextHintForSlot(activeSlot) {
    if (!activeSlot) return ""
    const vocab = this._getVocab(activeSlot.source)
    if (vocab && !vocab.dynamic) {
      const canonical = vocab.canonical || []
      if (canonical.length > 0) return `<${canonical[0]}>`
    }
    return `<${activeSlot.name}>`
  }

  // ── aj: ghost span management ──────────────────────────────────────────────

  // Lazily create (or get) the ghost span inside the field-wrap.
  _ghostEl() {
    if (!this._ghostSpan) {
      const wrap = this.fieldTarget.closest(".pito-chatbox__field-wrap")
      if (!wrap) return null

      const span = document.createElement("span")
      span.className  = "pito-ghost"
      span.setAttribute("aria-hidden", "true")
      // Position absolutely within the field-wrap (which is position:relative)
      span.style.position      = "absolute"
      span.style.top           = "0"
      span.style.left          = "0"
      span.style.whiteSpace    = "pre"
      span.style.pointerEvents = "none"
      span.style.userSelect    = "none"
      wrap.appendChild(span)
      this._ghostSpan = span
    }
    return this._ghostSpan
  }

  // Set ghost content and position it at the caret.
  _setGhost(completeText, hintText) {
    this._ghostComplete = completeText || ""
    const hasContent    = this._ghostComplete || hintText

    const span = this._ghostEl()
    if (!span) return

    if (!hasContent) {
      span.textContent = ""
      return
    }

    // Build ghost text: complete_current immediately + optional dim hint
    if (this._ghostComplete) {
      // Show completion directly (no dim separator needed)
      span.textContent = this._ghostComplete
    } else if (hintText) {
      // Trailing space — show dim next_hint
      span.textContent = hintText
    } else {
      span.textContent = ""
    }

    this._positionGhost()
  }

  // Position the ghost span at the current caret coords.
  _positionGhost() {
    const span = this._ghostSpan
    if (!span) return
    span.style.transform = `translate(${this._caretLeft}px, ${this._caretTop}px)`
  }

  // Clear ghost text and reset state.
  _clearGhost() {
    this._ghostComplete = ""
    this._cancelDynamicFetch()
    if (this._ghostSpan) {
      this._ghostSpan.textContent = ""
    }
  }

  // aj: TAB accept — insert the ghost completion into the field.
  _acceptGhost() {
    if (!this._ghostComplete) return

    const field      = this.fieldTarget
    const cursor     = field.selectionStart ?? field.value.length
    const completion = this._ghostComplete

    // Insert the completion at the cursor position
    field.value = field.value.slice(0, cursor) + completion + field.value.slice(cursor)

    // Move cursor to after the inserted text
    const newPos = cursor + completion.length
    field.selectionStart = field.selectionEnd = newPos

    // Clear ghost state before dispatching input (which will recompute)
    this._ghostComplete = ""
    if (this._ghostSpan) this._ghostSpan.textContent = ""

    // Dispatch input so all controllers (chat-form sync, terminal-caret, onInput)
    // see the updated value
    field.dispatchEvent(new Event("input", { bubbles: true }))
    field.focus({ preventScroll: true })
  }

  // ── ak: debounced dynamic fetch ────────────────────────────────────────────

  _scheduleDynamicFetch(value, cursor) {
    // Cancel any previous pending timer or in-flight request
    this._cancelDynamicFetch()

    this._dynamicTimer = setTimeout(() => {
      this._dynamicTimer = null
      this._fetchDynamicGhost(value, cursor)
    }, DYNAMIC_DEBOUNCE_MS)
  }

  async _fetchDynamicGhost(value, cursor) {
    // Increment request id so any older response can be discarded
    const myRequestId = ++this._dynamicRequestId

    // Create AbortController for this request
    const abortCtrl = new AbortController()
    this._dynamicAbort = abortCtrl

    // Gather CSRF token and optional conversation uuid from the DOM
    const csrfToken      = document.querySelector('meta[name="csrf-token"]')?.content
    const uuidInput      = document.querySelector('input[name="uuid"]')
    const conversationId = uuidInput ? uuidInput.value : undefined

    const body = { input: value, cursor }
    if (conversationId) body.uuid = conversationId

    try {
      const resp = await fetch("/autocomplete", {
        method:  "POST",
        signal:  abortCtrl.signal,
        headers: {
          "Content-Type": "application/json",
          "Accept":        "application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {}),
        },
        body: JSON.stringify(body),
      })

      // Discard stale responses
      if (myRequestId !== this._dynamicRequestId) return

      if (!resp.ok) {
        this._clearGhost()
        return
      }

      const data = await resp.json()

      // Discard stale responses again (in case another fetch started while awaiting json)
      if (myRequestId !== this._dynamicRequestId) return

      const ghost = data.ghost || {}
      this._setGhost(ghost.complete_current || "", ghost.next_hint || "")
    } catch (err) {
      // Abort errors are expected when we cancel; swallow all errors defensively
      if (myRequestId === this._dynamicRequestId) {
        this._clearGhost()
      }
    }
  }

  _cancelDynamicFetch() {
    if (this._dynamicTimer !== null) {
      clearTimeout(this._dynamicTimer)
      this._dynamicTimer = null
    }
    if (this._dynamicAbort) {
      this._dynamicAbort.abort()
      this._dynamicAbort = null
    }
    // Bump request id so any in-flight response is discarded when it arrives
    this._dynamicRequestId++
  }
}
