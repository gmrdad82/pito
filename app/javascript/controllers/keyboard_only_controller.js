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
export default class extends Controller {
  static values = { dialogId: { type: String, default: "mouse-forbidden-alert" } }

  connect() {
    this.alertShown = false
    document.body.classList.add("keyboard-only")

    this.boundMouseInteraction = this.handleMouseInteraction.bind(this)
    this.boundMouseMove = this.handleMouseMove.bind(this)
    this.boundMouseLeave = this.handleMouseLeave.bind(this)
    this.boundMouseEnter = this.handleMouseEnter.bind(this)

    // Capture phase so we run before any per-element listener (Stimulus,
    // native form submit, anchor navigation, dialog backdrop click guard).
    document.addEventListener("mousedown", this.boundMouseInteraction, true)
    document.addEventListener("click", this.boundMouseInteraction, true)
    document.addEventListener("contextmenu", this.boundMouseInteraction, true)
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
    document.removeEventListener("mousemove", this.boundMouseMove)
    document.removeEventListener("mouseleave", this.boundMouseLeave)
    document.removeEventListener("mouseenter", this.boundMouseEnter)
    document.body.classList.remove("keyboard-only")
  }

  handleMouseInteraction(event) {
    // Allow programmatic clicks dispatched from JS (e.g. Stimulus `.click()`
    // calls on a header for select-all, focus-restore flows). Synthetic
    // events from `Element.click()` / `dispatchEvent` have `isTrusted: false`.
    if (!event.isTrusted) return

    // Allow keyboard-fired clicks (Enter/Space activating a focused button
    // or anchor). The UA fires a synthetic `click` whose `detail` (click
    // count) is 0; real mouse clicks have `detail >= 1`.
    if (event.type === "click" && event.detail === 0) return

    // PointerEvent inheritance: a click from a keyboard activation reports
    // `pointerType === ""` (or "keyboard" on some engines). Only treat
    // events explicitly originating from a mouse as forbidden interaction.
    if (event.pointerType !== undefined && event.pointerType !== "mouse") return

    event.preventDefault()
    event.stopPropagation()
    this.showAlert()
  }

  handleMouseMove(event) {
    // Throttle removed — the `alertShown` one-shot guard inside
    // `showAlert()` already prevents dialog spam. Some platforms fire
    // mousemove with zero movement deltas during focus / window-activation
    // handshakes; ignore those.
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

  handleMouseLeave() {
    const dialog = document.getElementById(this.dialogIdValue)
    if (dialog && dialog.open) {
      dialog.close()
      this.alertShown = false
    }
  }

  showAlert() {
    if (this.alertShown) return
    this.alertShown = true
    const dialog = document.getElementById(this.dialogIdValue)
    if (!dialog) return
    if (!dialog.open) dialog.showModal()
    dialog.addEventListener("close", () => { this.alertShown = false }, { once: true })
  }
}
