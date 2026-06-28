// pito--chat-showcase
//
// Cycles context-aware command suggestions as comet-revealed ghosts in the chatbox
// whenever it is EMPTY (no value typed). The set is seeded by the server in a
// <script id="pito-showcase-data" type="application/json"> element and refreshed
// after every turn via a Turbo Stream replace of that element.
//
// BEHAVIOUR
//   Empty chatbox  → every `interval` ms a new suggestion is revealed via the CSS
//                    comet sweep (.pito-comet-reveal) on the ghost, and the
//                    textarea's native placeholder is hidden so the cycling ghost
//                    IS the hint (no overlap). Cycling is FOCUS-INDEPENDENT — the
//                    chatbox autofocuses on load, so pausing on focus would mean
//                    it never cycles.
//   Value typed    → ghost hidden, cycling stops, native placeholder restored.
//   Cleared to ""  → cycling restarts.
//   Turbo replace of #pito-showcase-data → reload the set, restart from index 0.
//
// DOM contract (set by the chatbox ERB):
//   Controller pito--chat-showcase on #pito-chatbox; targets: data (the JSON
//   <script>), item (.pito-showcase-ghost), field (the <textarea>).
//
// Values: interval (Number, default 10000) — ms between suggestion cycles.

import { Controller } from "@hotwired/stimulus"

const COMET_MS = 900 // matches the CSS default --pito-comet-ms

export default class extends Controller {
  static targets = ["data", "item", "field"]
  static values  = { interval: { type: Number, default: 10000 } }

  connect() {
    this._suggestions = []
    this._index       = 0
    this._timer       = null
    this._caret       = null
    // Remember the native placeholder so we can hide it while cycling and put it
    // back when a value is typed (or there are no suggestions).
    this._placeholder = this.hasFieldTarget ? this.fieldTarget.getAttribute("placeholder") : null

    this._loadSuggestions()
    this._bindField()
    this._bindCaret()
    this._bindDataObserver()
    this._maybeStart()
  }

  disconnect() {
    this._stop()
    this._restorePlaceholder()
    this._unbindField()
    this._unbindCaret()
    this._unbindDataObserver()
  }

  // ── Suggestions data ─────────────────────────────────────────────────────────

  _loadSuggestions() {
    if (!this.hasDataTarget) return
    try {
      const parsed = JSON.parse(this.dataTarget.textContent || "[]")
      this._suggestions = Array.isArray(parsed) ? parsed : []
    } catch (_) {
      this._suggestions = []
    }
    this._index = 0
  }

  // ── Field input (cycle on empty, stop on value) ──────────────────────────────

  _bindField() {
    if (!this.hasFieldTarget) return
    this._onInput = () => this._handleInput()
    this.fieldTarget.addEventListener("input", this._onInput)
  }

  _unbindField() {
    if (this.hasFieldTarget && this._onInput) {
      this.fieldTarget.removeEventListener("input", this._onInput)
    }
  }

  // ── Caret tracking (align the ghost with the REAL caret) ─────────────────────
  // The terminal-caret core emits a bubbling `pito:caret {left, top}` with the
  // caret's exact pixel position in the field-wrap frame (computed via its hidden
  // mirror — the single source of truth the cursor-trail also consumes). We cache
  // it and place the ghost there so the hint sits on the SAME row as the caret,
  // instead of the textarea's border-box top (which dropped it a row below).

  _bindCaret() {
    this._onCaret = (e) => {
      if (e.detail) this._caret = { left: e.detail.left, top: e.detail.top }
    }
    this.element.addEventListener("pito:caret", this._onCaret)
  }

  _unbindCaret() {
    if (this._onCaret) this.element.removeEventListener("pito:caret", this._onCaret)
  }

  _handleInput() {
    if (this._fieldEmpty()) {
      this._maybeStart()
    } else {
      this._stop()
      this._hideItem()
      this._restorePlaceholder()
    }
  }

  // ── Turbo Stream replace of #pito-showcase-data ──────────────────────────────

  _bindDataObserver() {
    this._dataObserver = new MutationObserver((mutations) => {
      for (const m of mutations) {
        for (const node of m.addedNodes) {
          if (node.id === "pito-showcase-data") {
            this._loadSuggestions()
            this._restart()
            return
          }
        }
      }
    })
    this._dataObserver.observe(this.element, { childList: true })
  }

  _unbindDataObserver() {
    if (this._dataObserver) {
      this._dataObserver.disconnect()
      this._dataObserver = null
    }
  }

  // ── Cycling ──────────────────────────────────────────────────────────────────

  _maybeStart() {
    if (this._suggestions.length === 0) return // no suggestions → keep native placeholder
    if (!this._fieldEmpty()) return            // a value is typed → no cycling
    if (this._timer !== null) return           // already running

    this._clearPlaceholder() // the cycling ghost IS the hint — no native-placeholder overlap
    this._showNext()
    this._timer = setInterval(() => this._showNext(), this.intervalValue)
  }

  _stop() {
    if (this._timer !== null) {
      clearInterval(this._timer)
      this._timer = null
    }
  }

  _restart() {
    this._stop()
    this._index = 0
    this._maybeStart()
  }

  _showNext() {
    if (this._suggestions.length === 0 || !this.hasItemTarget) return
    const text = this._suggestions[this._index]
    this._index = (this._index + 1) % this._suggestions.length
    this._revealItem(text)
  }

  // Comet-reveal the ghost, then hold it visible until the next cycle.
  _revealItem(text) {
    if (!this.hasItemTarget) return
    const item = this.itemTarget

    if (this.hasFieldTarget) {
      const cs = getComputedStyle(this.fieldTarget)
      item.style.fontFamily    = cs.fontFamily
      item.style.fontSize      = cs.fontSize
      item.style.fontWeight    = cs.fontWeight
      item.style.lineHeight    = cs.lineHeight
      item.style.letterSpacing = cs.letterSpacing
      const at = this._caretOrigin(cs)
      item.style.top  = `${at.top}px`
      item.style.left = `${at.left}px`
    }

    item.textContent = text
    item.classList.remove("pito-comet-reveal", "is-visible")
    void item.offsetWidth // reflow so the animation re-fires
    item.style.setProperty("--pito-comet-ms", `${COMET_MS}ms`)
    item.classList.add("pito-comet-reveal", "is-visible")

    if (this._cometTimer) clearTimeout(this._cometTimer)
    this._cometTimer = setTimeout(() => {
      if (item.isConnected) item.classList.remove("pito-comet-reveal")
    }, COMET_MS)
  }

  _hideItem() {
    if (!this.hasItemTarget) return
    this.itemTarget.classList.remove("pito-comet-reveal", "is-visible")
    this.itemTarget.textContent = ""
  }

  // ── Native placeholder management ────────────────────────────────────────────

  _clearPlaceholder() {
    if (this.hasFieldTarget && this._placeholder != null) this.fieldTarget.setAttribute("placeholder", "")
  }

  _restorePlaceholder() {
    if (this.hasFieldTarget && this._placeholder != null) this.fieldTarget.setAttribute("placeholder", this._placeholder)
  }

  // Where the ghost's first glyph should sit (field-wrap frame). Prefer the live
  // caret coords from `pito:caret`; otherwise replicate the caret core's
  // index-0 math — the textarea's text origin is its border-box origin PLUS its
  // own top/left border + padding (where the caret and typed glyphs render). The
  // ghost cycles only while EMPTY, so the caret is always at index 0 (a fixed
  // point), making the fallback exact.
  _caretOrigin(cs) {
    if (this._caret) return this._caret
    const insetTop  = (parseFloat(cs.borderTopWidth)  || 0) + (parseFloat(cs.paddingTop)  || 0)
    const insetLeft = (parseFloat(cs.borderLeftWidth) || 0) + (parseFloat(cs.paddingLeft) || 0)
    return {
      top:  (this.fieldTarget.offsetTop  || 0) + insetTop,
      left: (this.fieldTarget.offsetLeft || 0) + insetLeft,
    }
  }

  _fieldEmpty() {
    return this.hasFieldTarget ? this.fieldTarget.value === "" : true
  }
}
