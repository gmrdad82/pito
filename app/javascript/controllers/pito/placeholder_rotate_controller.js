// pito--placeholder-rotate
//
// Cycles a field's native `placeholder` through a list of hints every `interval`
// ms. This REPLACES the old comet-revealed "showcase ghost": instead of painting
// an overlay span at the caret (which depended on the bespoke caret machinery),
// the hints now ride the browser's own placeholder — zero overlay, zero caret
// coupling. The placeholder is naturally hidden the moment the user types, so no
// focus/empty gating is needed here.
//
// The hint list is the SAME server-built set the showcase used
// (Pito::Showcase::Builder → the #pito-showcase-data <script>), so the hints stay
// context-aware and are refreshed after every turn via a Turbo Stream replace of
// that element (observed below).
//
// DOM contract (chatbox ERB):
//   Controller pito--placeholder-rotate on #pito-chatbox.
//   Targets:
//     data  — <script type="application/json"> holding a JSON array of hints.
//     field — the <textarea> whose placeholder is rotated.
//   Values:
//     interval (Number, default 10000) — ms between placeholder swaps.
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["data", "field"]
  static values  = { interval: { type: Number, default: 10000 } }

  connect() {
    this._hints   = []
    this._index   = 0
    this._timer   = null
    // Remember the server-rendered placeholder so we can put it back on teardown.
    this._original = this.hasFieldTarget ? this.fieldTarget.getAttribute("placeholder") : null

    this._loadHints()
    this._bindDataObserver()
    this._start()
  }

  disconnect() {
    this._stop()
    this._restoreOriginal()
    this._unbindDataObserver()
  }

  // ── Hints data ───────────────────────────────────────────────────────────────

  _loadHints() {
    if (!this.hasDataTarget) { this._hints = []; return }
    try {
      const parsed = JSON.parse(this.dataTarget.textContent || "[]")
      this._hints = Array.isArray(parsed) ? parsed.filter(h => typeof h === "string" && h.length) : []
    } catch (_) {
      this._hints = []
    }
    this._index = 0
  }

  // ── Rotation ─────────────────────────────────────────────────────────────────

  _start() {
    if (this._hints.length === 0) return  // nothing to rotate → keep the original
    if (this._timer !== null) return      // already running
    // First swap fires after one interval, so the server-rendered placeholder is
    // shown first; subsequent swaps cycle through the hints.
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
    this._start()
  }

  _showNext() {
    if (!this.hasFieldTarget || this._hints.length === 0) return
    this.fieldTarget.setAttribute("placeholder", this._hints[this._index])
    this._index = (this._index + 1) % this._hints.length
  }

  _restoreOriginal() {
    if (this.hasFieldTarget && this._original != null) {
      this.fieldTarget.setAttribute("placeholder", this._original)
    }
  }

  // ── Turbo Stream replace of #pito-showcase-data ────────────────────────────────

  _bindDataObserver() {
    this._dataObserver = new MutationObserver((mutations) => {
      for (const m of mutations) {
        for (const node of m.addedNodes) {
          if (node.id === "pito-showcase-data") {
            this._loadHints()
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
}
