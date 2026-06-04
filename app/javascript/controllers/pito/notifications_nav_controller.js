// pito--notifications-nav
//
// Mounted on the notifications list injected into #pito-sidebar by ctrl+/.
// Keyboard:
//   ↑ / ↓   — move the highlight through notification rows
//   Space   — toggle read/unread on the highlighted row (optimistic DOM update
//             + PATCH /notifications/:id { read: <bool> })
//   Escape  — handled by pito--resume (clears the sidebar)
// Mouse:
//   click a row — highlight it
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"

const HIGHLIGHT = "pito-resume-highlight"

export default class extends Controller {
  connect() {
    this.abort = new AbortController()
    document.addEventListener("keydown", this.#onKey.bind(this), { signal: this.abort.signal })
    this.element.addEventListener("click", this.#onClick.bind(this), { signal: this.abort.signal })
    this.index = -1
    const rows = this.#rows()
    if (rows.length) {
      this.index = 0
      this.#paint(rows)
    }
  }

  disconnect() {
    this.abort?.abort()
  }

  // ── Private ────────────────────────────────────────────────────────────────

  #rows() {
    return Array.from(this.element.querySelectorAll(".pito-notification-row"))
  }

  #onKey(e) {
    const rows = this.#rows()
    if (!rows.length) return

    if (e.key === "ArrowDown") {
      e.preventDefault()
      this.#move(rows, 1)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this.#move(rows, -1)
    } else if (e.key === " " || e.key === "Spacebar") {
      e.preventDefault()
      this.#toggle(rows[this.index])
    }
  }

  #onClick(e) {
    const row = e.target.closest(".pito-notification-row")
    if (!row) return
    this.index = this.#rows().indexOf(row)
    this.#paint(this.#rows())
  }

  #move(rows, delta) {
    if (this.index === -1) {
      this.index = delta > 0 ? 0 : rows.length - 1
    } else {
      this.index = Math.max(0, Math.min(rows.length - 1, this.index + delta))
    }
    this.#paint(rows)
    rows[this.index]?.scrollIntoView({ block: "nearest" })
  }

  #paint(rows) {
    rows.forEach((r, i) => r.classList.toggle(HIGHLIGHT, i === this.index))
  }

  #toggle(row) {
    if (!row) return
    const id = row.dataset.notificationId
    const nowRead = row.dataset.read !== "true" // flip current state
    row.dataset.read = String(nowRead)

    const dot = row.querySelector(".pito-notification-dot")
    if (dot) {
      dot.textContent = nowRead ? "○" : "●"
      dot.classList.toggle("text-cyan", !nowRead)
      dot.classList.toggle("text-fg-faded", nowRead)
    }

    const msg = row.querySelector(".pito-notification-message")
    if (msg) {
      msg.classList.toggle("text-fg", !nowRead)
      msg.classList.toggle("font-bold", !nowRead)
      msg.classList.toggle("text-fg-dim", nowRead)
    }

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(`/notifications/${id}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        ...(csrf ? { "X-CSRF-Token": csrf } : {}),
      },
      body: JSON.stringify({ read: nowRead }),
    }).catch((err) => console.warn("[pito--notifications-nav] toggle failed:", err))
  }
}
