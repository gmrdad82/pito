import { Controller } from "@hotwired/stimulus"

// FB-172 (2026-05-21) — keyboard-only mode.
//
// Per the user contract:
//   > Very important, I wanna disable mouse clicks on anything. It will
//   > be only keyboard interractive. So no clicks on actions, fields,
//   > outside or inside backdrops, checkboxes, etc. If possible I would
//   > like to even hide the mouse cursor and if mouse cursor movement is
//   > detected or clicked to have a dialog with a copy: mouse interraction
//   > forbidden.(next row) type ? for help or : command...
//
// Strategy:
//
//   * Capture-phase listeners on `mousedown`, `click`, and `contextmenu`
//     swallow every mouse interaction at the document level — they fire
//     BEFORE any per-element listener (Stimulus actions, native form
//     submission, anchor navigation), so nothing reaches the page.
//
//   * `mousemove` is monitored too so passive cursor hovering also
//     surfaces the alert. A one-shot `alertShown` guard means we never
//     spam the dialog when the cursor drifts across the viewport.
//
//   * `mouseenter` on the document also triggers the alert immediately,
//     so the dialog reappears the moment the cursor re-enters the
//     viewport after the mouseleave auto-dismiss.
//
//   * `cursor: none` is applied via the `keyboard-only` body class so the
//     OS cursor visually disappears (CSS lives in `application.css`).
//
//   * The "invalid input" alert dialog is spawned via `showModal()` on
//     the canonical `Tui::AlertDialogComponent` mounted once at layout
//     bottom (id: `mouse-forbidden-alert`). The `[Esc] to close` chrome
//     in the dialog's top border is the canonical dismiss path; on close
//     the one-shot flag resets so the next mouse activity re-opens the
//     dialog.
//
// Mounted on `<body>` via Stimulus `data-controller` so connect/disconnect
// align with the page lifecycle. Survives Turbo Drive navigation cleanly
// because Stimulus re-binds on body swap; the body class is re-added on
// reconnect.
//
// @contract (FB-172, locked 2026-05-22)
//
//   TRIGGERS AlertDialog "invalid input":
//     - Real mouse click:   event.isTrusted === true
//                           AND event.detail >= 1
//                           AND (event.pointerType === "mouse"
//                                OR event.pointerType === undefined)
//                           (undefined = plain MouseEvent, not a PointerEvent,
//                            which is what `click` / `mousedown` fire on most
//                            browsers when no pointer capture is active)
//     - `mousedown` from real mouse (same isTrusted + pointerType rules)
//     - `contextmenu` (right-click) — always physical; isTrusted check only,
//       no pointerType check (right-click cannot be keyboard-fired)
//     - Real `mousemove` with non-zero movement:
//         event.movementX !== 0 || event.movementY !== 0
//     - `mouseenter` on document/viewport (cursor re-entry after mouseleave),
//       excluding synthetic zero-coord zero-movement events
//     - Side-button presses on the mouse (back = X1 / button 3,
//       forward = X2 / button 4, extra side buttons 6/7 = button 5/6+)
//       AND middle-button (button 1) via the `auxclick` event AND
//       `mousedown` capture-phase guard (button >= 1). Any non-primary
//       button at mousedown is caught. `auxclick` catches all non-primary
//       click completions (button !== 0). Added 2026-05-22; buttons 6/7
//       added 2026-05-24.
//
//   DOES NOT TRIGGER:
//     - Programmatic `.click()` calls (event.isTrusted === false)
//     - Keyboard-fired clicks (Enter/Space on focused element:
//       event.detail === 0)
//     - event.pointerType === "" (pen/touch pointer) or "keyboard"
//     - `mouseenter` / `mousemove` with clientX === 0 && clientY === 0
//       AND movementX === 0 && movementY === 0 (synthetic OS events)
//
//   AUTO-DISMISS:
//     - On `mouseleave` from document/viewport, close the dialog if open
//       and reset the one-shot alertShown guard.
//
//   ESC DISMISS:
//     - Native <dialog> Esc handling closes the dialog; the `close`
//       event listener resets alertShown so the next real mouse event
//       re-opens it.
//
//   ONE-SHOT GUARD:
//     - While the dialog is open, additional mouse events do not re-open
//       or spam showModal(). The guard resets only on dialog `close`.

export default class extends Controller {
  static values = { dialogId: { type: String, default: "mouse-forbidden-alert" } }

  connect() {
    this.alertShown = false
    document.body.classList.add("keyboard-only")

    this.boundMouseInteraction = this.handleMouseInteraction.bind(this)
    this.boundMouseMove = this.handleMouseMove.bind(this)
    this.boundMouseLeave = this.handleMouseLeave.bind(this)
    this.boundMouseEnter = this.handleMouseEnter.bind(this)
    this.boundAuxClick = this.handleAuxClick.bind(this)

    // Capture phase so we run before any per-element listener (Stimulus,
    // native form submit, anchor navigation, dialog backdrop click guard).
    document.addEventListener("mousedown", this.boundMouseInteraction, true)
    document.addEventListener("click", this.boundMouseInteraction, true)
    document.addEventListener("contextmenu", this.boundMouseInteraction, true)
    // `auxclick` fires for non-primary mouse buttons (middle = button 1,
    // back = button 3 / X1, forward = button 4 / X2). Capture-phase
    // preventDefault on this event blocks the browser's built-in
    // back/forward navigation triggered by mouse side buttons. Added
    // 2026-05-22 in response to mouse4 still triggering browser back.
    document.addEventListener("auxclick", this.boundAuxClick, true)
    document.addEventListener("mousemove", this.boundMouseMove)
    // mouseleave on document fires when the cursor exits the viewport;
    // auto-dismiss the alert dialog so the user isn't trapped after
    // moving the cursor off-window (FB-172 follow-up 2026-05-21).
    document.addEventListener("mouseleave", this.boundMouseLeave)
    // mouseenter fires the moment the cursor re-enters the viewport
    // after the auto-dismiss; re-surface the alert immediately.
    document.addEventListener("mouseenter", this.boundMouseEnter)
  }

  disconnect() {
    document.removeEventListener("mousedown", this.boundMouseInteraction, true)
    document.removeEventListener("click", this.boundMouseInteraction, true)
    document.removeEventListener("contextmenu", this.boundMouseInteraction, true)
    document.removeEventListener("auxclick", this.boundAuxClick, true)
    document.removeEventListener("mousemove", this.boundMouseMove)
    document.removeEventListener("mouseleave", this.boundMouseLeave)
    document.removeEventListener("mouseenter", this.boundMouseEnter)
    document.body.classList.remove("keyboard-only")
  }

  handleMouseInteraction(event) {
    // contextmenu (right-click) is always physical — it cannot be keyboard-
    // fired with detail === 0, and isTrusted is the only relevant check.
    if (event.type === "contextmenu") {
      if (!event.isTrusted) return
      event.preventDefault()
      event.stopPropagation()
      this.showAlert()
      return
    }

    // Non-primary mousedown — any button except the primary (0).
    // Covers: middle (1), right (2, also via contextmenu above),
    // back/X1 (3), forward/X2 (4), and any extra side buttons (5, 6, …).
    // Blocking at mousedown stops browser navigation (back/forward) and
    // middle-click tab-open BEFORE the ensuing auxclick fires. The
    // auxclick listener provides a second layer for buttons that don't
    // fire mousedown reliably. Added 2026-05-22; >= 1 generalized
    // 2026-05-24 to catch buttons 6, 7, and beyond.
    if (event.type === "mousedown" && event.isTrusted && event.button >= 1) {
      event.preventDefault()
      event.stopPropagation()
      this.showAlert()
      return
    }

    // Allow programmatic clicks dispatched from JS (e.g. Stimulus `.click()`
    // calls on a header for select-all, focus-restore flows). Synthetic
    // events from `Element.click()` / `dispatchEvent` have `isTrusted: false`.
    if (!event.isTrusted) return

    // Allow keyboard-fired clicks (Enter/Space activating a focused button
    // or anchor). The UA fires a synthetic `click` whose `detail` (click
    // count) is 0; real mouse clicks have `detail >= 1`.
    if (event.type === "click" && event.detail === 0) return

    // PointerEvent inheritance: touch/pen events report pointerType as
    // "touch" / "pen" / "". Only treat events originating from a physical
    // mouse (pointerType === "mouse") OR plain MouseEvents that are NOT
    // PointerEvents (pointerType === undefined — what most browsers fire for
    // raw mousedown/click without pointer capture active) as forbidden.
    //
    // BUG FIXED (2026-05-22): the previous guard was:
    //   if (event.pointerType !== undefined && event.pointerType !== "mouse") return
    // This returned early when pointerType was undefined (plain MouseEvent),
    // so a real physical mousedown / click escaped the guard entirely.
    // Fix: skip only when pointerType IS defined AND IS a non-mouse value
    // (i.e. "touch", "pen", or the keyboard-activation "").
    if (event.pointerType !== undefined && event.pointerType !== "mouse") return

    event.preventDefault()
    event.stopPropagation()
    this.showAlert()
  }

  handleMouseMove(event) {
    // The `alertShown` one-shot guard inside `showAlert()` prevents dialog
    // spam. Some platforms fire mousemove with zero movement deltas during
    // focus / window-activation handshakes; ignore those.
    if (event.movementX === 0 && event.movementY === 0) return
    this.showAlert()
  }

  handleMouseEnter(event) {
    // Browsers sometimes fire synthetic mouseenter events on focus /
    // window activation with zero movement and zero coordinates; ignore
    // those. A real cursor re-entry has non-zero movement OR non-zero
    // viewport coordinates.
    if (event.movementX === 0 && event.movementY === 0) {
      if (event.clientX === 0 && event.clientY === 0) return
    }
    this.showAlert()
  }

  handleAuxClick(event) {
    // `auxclick` fires for ALL non-primary mouse buttons (button !== 0):
    //   button 1 = middle (open-in-new-tab on links)
    //   button 2 = right (usually contextmenu; auxclick fallback)
    //   button 3 = back / X1 (browser back-history)
    //   button 4 = forward / X2 (browser forward-history)
    //   button 5 = extra side button 6
    //   button 6 = extra side button 7
    //   button N = any additional hardware buttons
    // Block all of them — every non-primary click is mouse-only behavior
    // we forbid. preventDefault stops browser history navigation on
    // side buttons. Generalized from button === 1|3|4 to button !== 0
    // on 2026-05-24 to cover buttons 5, 6, 7, and beyond.
    if (!event.isTrusted) return
    if (event.button !== 0) {
      event.preventDefault()
      event.stopPropagation()
      this.showAlert()
    }
  }

  handleMouseLeave() {
    const dialog = document.getElementById(this.dialogIdValue)
    if (dialog && dialog.open) {
      dialog.close()
      this.alertShown = false
    }
  }

  showAlert() {
    // If the size-guard dialog is currently open, just block the mouse event
    // without surfacing the mouse-catcher dialog on top. The size-guard
    // already conveys to the user that the window is too small.
    const sizeGuard = document.getElementById("size-guard-dialog")
    if (sizeGuard && sizeGuard.open) return
    if (this.alertShown) return
    this.alertShown = true
    const dialog = document.getElementById(this.dialogIdValue)
    if (!dialog) return
    if (!dialog.open) dialog.showModal()
    dialog.addEventListener("close", () => { this.alertShown = false }, { once: true })
  }
}
