import { Controller } from "@hotwired/stimulus"

// tui-totp-code — unified segmented code input controller.
//
// Replaces two separate controllers:
//   - totp_code_input_controller.js   (6 numeric digits)
//   - backup_code_input_controller.js (8 alphanumeric chars)
//
// Mounted on the wrapper element rendered by `Tui::TotpCodeComponent`.
// The `mode` value ("digits" | "backup") selects the sanitise path and
// the auto-submit behaviour:
//
//   mode=digits  — strips non-digits, auto-submits when all 6 cells filled.
//   mode=backup  — strips non-alphanumeric and lowercases, never auto-submits.
//
// Both modes share identical UX:
//   - Multi-char paste / extension autofill distributed from the pasted-into cell.
//   - Auto-advance on single-char entry; Backspace on empty steps back.
//   - ArrowLeft / ArrowRight move focus laterally.
//   - Hidden aggregation field synced on every change.
//   - Capture-phase form submit listener guarantees hidden-field sync even when
//     an autofill path bypasses `input` / `change` / `blur`.
//
// Values:
//   mode  [String] — "digits" | "backup". Defaults to "digits".
//   field [String] — param name on the hidden aggregation input.
//
// Targets (mode-dependent):
//   digit  — individual cell inputs (mode=digits)
//   char   — individual cell inputs (mode=backup)
//   hidden — the hidden aggregation input
//
// @contract see app/components/tui/totp_code_component.{rb,html.erb}
export default class extends Controller {
  static targets = ["digit", "char", "hidden"]
  static values  = { mode: { type: String, default: "digits" }, field: String }

  connect() {
    this._submitted = false
    this._syncHidden()

    this._form = this.element.closest("form")
    if (this._form) {
      this._onFormSubmit = () => this._syncHidden()
      this._form.addEventListener("submit", this._onFormSubmit, true)
    }
  }

  disconnect() {
    if (this._form && this._onFormSubmit) {
      this._form.removeEventListener("submit", this._onFormSubmit, true)
    }
    this._form = null
    this._onFormSubmit = null
  }

  // Per-box `input` handler. Sanitises, distributes multi-char payloads,
  // advances focus, syncs hidden, and maybe auto-submits.
  onInput(event) {
    const box = event.target
    const cells = this._cells()
    const idx = cells.indexOf(box)
    if (idx < 0) {
      this._syncHidden()
      return
    }

    const cleaned = this._sanitize(box.value)

    if (cleaned.length <= 1) {
      box.value = cleaned
      if (cleaned && idx < cells.length - 1) {
        cells[idx + 1].focus()
        cells[idx + 1].select()
      }
      this._syncHidden()
      this._maybeAutoSubmit()
      return
    }

    // Multi-char payload (extension autofill writes full code into one box).
    this._distributeFrom(idx, cleaned)
    this._syncHidden()
    this._maybeAutoSubmit()
  }

  // Per-box `keydown` handler. Backspace steps back; Arrows move laterally.
  onKeydown(event) {
    const box = event.target
    const cells = this._cells()
    const idx = cells.indexOf(box)

    if (event.key === "Backspace" && !box.value && idx > 0) {
      event.preventDefault()
      const prev = cells[idx - 1]
      prev.value = ""
      prev.focus()
      this._syncHidden()
      return
    }

    if (event.key === "ArrowLeft" && idx > 0) {
      event.preventDefault()
      cells[idx - 1].focus()
      cells[idx - 1].select()
      return
    }

    if (event.key === "ArrowRight" && idx < cells.length - 1) {
      event.preventDefault()
      cells[idx + 1].focus()
      cells[idx + 1].select()
      return
    }
  }

  // Per-box `paste` handler. Distributes clipboard text starting at the
  // pasted-into cell.
  onPaste(event) {
    event.preventDefault()
    const raw = (event.clipboardData || window.clipboardData)?.getData("text") || ""
    const cleaned = this._sanitize(raw)
    const cells = this._cells()
    const idx = cells.indexOf(event.target)
    const startAt = idx >= 0 ? idx : 0
    this._distributeFrom(startAt, cleaned)
    this._syncHidden()
    this._maybeAutoSubmit()
  }

  // Per-box `blur` handler — defensive sync for autofill paths that wrote the
  // cell value without firing `input` / `change`.
  onCellBlur() {
    this._syncHidden()
    this._maybeAutoSubmit()
  }

  // Private — return the cell targets for the current mode.
  _cells() {
    return this.modeValue === "backup" ? this.charTargets : this.digitTargets
  }

  // Private — sanitise a raw string per mode.
  _sanitize(str) {
    if (this.modeValue === "backup") {
      return (str || "").replace(/[^a-z0-9]/gi, "").toLowerCase()
    }
    return (str || "").replace(/\D/g, "")
  }

  // Private — fill cells from startIdx with chars, then advance focus.
  _distributeFrom(startIdx, chars) {
    if (!chars) return
    const cells = this._cells()
    const limit = Math.min(chars.length, cells.length - startIdx)
    for (let i = 0; i < limit; i++) {
      cells[startIdx + i].value = chars[i]
    }
    const lastFilled = startIdx + limit - 1
    const next = Math.min(lastFilled + 1, cells.length - 1)
    cells[next]?.focus()
    if (lastFilled + 1 < cells.length) {
      cells[next]?.select()
    }
  }

  // Private — concatenate all cell values into the hidden aggregation field.
  _syncHidden() {
    if (!this.hasHiddenTarget) return
    this.hiddenTarget.value = this._cells()
      .map((box) => box.value || "")
      .join("")
  }

  // Private — auto-submit once all cells are filled (digits mode only).
  _maybeAutoSubmit() {
    if (this.modeValue !== "digits") return
    if (this._submitted) return

    const cells = this._cells()
    const code = cells.map((box) => box.value || "").join("")
    if (code.length !== cells.length) return
    if (!/^\d+$/.test(code)) return

    const form = this.element.closest("form")
    if (!form) return

    this._submitted = true
    if (typeof form.requestSubmit === "function") {
      form.requestSubmit()
    } else {
      form.submit()
    }
  }
}
