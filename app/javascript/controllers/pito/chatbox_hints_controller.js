// pito--chatbox-hints
//
// Drives the single-row meta-line hints inside #pito-chatbox (item 10, owner
// 2026-06-29). Exactly ONE hint shows at a time, chosen from the chatbox focus
// state AND the leading verb/noun the owner is typing:
//
//   unfocused                                   → chatHint      (`m to start chatting`)
//   focused + `list` + a vids/games noun        → shiftTabHint  (channel cycler)
//   focused + `analyze`                          → shiftSpaceHint (period cycler)
//   focused + anything else (empty / other verb) → nothing
//
// Focus alone NO LONGER reveals the cyclers — shift+tab only makes sense for
// `list vids/games` and shift+space only for `analyze`; chat-form gates the
// keystrokes and the form submission on the same visibility.
//
// The controller only manages the default-state row (which carries all three
// targets). The start-screen / 404 / /share rows render a static always-on
// `m` hint with no targets, so `_apply` no-ops there (hasXTarget == false).
//
// Visibility note: `.inline-flex` and `.hidden` are both display utilities with
// equal specificity, so we SWAP the class (add one, remove the other) rather than
// rely on one overriding the other.

import { Controller } from "@hotwired/stimulus"

// Leading-verb / noun vocabulary, mirroring the server grammar aliases. Kept
// small + local: these four sets are stable and only gate which hint shows.
const LIST_VERBS    = [ "list", "ls" ]
const ANALYZE_VERBS = [ "analyze", "analytics", "stats" ]
const VID_NOUNS     = [ "vid", "vids", "video", "videos" ]
const GAME_NOUNS    = [ "game", "games", "gamez" ]

export default class extends Controller {
  static targets = ["chatHint", "shiftTabHint", "shiftSpaceHint"]

  connect() {
    this._focused = this.#computeFocused()

    this._onFocus    = (e) => { this._focused = !!(e.detail && e.detail.focused); this._apply() }
    this._onFocusIn  = () => this.#recheck()
    this._onFocusOut = () => this.#recheck()
    this._onInput    = () => this._apply()

    document.addEventListener("pito:focus", this._onFocus)
    document.addEventListener("focusin",    this._onFocusIn)
    document.addEventListener("focusout",   this._onFocusOut)
    this.element.addEventListener("input",  this._onInput)

    this._apply()
    // Catch the child pito--autosize autofocus that fires right after connect.
    requestAnimationFrame(() => this.#recheck())
  }

  disconnect() {
    document.removeEventListener("pito:focus", this._onFocus)
    document.removeEventListener("focusin",    this._onFocusIn)
    document.removeEventListener("focusout",   this._onFocusOut)
    this.element.removeEventListener("input",  this._onInput)
  }

  // ── Private ──────────────────────────────────────────────────────────────────

  #computeFocused() {
    const a = document.activeElement
    return !!(a && a.closest && a.closest("#pito-chatbox"))
  }

  #recheck() {
    const f = this.#computeFocused()
    if (f !== this._focused) {
      this._focused = f
      this._apply()
    }
  }

  // Which hint to show: "m" | "shiftTab" | "shiftSpace" | "none".
  #mode() {
    if (!this._focused) return "m"

    const field = this.element.querySelector("textarea")
    const text  = (field ? field.value : "").trim().toLowerCase()
    if (text === "") return "none"

    const tokens = text.split(/\s+/)
    const verb   = tokens[0]

    if (ANALYZE_VERBS.includes(verb)) return "shiftSpace"
    if (LIST_VERBS.includes(verb) &&
        tokens.slice(1).some((t) => VID_NOUNS.includes(t) || GAME_NOUNS.includes(t))) {
      return "shiftTab"
    }
    return "none"
  }

  _apply() {
    // No-op on rows without the targets (start screen / 404 / share static hint).
    if (!this.hasChatHintTarget && !this.hasShiftTabHintTarget && !this.hasShiftSpaceHintTarget) return

    const mode = this.#mode()
    if (this.hasChatHintTarget)       this.#setVisible(this.chatHintTarget,       mode === "m")
    if (this.hasShiftTabHintTarget)   this.#setVisible(this.shiftTabHintTarget,   mode === "shiftTab")
    if (this.hasShiftSpaceHintTarget) this.#setVisible(this.shiftSpaceHintTarget, mode === "shiftSpace")
  }

  // Swap display classes (never leave inline-flex + hidden fighting).
  #setVisible(el, visible) {
    el.classList.toggle("inline-flex", visible)
    el.classList.toggle("hidden", !visible)
  }
}
