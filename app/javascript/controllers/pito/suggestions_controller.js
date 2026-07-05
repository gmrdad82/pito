// pito--suggestions
//
// Chatbox suggestions: stage-dependent UX for slash, hashtag, and free-form input.
//
// STAGE DETECTION
//   Slash/hashtag VERB stage (no space yet after trigger):  PALETTE (local)
//   Hashtag REPLY-VERB stage (`#<handle> <verb>`):          PALETTE (fetched)
//   Slash /config ARG stage (trailing space, config verb):  PALETTE (fetched)
//   Free-form (no / or #):                                  nothing (palette closed)
//   None (empty):                                           nothing
//
//   The reply-verb stage sits AFTER the handle's space, so it trips the space
//   heuristic (_isArgStage) — but the engine tags its /suggestions response
//   stage:"verb" and the client renders the full allowed-verb list as a palette
//   (with/without/shinies/schedule/show/…).
//
// VERB STAGE (palette)
//   Float-above .pito-suggestions-palette lists matching catalog entries.
//   ArrowUp/ArrowDown → navigate rows (single step).
//   Enter  → accept highlighted item (_insertToken), no submit.
//   Space  → dismiss palette; space types normally → field becomes "/cmd " → arg stage.
//   Esc    → close palette.
//   Other  → type normally; onInput re-filters the palette.
//
// Tab is NOT handled anywhere (owner #9): the inline completion feature was
// removed, so Tab behaves natively in every state (palette open or not).
//
// FREE-FORM / ARG STAGE (non-palette)
//   Free input (no / or #) and non-palette arg stages produce no suggestions.
//   Enter → pass through → form submits.
//
// handleKeydown dispatch rule:
//   palette open?  → Arrow→nav; Enter→accept; Space→dismiss (no preventDefault); Esc→close; other→pass through
//   else           → all keys pass through (no Tab handling)
//
// Implements tasks ad+ae+af+ag:
//   ad — skeleton: connect, modeFor, onInput
//   ae — slash/hashtag: verb-stage palette + reply-verb/config palette fetches
//   af — key coordination (handleKeydown intercepts BEFORE chat-form + home-transition)
//   ag — auth re-filter on Turbo auth-update
//
// DOM Contract (set by chatbox ERB — build against this exactly):
//   Controller:  pito--suggestions  on  #pito-chatbox
//   Target field:    <textarea>  (data-pito--suggestions-target="field")
//   Target catalog:  <script type="application/json">  (data-pito--suggestions-target="catalog")
//   Target palette:  <div class="pito-suggestions-palette hidden">  (data-pito--suggestions-target="palette")
//
//   data-action order on the textarea (suggestions FIRST so handleKeydown fires first):
//     keydown->pito--suggestions#handleKeydown
//     keydown->pito--chat-form#handleKeydown
//     input->pito--suggestions#onInput

import { Controller } from "@hotwired/stimulus"
import { isAuthenticated } from "pito/auth"

// ── Arg-stage fetch debounce delay (ms) ───────────────────────────────────────
const ARG_DEBOUNCE_MS = 120

export default class extends Controller {
  // ── Targets ────────────────────────────────────────────────────────────────
  static targets = ["field", "catalog", "palette"]

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  connect() {
    // ad: parse the embedded catalog JSON (auth-aware; rendered server-side)
    this._catalog       = this._parseCatalog()
    this._authenticated = isAuthenticated()

    // ad: initialise state
    this._mode         = "none"

    // Palette state (verb-stage slash/hashtag)
    this._paletteOpen  = false
    this._paletteRows  = []   // current list of catalog entries shown
    this._selectedIdx  = 0   // highlighted row index

    // ae arg-stage fetch state (slash/hashtag palette completion via /suggestions)
    this._argTimer     = null
    this._argRequestId = 0
    this._argAbort     = null

    // ag: belt-and-suspenders listener for Turbo stream renders that may swap
    // #pito-auth-gate (and therefore change auth state) without replacing the
    // chatbox.  If the chatbox IS replaced, connect() re-runs automatically.
    this._onTurboStream = () => {
      const wasAuthenticated = this._authenticated
      this._authenticated = isAuthenticated()
      if (wasAuthenticated !== this._authenticated) {
        // Re-parse catalog in case it was also replaced in the same stream.
        this._catalog = this._parseCatalog()
        // Re-evaluate suggestion in case auth change affects available commands
        this._refreshSuggestion()
      }
    }
    document.addEventListener("turbo:before-stream-render", this._onTurboStream)

    // Shift+R (with >1 live handle) asks us to present an inline hashtag picker
    // above the chatbox — reusing the same suggestions palette.
    this._onHashtagPickerOpen = (e) => this._openExternalHashtagPicker(e)
    document.addEventListener("pito:hashtag-picker:open", this._onHashtagPickerOpen)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this._onTurboStream)
    document.removeEventListener("pito:hashtag-picker:open", this._onHashtagPickerOpen)
    this._cancelArgFetch()
    this._closePalette()
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
        // Exact complete verb typed (no trailing space) → let Enter SUBMIT
        // instead of accepting a palette row. The palette is for discovery
        // while typing a PARTIAL verb; once the verb is complete, Enter sends.
        // Slash commands [owner I3] and — G75 — free chat verbs, where the
        // rule honors EVERY alias ("ls" + Enter sends, not just "list").
        if (this._isExactCompleteSlashVerb() || this._isExactCompleteChatVerb()) {
          this._closePalette()
          return   // no preventDefault → chat-form#handleKeydown submits the form
        }
        event.preventDefault()
        event.stopImmediatePropagation()
        this._acceptPaletteSelection()
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

    // Tab is NOT handled anywhere here (owner 2026-06-29, #9): the inline
    // suggestion/completion feature was removed, so the chatbox no longer
    // intercepts Tab at all — it behaves natively. (Shift+Tab channel cycling
    // lives in chat-form#handleKeydown and is untouched.)
    //
    // All keys pass through to chat-form#handleKeydown and
    // home-transition#interceptEnter without suppression.
  }

  // ad: recompute mode and refresh palette on every input event
  onInput(event) {
    // History cycling dispatches a synthetic input (detail.historyRecall=true) so
    // other controllers (draft, caret, type-fx) rerender — skip opening palette
    // here so a recalled slash entry ("/games") doesn't open the verb palette
    // and intercept the next ↑/↓ that the user intends for history navigation.
    if (event.detail?.historyRecall) {
      this._closePalette()
      this._cancelArgFetch()
      return
    }

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

  // ── ae: unified suggestion refresh (palette for verb/reply-verb/config stages) ──

  _refreshSuggestion() {
    const field  = this.fieldTarget
    const value  = field.value
    const cursor = field.selectionStart ?? value.length

    if (this._mode === "slash" || this._mode === "hashtag") {
      if (this._isArgStage(value, cursor)) {
        // Hashtag REPLY-VERB stage (`#<handle> <verb>`): the verb sits after the
        // handle's space, so it trips _isArgStage — but it is a VERB choice, not
        // an arg. Fetch the full allowed-verb list and surface it as a PALETTE
        // (the engine tags this response stage:"verb"). Keep any open palette up
        // (don't blink-close) while the debounced fetch refreshes its rows.
        if (this._isHashtagReplyVerbStage(value, cursor)) {
          this._scheduleArgFetch(value, cursor)
          return
        }

        // Slash `/config <arg>` arg stage: the engine returns these completions
        // as a browsable PALETTE (stage:"verb"), so keep any open palette up while
        // the debounced fetch refreshes its rows — same no-blink treatment as the
        // hashtag reply-verb stage. (Other slash args get no suggestions.)
        if (this._isSlashConfigArgStage(value, cursor)) {
          this._scheduleArgFetch(value, cursor)
          return
        }

        // Other arg-stage (E13): the engine now serves ARGUMENT menus for
        // hashtag reply verbs (columns for with/without, sort keys, metrics,
        // row ids, enum args) — ask it; an empty menu closes the palette via
        // the fetch handler, so no-arg verbs behave exactly as before.
        this._scheduleArgFetch(value, cursor)
        return
      }

      // Verb-stage: cancel arg fetch, show palette
      this._cancelArgFetch()
      this._refreshVerbPalette(value, cursor)
    } else if (this._mode === "free") {
      // Free mode (E8/T3.4): chat verbs have server-side argument suggestions
      // (segment names after `show game 5 `, nouns, subcommands, game titles…).
      // Debounced fetch; the engine returns empty for genuinely free prose and
      // the empty menu keeps the palette closed.
      this._scheduleArgFetch(value, cursor)
    } else {
      // none — clear everything
      this._closePalette()
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

  // Render server-fetched menu_items as a verb palette (hashtag reply-verb stage).
  // Unlike _refreshVerbPalette, the rows carry an explicit `label` (the verb word
  // shown verbatim — no leading "#"/"/" glyph) and the engine-supplied `insert`
  // (e.g. "show ") which _insertToken splices over the partial verb token.
  _showFetchedPalette(menuItems, triggerChar) {
    this._paletteRows = menuItems.map((it) => ({
      label:       it.label,
      name:        it.label,
      insert:      it.insert,
      description: it.description || "",
    }))
    this._paletteTrigger = triggerChar || "#"
    this._selectedIdx    = 0
    this._renderPalette()
  }

  // Open the inline suggestions palette with an explicit set of hashtag handles.
  // Called when `pito:hashtag-picker:open` fires (shift+r with >1 live handle).
  // Reuses _renderPalette / _acceptPaletteSelection / _closePalette unchanged.
  _openExternalHashtagPicker(e) {
    if (!this._authenticated) return
    const handles = e?.detail?.handles
    if (!Array.isArray(handles) || handles.length === 0) return

    // Cancel any pending fetches before taking over the palette.
    this._cancelArgFetch()

    // Set mode to "hashtag" so _insertToken uses verb-stage logic (prepend at 0).
    this._mode = "hashtag"
    this._paletteRows    = handles.map(h => ({ name: String(h), insert: `#${h} ` }))
    this._paletteTrigger = "#"
    this._selectedIdx    = 0
    this._renderPalette()

    // Ensure the chatbox field is focused so Arrow/Enter/Esc work immediately.
    this.fieldTarget.focus({ preventScroll: true })
  }

  // Render the palette DOM rows inside the palette target element.
  _renderPalette() {
    const palette = this.paletteTarget
    palette.innerHTML = ""

    this._paletteRows.forEach((entry, idx) => {
      const row = document.createElement("div")
      row.className = "pito-suggestions-row" + (idx === this._selectedIdx ? " is-selected" : "")
      const cmd = document.createElement("span")
      cmd.className   = "pito-suggestions-cmd"
      // Verb palettes (hashtag reply verbs) carry an explicit label shown
      // verbatim; trigger-prefixed palettes (slash verbs, hashtag handles) glue
      // the "/" or "#" glyph onto the entry name.
      cmd.textContent = entry.label != null
        ? entry.label
        : ((this._paletteTrigger || "/") + (entry.name || ""))
      row.appendChild(cmd)
      if (entry.description) {
        const desc = document.createElement("span")
        desc.className   = "pito-suggestions-desc"
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
    const rows    = palette.querySelectorAll(".pito-suggestions-row")
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

  // Hashtag reply-verb stage: the cursor is choosing the VERB right after
  // `#<handle> ` (e.g. `#alpha-1266 sh`), before that verb is finalised by a
  // second space. Mirrors the engine's at_verb_stage for follow-up handles.
  // The handle may contain hyphens, so we key off the FIRST space (which always
  // ends the handle) and require no further space in the remainder.
  //   "#h "        → true   (empty partial verb)
  //   "#h sh"      → true   (typing the verb)
  //   "#h show "   → false  (verb finalised → arg stage)
  //   "#h with co" → false  (arg stage)
  _isHashtagReplyVerbStage(value, cursor) {
    if (value[0] !== "#") return false
    const before     = value.slice(0, cursor)
    const firstSpace = before.indexOf(" ")
    if (firstSpace === -1) return false           // still typing the handle
    const rest = before.slice(firstSpace + 1)     // text after "#<handle> "
    return !rest.includes(" ")
  }

  // FREE-mode (chat verb) argument menu at a FRESH token: `list `, `show game
  // 5 with `, … — the engine serves chat verbs' nouns/segments/kwargs tagged
  // stage:"verb" (E8), but no gate rendered them, so the fetched items were
  // discarded exactly like the reply-arg case (owner G31, same bug class).
  // Fresh-token rule as everywhere: trailing space → palette; mid-token →
  // closed so Enter sends the message.
  _isFreeArgFreshToken(value, cursor) {
    if (value[0] === "#" || value[0] === "/") return false
    const before = value.slice(0, cursor)
    return before.trim().length > 0 && before.endsWith(" ")
  }

  // FREE-mode VERB stage (G75): the FIRST word of a chat message is a verb in
  // progress ("l", "lis", "analy") — the engine prefix-filters the chat
  // catalog (alias-aware) and tags it stage:"verb". Unlike the ARG stage's
  // fresh-token rule, the palette stays open WHILE TYPING mid-token — that's
  // the discovery behavior slash verbs have always had; Enter on an
  // exact-complete verb still sends (handled in handleKeydown, alias-aware).
  //   "l"        → true   (typing the verb → palette)
  //   "lis"      → true
  //   "list "    → false  (that's the ARG stage, gated above)
  //   "#h l"     → false  (hashtag mode)
  _isFreeVerbStage(value, cursor) {
    if (value[0] === "#" || value[0] === "/") return false
    const before = value.slice(0, cursor)
    return before.trim().length > 0 && !before.includes(" ")
  }

  // True when the field holds an EXACT, complete free-chat verb — canonical
  // name OR any alias ("list", "ls") — with no trailing space. Mirrors
  // _isExactCompleteSlashVerb for the G75 verb stage: Enter must SEND the
  // bare verb (its default reading), not accept the highlighted row.
  _isExactCompleteChatVerb() {
    if (!this.hasFieldTarget) return false
    const field  = this.fieldTarget
    const value  = field.value
    if (value.length === 0 || value[0] === "#" || value[0] === "/") return false
    const cursor = field.selectionStart ?? value.length
    const before = value.slice(0, cursor)
    if (before.includes(" ")) return false        // past the verb → not verb stage
    const token = before.toLowerCase()
    return (this._catalog?.chat || []).some(e =>
      e.name.toLowerCase() === token ||
      (e.aliases || []).some(a => a.toLowerCase() === token),
    )
  }

  // Hashtag reply ARG stage at a FRESH token: `#<handle> <verb> [<args>] ` with
  // a trailing space. The engine serves the verb's argument menu here (columns
  // for with/without, sort keys, metrics, row ids — E13) tagged stage:"verb",
  // but this gate was never opened, so the fetched items were thrown away and
  // `#h with ` showed nothing (owner G26.5). Same fresh-token rule as the
  // /config gate: mid-token (`#h with cat`) stays closed so Enter sends.
  //   "#h with "      → true   (starting an arg token → palette)
  //   "#h with cat"   → false  (typing a partial → close; Enter sends)
  //   "#h with cat, " → true   (starting the next arg token)
  //   "#h sh"         → false  (that's the reply-VERB stage, gated separately)
  _isHashtagReplyArgStage(value, cursor) {
    if (value[0] !== "#") return false
    const before     = value.slice(0, cursor)
    const firstSpace = before.indexOf(" ")
    if (firstSpace === -1) return false           // still typing the handle
    const rest = before.slice(firstSpace + 1)     // text after "#<handle> "
    return rest.includes(" ") && before.endsWith(" ")
  }

  // Slash `/config <arg>` arg stage: the verb is `config` and the cursor sits at
  // the START of a fresh arg token — i.e. right after a TRAILING space. The engine
  // surfaces these completions (provider list, per-provider keys) as a browsable
  // palette (stage:"verb"); we keep that palette open ONLY when a trailing space
  // signals "I'm starting the next token". A COMPLETE token with no trailing space
  // (e.g. "/config google") must NOT pop the palette, so Enter can SEND the
  // read/default version of the command. Scoped to `config` (the only slash
  // verb with a server arg palette). [owner I3, 2026-06-26]
  //   "/config "          → true   (starting the provider token)
  //   "/config goo"       → false  (typing a partial token → close; Enter sends)
  //   "/config google"    → false  (complete token, no trailing space → Enter sends)
  //   "/config google "   → true   (starting the key token)
  //   "/games import x"   → false  (not config)
  _isSlashConfigArgStage(value, cursor) {
    if (value[0] !== "/") return false
    const before     = value.slice(0, cursor)
    const firstSpace = before.indexOf(" ")
    if (firstSpace === -1) return false           // still typing the verb
    const verb = before.slice(1, firstSpace).toLowerCase()
    if (verb !== "config") return false
    return before.endsWith(" ")                   // only at the start of a fresh token
  }

  // Verb-stage: true when the field holds an EXACT, complete slash command verb
  // with no trailing space (e.g. "/connect", "/config") — the text after "/"
  // equals a known catalog command name. Used so Enter SUBMITS the complete
  // command (its read/default version) instead of the open palette accepting a
  // row. A PARTIAL verb ("/conn") returns false → the palette still accepts on
  // Enter, preserving command discovery. Applies to every slash command.
  // [owner I3, 2026-06-26]
  _isExactCompleteSlashVerb() {
    if (!this.hasFieldTarget) return false
    const field  = this.fieldTarget
    const value  = field.value
    if (value[0] !== "/") return false
    const cursor = field.selectionStart ?? value.length
    const before = value.slice(0, cursor)
    if (before.indexOf(" ") !== -1) return false  // past the verb → not bare verb stage
    const verb = before.slice(1).toLowerCase()    // text after "/"
    if (verb.length === 0) return false
    return (this._catalog?.slash || []).some(e => e.name.toLowerCase() === verb)
  }

  // ── ae: arg-stage palette fetch (debounced POST /suggestions) ─────────────

  _scheduleArgFetch(value, cursor) {
    // Cancel previous pending timer or in-flight request
    this._cancelArgFetch()

    this._argTimer = setTimeout(() => {
      this._argTimer = null
      this._fetchArgSuggestions(value, cursor)
    }, ARG_DEBOUNCE_MS)
  }

  async _fetchArgSuggestions(value, cursor) {
    // Guard: a debounced fetch can fire after the controller's page (or the
    // test environment) has been torn down; bail rather than touch a vanished
    // `document`. Harmless in the browser (document always defined).
    if (typeof document === "undefined") return

    const myRequestId = ++this._argRequestId

    const abortCtrl    = new AbortController()
    this._argAbort     = abortCtrl

    const csrfToken      = document.querySelector('meta[name="csrf-token"]')?.content
    const uuidInput      = document.querySelector('input[name="uuid"]')
    const conversationId = uuidInput ? uuidInput.value : undefined

    const body = { input: value, cursor }
    if (conversationId) body.uuid = conversationId

    try {
      const resp = await fetch("/suggestions", {
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
        this._closePalette()
        return
      }

      const data = await resp.json()

      if (myRequestId !== this._argRequestId) return

      const menuItems = data.menu_items || []

      // VERB-STAGE PALETTE: the engine tags reply-verb (and /config arg)
      // responses with stage:"verb" — render the WHOLE list as a selectable
      // palette so every allowed verb (with/without/shinies/schedule/show/…) is
      // visible and arrow-navigable.
      if (data.stage === "verb") {
        if (menuItems.length === 0) {
          this._closePalette()
          return
        }
        // Render as a browsable palette ONLY when the cursor is at a fresh token:
        // a hashtag reply-verb (`#h sh`), or a slash `/config` arg right after a
        // trailing space (`/config google `). When typing WITHIN a slash token
        // (no trailing space, e.g. `/config google`) the server still tags the
        // response stage:"verb" — but we must NOT re-open the palette there, or it
        // would intercept Enter on a complete command. Fall through to close
        // so the token stays Enter-sendable. Slash-only rule;
        // hashtag reply verbs are unchanged. [owner I3, 2026-06-26]
        if (this._isHashtagReplyVerbStage(value, cursor) ||
            this._isSlashConfigArgStage(value, cursor) ||
            this._isHashtagReplyArgStage(value, cursor) ||
            this._isFreeArgFreshToken(value, cursor) ||
            this._isFreeVerbStage(value, cursor)) {
          this._showFetchedPalette(menuItems, value[0])
          return
        }
        // else: complete token with no trailing space — close palette so Enter sends
      }

      // Not a palette stage — close the palette
      this._closePalette()
    } catch (err) {
      if (myRequestId === this._argRequestId) {
        this._closePalette()
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

  // ae: replace the active token (the prefix that triggered the suggestion) with insert
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
    } else if (mode === "free" && this._isFreeVerbStage(value, cursor)) {
      // G75 verb-stage: splice over the partial verb the user is typing
      // ("li" + accept "link " → "link ", not "lilink ") — the free-mode
      // analogue of the slash verb-stage replace-from-0. Arg-stage free
      // accepts keep the plain insert-at-cursor below (the fresh-token rule
      // guarantees an empty partial there).
      tokenStart = value.length - value.trimStart().length  // past any leading spaces
      tokenEnd   = cursor
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
      console.warn("[pito--suggestions] Failed to parse catalog JSON:", e)
      return { slash: [], hashtag: [], chat: [], vocabularies: {} }
    }
  }
}
