/**
 * sessions-scramble — scramble-transition new-row insertion for the sessions
 * table. Mounted on the `<turbo-frame id="sessions_panel">` element.
 *
 * ## Behavior
 *
 * Listens for `pito:panel:security:received` DOM events dispatched by the
 * `tui-panel-cable` controller on the panel root. When a message with
 * `kind: "session_created"` arrives, the new `<tr>` is expected to have
 * already been appended by a Turbo Stream `append` action (server-side
 * broadcast, wired in C9). This controller then runs a 400 ms scramble
 * animation over the new row's cells — each character cycles through random
 * ASCII glyphs before settling on the real value.
 *
 * The scramble resets the sort to creation-descending so the new row is
 * visible at the top. Sort reset is triggered by clicking the "created"
 * column sort link if its current direction is ascending; otherwise it is
 * already in descending order and no click is needed.
 *
 * ## Cable wiring
 *
 * Does NOT create its own ActionCable consumer. The `tui-panel-cable`
 * controller (mounted on the panel root) already holds the subscription and
 * fires `pito:panel:security:received` (bubbles: false) on the panel
 * element. On `connect()` this controller walks up the DOM to find the
 * panel root and attaches the listener there.
 *
 * ## Animation
 *
 * Pure vanilla — no external animation library. Uses `setInterval` with
 * character substitution. Each cell's text is stored, overwritten with
 * random chars, then resolved character-by-character over ~400 ms
 * (10 frames at 40 ms cadence).
 *
 * @data-controller sessions-scramble
 * @mounts-on       turbo-frame#sessions_panel (inside Sessions::TableComponent)
 * @listens         pito:panel:security:received (on panel root, bubbles: false)
 * @related         tui_panel_cable_controller.js, Sessions::TableComponent
 */

import { Controller } from "@hotwired/stimulus"

const SCRAMBLE_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*"
const SCRAMBLE_FRAMES = 10
const FRAME_INTERVAL_MS = 40

function randomChar() {
  return SCRAMBLE_CHARS[Math.floor(Math.random() * SCRAMBLE_CHARS.length)]
}

function scrambleText(element, finalText, onDone) {
  let frame = 0
  const len = finalText.length

  const interval = setInterval(() => {
    frame++
    const resolvedCount = Math.floor((frame / SCRAMBLE_FRAMES) * len)
    let display = finalText.slice(0, resolvedCount)
    for (let i = resolvedCount; i < len; i++) {
      display += randomChar()
    }
    element.textContent = display

    if (frame >= SCRAMBLE_FRAMES) {
      clearInterval(interval)
      element.textContent = finalText
      if (onDone) onDone()
    }
  }, FRAME_INTERVAL_MS)

  return interval
}

export default class extends Controller {
  connect() {
    this._panelRoot = this.element.closest("[data-tui-panel-cable-name-value]")
    if (!this._panelRoot) return

    this._handler = (event) => this._onPanelReceived(event)
    this._panelRoot.addEventListener("pito:panel:security:received", this._handler)
  }

  disconnect() {
    if (this._panelRoot && this._handler) {
      this._panelRoot.removeEventListener("pito:panel:security:received", this._handler)
    }
    this._panelRoot = null
    this._handler = null
  }

  _onPanelReceived(event) {
    const { kind, payload } = event.detail || {}
    if (kind !== "session_created") return

    const newRowId = payload && payload.session_id
      ? `sessions_row_${payload.session_id}`
      : null

    // Reset sort to creation descending so the new row is visible.
    this._resetSortToCreatedDesc()

    // Wait one tick for the Turbo Stream append to settle in the DOM,
    // then scramble the new row if we have a session_id to target.
    if (newRowId) {
      requestAnimationFrame(() => {
        const row = this.element.querySelector(`[data-session-id="${payload.session_id}"]`) ||
                    document.getElementById(newRowId)
        if (row) this._scrambleRow(row)
      })
    }
  }

  _scrambleRow(row) {
    const cells = Array.from(row.querySelectorAll("td"))
    // Skip the checkbox column (first cell — no text to scramble).
    const dataCells = cells.slice(1)
    let pending = dataCells.length

    dataCells.forEach((cell) => {
      const finalText = cell.textContent.trim()
      cell.textContent = Array.from({ length: finalText.length }, randomChar).join("")
      scrambleText(cell, finalText, () => {
        pending--
      })
    })
  }

  _resetSortToCreatedDesc() {
    // Find the "created" sort link inside the turbo-frame. If its current
    // href contains sessions_dir=asc (ascending), click it to flip to desc.
    // If already desc (or unset — server default is desc), leave it alone.
    const createdLink = this.element.querySelector(
      'a[href*="sessions_sort=created"][href*="sessions_dir=asc"]'
    )
    if (createdLink) createdLink.click()
  }
}
