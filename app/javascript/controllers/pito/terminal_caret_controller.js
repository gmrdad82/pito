// Pito::TerminalCaretController
//
// VERDICT: the ghost `Cursor::Component` is unsuitable as the chatbox
// caret — it is a fixed decorative "/" glyph that never tracks input and visually
// competes with the real (native) caret. A native caret cannot be a styled block
// (it is always a thin I-beam), and CSS `caret-shape: block` is not Baseline
// (~48% support) and cannot do the over-hint decoration or invert the covered glyph.
// Resolution: this controller draws a terminal-style BLOCK caret as an overlay.
//
// It hides the native caret and positions a blinking block over the glyph at the
// caret, inverting that glyph (bg-root on fg-default). The caret pixel math, the
// hidden mirror, the inverted-block render and the bubbling `pito:caret` emit all
// live in the shared TerminalCaretCore — this controller only binds DOM events,
// handles autofocus, and gates the blink on motion/reduced-motion.
//
// Works on the multi-line chatbox <textarea> (mode "textarea") AND the single-line
// sidebar / palette / rename <input>s (mode "input", auto-detected). In input mode
// the block is shown ONLY while that input is focused, so the five sidebar/palette
// inputs never paint five carets at once.
//
// Markup (textarea):
//   <div class="pito-chatbox__field-wrap" data-controller="pito--terminal-caret">
//     <textarea data-pito--terminal-caret-target="field" ...></textarea>
//     <span class="terminal-caret" data-pito--terminal-caret-target="block" aria-hidden="true"></span>
//   </div>
//
// Markup (input): same shape, the field is an <input>, wrap is `relative`, and the
// input carries `.pito-caret-input` (caret-color:transparent + monospace).

import { Controller } from "@hotwired/stimulus"
import TerminalCaretCore from "pito/terminal_caret_core"
import { motionDisabled } from "pito/settings"

export default class extends Controller {
  static targets = ["field", "block"]
  static values = { autofocus: Boolean }

  connect() {
    this.field = this.hasFieldTarget ? this.fieldTarget : this.element
    this.core = new TerminalCaretCore({
      field: this.field,
      block: this.blockTarget,
      host: this.element,
    })
    this.singleLine = this.core.singleLine
    this.core.mount()
    this.#bind()
    this.core.autosize()
    if (this.autofocusValue) {
      this.field.focus({ preventScroll: true })
      // Restored drafts (and conversation switches) re-render the field with its
      // saved text; focus() alone leaves the caret at position 0. Move it to the
      // end so the user continues typing from where they left off.
      const end = this.field.value.length
      this.field.selectionStart = this.field.selectionEnd = end
    }
    const focused = document.activeElement === this.field
    this.#setFocusState(focused)
    this.core.render()
    // Emit initial focus state so a late-connecting chatbox-hints controller
    // gets the correct value even if it missed the autofocus event. (chatbox only)
    if (!this.singleLine) this.#emitFocus(focused)

    // Robust to focus timing (input mode only). The five single-line inputs are
    // focused by their OWN sibling controllers — games-search (rAF), games-nav /
    // videos-nav (rAF), command-palette (#open), rename (programmatic) — whose
    // focus() can land around our connect, beating both the one-time activeElement
    // check above (which only catches focus that ALREADY happened) and, in some
    // orderings, our focus listener. So re-assert visibility from the LIVE
    // activeElement on the next microtask AND animation frame: whenever the field
    // is (or has become) the active element by then, the block is shown — we never
    // depend on having observed the focus transition. Idempotent and blur-safe (a
    // resync while blurred keeps it hidden, preserving "only the focused input shows
    // a block"). The textarea/chatbox path is always-visible and not scheduled.
    if (this.singleLine) {
      queueMicrotask(() => this.#resyncVisibility())
      requestAnimationFrame(() => this.#resyncVisibility())
    }

    // Gate the blink on motion/reduced-motion, live — `/config fx off` replaces
    // #pito-settings' data-fx, so the block flips to a solid (no-blink) cursor
    // without a reload. Mirrors the pito--sidebar-fx pattern.
    this.#applyMotion()
    const settings = document.getElementById("pito-settings")
    if (settings) {
      this.motionObserver = new MutationObserver(() => this.#applyMotion())
      this.motionObserver.observe(settings, { attributes: true, attributeFilter: ["data-fx"] })
    }

    // The self-hosted monospace webfont can finish loading AFTER this connect's
    // first render — leaving the block caret 1–2px below the text line until the
    // next reflow (previously fixed only incidentally when the showcase ghost's
    // first reveal read offsetTop). Re-render on the next frame AND once fonts are
    // ready so the caret sits on the line from the start. Idempotent; guarded for
    // jsdom (no requestAnimationFrame/document.fonts) and aborted after disconnect.
    const resync = () => {
      if (this.abort?.signal.aborted) return
      this.core.autosize()
      this.core.render()
    }
    if (typeof requestAnimationFrame === "function") requestAnimationFrame(resync)
    if (typeof document !== "undefined" && document.fonts?.ready) {
      document.fonts.ready.then(resync)
    }
  }

  disconnect() {
    this.abort?.abort()
    this.resizeObserver?.disconnect()
    this.motionObserver?.disconnect()
    this.core?.teardown()
  }

  // Public passthroughs (kept for sibling controllers / back-compat).
  autosize() { this.core.autosize() }
  render() { this.core.render() }
  caretCoords() { return this.core.caretCoords() }

  // ── internals ──────────────────────────────────────────────────────────────

  // Solid block + no blink when motion is off (consistent with the trail being
  // disabled). data-no-blink kills the @keyframes animation in CSS.
  #applyMotion() {
    this.blockTarget.toggleAttribute("data-no-blink", motionDisabled())
  }

  // Re-assert focus-driven visibility from the live activeElement (input mode).
  // Whenever the field is the active element the block MUST be visible — this does
  // not rely on having observed the focus event, so a sibling controller's focus()
  // that landed around connect is honoured. Bails after disconnect.
  #resyncVisibility() {
    if (this.abort?.signal.aborted) return
    const focused = document.activeElement === this.field
    this.#setFocusState(focused)
    if (focused) this.core.render()
  }

  #emitFocus(focused) {
    document.dispatchEvent(new CustomEvent("pito:focus", {
      bubbles: false,
      detail: { focused: !!focused },
    }))
  }

  // textarea: block always present, blinks when blurred.
  // input:    block shown only while focused (never five carets at once).
  #setFocusState(focused) {
    this.core.setActive(focused)
    if (this.singleLine) this.core.setVisible(focused)
  }

  #bind() {
    this.abort = new AbortController()
    const { signal } = this.abort
    const onCaretMove = () => { this.core.render(); this.core.emitCaret() }
    const onInput = () => { this.core.autosize(); this.core.render(); this.core.emitCaret() }
    const onFocus = () => {
      this.#setFocusState(true)
      if (!this.singleLine) this.#emitFocus(true)
      this.core.render(); this.core.emitCaret()
    }
    const onBlur = () => {
      this.#setFocusState(false)
      if (!this.singleLine) this.#emitFocus(false)
      this.core.render()
    }

    this.field.addEventListener("input", onInput, { signal })
    this.field.addEventListener("keyup", onCaretMove, { signal })
    this.field.addEventListener("click", onCaretMove, { signal })
    this.field.addEventListener("focus", onFocus, { signal })
    this.field.addEventListener("blur", onBlur, { signal })
    this.field.addEventListener("scroll", onCaretMove, { signal })
    // `input` does not fire when the field is cleared programmatically (e.g. the
    // chat form on submit) — that path dispatches its own "input" event.
    document.addEventListener("selectionchange", () => {
      if (document.activeElement === this.field) { this.core.render(); this.core.emitCaret() }
    }, { signal })

    // Re-sync mirror width + re-grow when the field is resized by layout.
    if (typeof ResizeObserver !== "undefined") {
      this.resizeObserver = new ResizeObserver(() => {
        this.core.syncMirrorWidth()
        this.core.autosize()
        this.core.render()
      })
      this.resizeObserver.observe(this.field)
    }
  }
}
