// pito--autosuggest
//
// Chatbox autosuggest: stage-dependent UX for slash, hashtag, and free-form input.
//
// STAGE DETECTION
//   Slash/hashtag VERB stage (no space yet after trigger):  PALETTE
//   Slash/hashtag ARG  stage (space exists after verb):     INLINE GHOST
//   Free-form (no / or #):                                  INLINE GHOST
//   None (empty):                                           nothing
//
// VERB STAGE (palette)
//   Float-above .pito-autosuggest-palette lists matching catalog entries.
//   ArrowUp/ArrowDown → navigate rows (single step).
//   Enter  → accept highlighted item (_insertToken), no submit.
//   Space  → dismiss palette; space types normally → field becomes "/cmd " → arg stage.
//   Tab    → NO-OP: preventDefault+stopImmediatePropagation, palette stays open.
//   Esc    → close palette.
//   Other  → type normally; onInput re-filters the palette.
//
// ARG STAGE (ghost)
//   Debounced POST /autocomplete → top hit shown as inline ghost.
//   Tab → accept ghost (_insertToken, no submit).
//   Enter → pass through → form submits.
//
// FREE-FORM (ghost)
//   Local grammar-gated ghost or debounced POST for dynamic slots.
//   Tab → accept (append suffix at cursor, no submit).
//   Enter → pass through → form submits.
//
// handleKeydown dispatch rule:
//   palette open?  → Arrow→nav; Enter→accept; Tab→no-op; Space→dismiss (no preventDefault); Esc→close; other→pass through
//   ghost active?  → Tab→accept (preventDefault+stopImmediatePropagation); Enter→pass through
//   else           → pass through
//
// Implements tasks ad+ae+af+ag+aj+ak:
//   ad — skeleton: connect, modeFor, onInput
//   ae — slash/hashtag: verb-stage palette + arg-stage ghost
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
    this._mode          = "none"

    // Palette state (verb-stage slash/hashtag)
    this._paletteOpen   = false
    this._paletteRows   = []   // current list of catalog entries shown
    this._selectedIdx   = 0   // highlighted row index

    // aj/ae: ghost text state (shared by arg-stage + free modes)
    this._ghostSpan          = null   // lazily created <span class="pito-ghost">
    this._ghostComplete      = ""     // text that TAB would append at the caret
    this._ghostInsert        = null   // for slash/hashtag: full item.insert to use with _insertToken
    this._caretLeft          = 0
    this._caretTop           = 0

    // ak: dynamic fetch state (free-mode ghost)
    this._dynamicTimer       = null   // debounce timer id
    this._dynamicRequestId   = 0      // monotonic counter to ignore stale responses
    this._dynamicAbort       = null   // AbortController for in-flight fetch

    // ae arg-stage fetch state (slash/hashtag arg completion via /autocomplete)
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
        // Re-evaluate ghost in case auth change affects available commands
        this._refreshSuggestion()
      }
    }
    document.addEventListener("turbo:before-stream-render", this._onTurboStream)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this._onTurboStream)
    this.element.removeEventListener("pito:caret", this._onCaret)
    this._cancelDynamicFetch()
    this._cancelArgFetch()
    this._closePalette()
    // Remove ghost span if it was created
    if (this._ghostSpan && this._ghostSpan.parentNode) {
      this._ghostSpan.parentNode.removeChild(this._ghostSpan)
    }
    this._ghostSpan = null
  }

  // ── Public actions (wired via data-action on the textarea) ─────────────────

  // af: MUST be listed FIRST in data-action so it fires before chat-form#handleKeydown.
  handleKeydown(event) {
    // ── VERB-STAGE PALETTE IS OPEN ──────────────────────────────────────────
    // All key handling for palette navigation/accept/close must
    // preventDefault + stopImmediatePropagation so chat-form never sees them.
    if (this._paletteOpen) {
      if (event.key === "ArrowDown") {
        event.preventDefault()
        event.stopImmediatePropagation()
        this._moveSelection(1)
        return
      }
      if (event.key === "ArrowUp") {
        event.preventDefault()
        event.stopImmediatePropagation()
        this._moveSelection(-1)
        return
      }
      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault()
        event.stopImmediatePropagation()
        this._acceptPaletteSelection()
        return
      }
      if (event.key === "Tab") {
        // Tab is a no-op while the palette is open — do NOT accept, do NOT navigate.
        // Prevent focus movement but keep the palette open.
        event.preventDefault()
        event.stopImmediatePropagation()
        return
      }
      if (event.key === "Escape") {
        event.preventDefault()
        event.stopImmediatePropagation()
        this._closePalette()
        return
      }
      if (event.key === " ") {
        // Space: dismiss the palette and let the space character type normally
        // so the field becomes e.g. "/help " and mode transitions to arg stage.
        this._closePalette()
        return  // no preventDefault — space is typed
      }
      // Any other key (printable characters, Backspace, etc.): let it type normally.
      // onInput will fire and re-filter the palette via _refreshVerbPalette.
      return
    }

    // ── GHOST IS ACTIVE (arg-stage or free-form) ────────────────────────────
    // Tab accepts ghost; Enter passes through to submit.
    if (this._ghostComplete && event.key === "Tab" && !event.shiftKey) {
      event.preventDefault()
      event.stopImmediatePropagation()
      this._acceptGhost()
      return
    }

    // All other keys pass through to chat-form#handleKeydown and
    // home-transition#interceptEnter without suppression.
  }

  // ad: recompute mode and refresh ghost/palette on every input event
  onInput(event) {
    const field  = this.fieldTarget
    const value  = field.value
    const cursor = field.selectionStart ?? value.length

    this._mode = this.modeFor(value, cursor)
    this._refreshSuggestion()
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

  // ── ae/aj: unified suggestion refresh (palette for verb-stage, ghost otherwise) ──

  _refreshSuggestion() {
    const field  = this.fieldTarget
    const value  = field.value
    const cursor = field.selectionStart ?? value.length

    if (this._mode === "slash" || this._mode === "hashtag") {
      this._cancelDynamicFetch()

      if (this._isArgStage(value, cursor)) {
        // Arg-stage: close palette, show ghost via debounced fetch
        this._closePalette()
        this._scheduleArgFetch(value, cursor)
        return
      }

      // Verb-stage: cancel arg fetch, clear ghost, show palette
      this._cancelArgFetch()
      this._clearGhost()
      this._refreshVerbPalette(value, cursor)
    } else if (this._mode === "free") {
      // Free mode: close palette, cancel arg fetch, show ghost
      this._closePalette()
      this._cancelArgFetch()
      this._refreshGhost(value, cursor)
    } else {
      // none — clear everything
      this._closePalette()
      this._clearGhost()
      this._cancelDynamicFetch()
      this._cancelArgFetch()
    }
  }

  // ── ae: verb-stage palette ─────────────────────────────────────────────────

  // Compute matching catalog entries and render (or close) the palette.
  _refreshVerbPalette(value, cursor) {
    const triggerChar = value[0]   // "/" or "#"
    const partial     = value.slice(1, cursor).split(" ")[0].toLowerCase()

    let entries
    if (triggerChar === "/") {
      entries = (this._catalog.slash || [])
        .filter(e => e.name.toLowerCase().startsWith(partial))
    } else {
      // Collect available segment handles from the scrollback DOM (unique, sorted).
      const handleEls = document.querySelectorAll("#pito-scrollback [data-pito-handle]")
      const uniqueHandles = [...new Set([...handleEls].map(el => el.dataset.pitoHandle))]
      entries = uniqueHandles
        .filter(h => h.toLowerCase().startsWith(partial))
        .map(h => ({ name: h, insert: "#" + h + " " }))
    }

    if (entries.length === 0) {
      this._closePalette()
      return
    }

    this._paletteRows    = entries
    this._paletteTrigger = triggerChar
    this._selectedIdx    = 0
    this._renderPalette()
  }

  // Render the palette DOM rows inside the palette target element.
  _renderPalette() {
    const palette = this.paletteTarget
    palette.innerHTML = ""

    this._paletteRows.forEach((entry, idx) => {
      const row = document.createElement("div")
      row.className = "pito-autosuggest-row" + (idx === this._selectedIdx ? " is-selected" : "")
      const cmd = document.createElement("span")
      cmd.className   = "pito-autosuggest-cmd"
      cmd.textContent = (this._paletteTrigger || "/") + (entry.name || "")
      row.appendChild(cmd)
      if (entry.description) {
        const desc = document.createElement("span")
        desc.className   = "pito-autosuggest-desc"
        desc.textContent = entry.description
        row.appendChild(desc)
      }
      row.dataset.idx = String(idx)

      // Click to accept
      row.addEventListener("mousedown", (e) => {
        // mousedown fires before blur; prevent blur from hiding palette first
        e.preventDefault()
        this._selectedIdx = idx
        this._acceptPaletteSelection()
      })

      palette.appendChild(row)
    })

    palette.classList.remove("hidden")
    this._paletteOpen = true
  }

  // Move selection by delta (+1 down, -1 up), wrapping within bounds.
  _moveSelection(delta) {
    if (!this._paletteOpen || this._paletteRows.length === 0) return

    this._selectedIdx = Math.max(0, Math.min(
      this._paletteRows.length - 1,
      this._selectedIdx + delta
    ))
    this._highlightSelected()
  }

  // Update the .is-selected class on palette rows without a full re-render.
  _highlightSelected() {
    const palette = this.paletteTarget
    const rows    = palette.querySelectorAll(".pito-autosuggest-row")
    rows.forEach((row, idx) => {
      row.classList.toggle("is-selected", idx === this._selectedIdx)
    })
  }

  // Accept the currently highlighted palette row.
  _acceptPaletteSelection() {
    const entry = this._paletteRows[this._selectedIdx]
    if (!entry) {
      this._closePalette()
      return
    }
    this._closePalette()
    this._insertToken(entry.insert)
  }

  // Hide and reset the palette.
  _closePalette() {
    if (this.hasPaletteTarget) {
      this.paletteTarget.classList.add("hidden")
      this.paletteTarget.innerHTML = ""
    }
    this._paletteOpen = false
    this._paletteRows = []
    this._selectedIdx = 0
  }

  // ae: returns true when the cursor is past the verb + at least one space
  // i.e. the user has typed "/config " or "/config goo" (space exists after verb)
  _isArgStage(value, cursor) {
    const before = value.slice(0, cursor)
    // After the trigger char (/ or #), look for at least one space
    return before.length > 1 && before.slice(1).includes(" ")
  }

  // ── ae: arg-stage ghost fetch (debounced POST /autocomplete) ─────────────

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
        this._clearGhost()
        return
      }

      const data = await resp.json()

      if (myRequestId !== this._argRequestId) return

      const menuItems = data.menu_items || []
      if (menuItems.length === 0) {
        this._clearGhost()
        return
      }

      // ae: show top result as ghost text — display the suffix of insert that
      // goes beyond what the user has already typed for the current arg token.
      const topItem = menuItems[0]
      const insert  = topItem.insert || ""

      // Find the current partial arg token (text after last space before cursor)
      const beforeCursor = value.slice(0, cursor)
      const lastSpace    = beforeCursor.lastIndexOf(" ")
      const partial      = beforeCursor.slice(lastSpace + 1)   // may be ""

      // Compute ghost suffix: insert startsWith partial (case-insensitive) → show remainder
      let ghostSuffix
      if (partial.length === 0) {
        ghostSuffix = insert
      } else if (insert.toLowerCase().startsWith(partial.toLowerCase())) {
        ghostSuffix = insert.slice(partial.length)
      } else {
        // No prefix match — top candidate doesn't match what's typed; clear ghost
        this._clearGhost()
        return
      }

      // Store the full insert so _acceptGhost uses _insertToken correctly
      this._ghostInsert = insert
      this._ghostComplete = ghostSuffix

      const span = this._ghostEl()
      if (!span) return
      span.textContent = ghostSuffix
      this._positionGhost()
    } catch (err) {
      if (myRequestId === this._argRequestId) {
        this._clearGhost()
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

  // ae: replace the active token (the prefix that triggered the ghost) with insert
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
  // Font/line-height metrics are copied from the field so the ghost baseline
  // aligns exactly with the textarea's text line-box (same fix as the block
  // caret's #syncBlockMetrics which sets height+lineHeight to cs.lineHeight).
  _ghostEl() {
    if (!this._ghostSpan) {
      const wrap = this.fieldTarget.closest(".pito-chatbox__field-wrap")
      if (!wrap) return null

      const span = document.createElement("span")
      span.className  = "pito-ghost"
      span.setAttribute("aria-hidden", "true")

      // Copy font + line-height metrics from the field so the ghost text baseline
      // sits on the same line-box as the typed text.  Without this the span
      // inherits the browser default line-height which can be 1–2px too tall,
      // causing the ghost to sit slightly below the typed text.
      const cs = getComputedStyle(this.fieldTarget)
      span.style.fontFamily   = cs.fontFamily
      span.style.fontSize     = cs.fontSize
      span.style.fontWeight   = cs.fontWeight
      span.style.fontStyle    = cs.fontStyle
      span.style.lineHeight   = cs.lineHeight
      span.style.letterSpacing = cs.letterSpacing

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
    this._ghostInsert   = null
    this._cancelDynamicFetch()
    if (this._ghostSpan) {
      this._ghostSpan.textContent = ""
    }
  }

  // aj/ae: TAB accept (ghost) — insert the ghost completion into the field.
  // For slash/hashtag arg-stage, use _insertToken with the stored full insert string
  // so the token is cleanly replaced (trailing space, no doubling).
  // For free mode, append the ghost suffix at the cursor.
  _acceptGhost() {
    if (!this._ghostComplete) return

    if ((this._mode === "slash" || this._mode === "hashtag") && this._ghostInsert) {
      // ae: clean token replacement via _insertToken
      const insertText = this._ghostInsert
      // Clear ghost state before _insertToken dispatches input (which recomputes)
      this._ghostComplete = ""
      this._ghostInsert   = null
      if (this._ghostSpan) this._ghostSpan.textContent = ""
      this._insertToken(insertText)
      return
    }

    // aj: free-form — append suffix at cursor
    const field      = this.fieldTarget
    const cursor     = field.selectionStart ?? field.value.length
    const completion = this._ghostComplete

    field.value = field.value.slice(0, cursor) + completion + field.value.slice(cursor)

    const newPos = cursor + completion.length
    field.selectionStart = field.selectionEnd = newPos

    // Clear ghost state before dispatching input (which will recompute)
    this._ghostComplete = ""
    this._ghostInsert   = null
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
