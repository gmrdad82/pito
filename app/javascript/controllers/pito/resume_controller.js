// pito--resume
//
// Mounted on #pito-sidebar. When /resume populates the sidebar via a Turbo Stream
// update, this controller activates keyboard and mouse navigation for the
// conversation list.
//
// Keyboard:
//   ↑ / ↓   — move highlight through rows
//   Enter   — select highlighted row
//   Escape  — clear (empty) the sidebar
//   d       — arm the highlighted row for deletion (shows confirm prompt)
//             a second d while armed deletes the conversation via DELETE /chat/<uuid>
//             moving the highlight or pressing Escape disarms
//
// Mouse:
//   click .pito-conversation-row — select that row
//
// Selecting a row:
//   - If the row has class "is-current" (already the active conversation) → just clear.
//   - Otherwise → Turbo.visit("/chat/<uuid>").
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

const HIGHLIGHT_CLASS = "pito-resume-highlight"
// Per-browser UI state: which sidebar panel (if any) is open, so a reload
// restores it. Ephemeral view state → localStorage, not the server.
const SIDEBAR_KEY = "pito:sidebar"

export default class extends Controller {
  #dismissHandler = null

  connect() {
    this.abort = new AbortController()
    document.addEventListener("keydown", this.#onKey.bind(this), { signal: this.abort.signal })
    // Sequential Esc: capture-phase so it runs BEFORE the chatbox's suggestions
    // Esc. When the sidebar is open it closes the sidebar and swallows the event
    // (so a /command palette underneath survives); the next Esc reaches the
    // palette. Also makes Esc close the notifications panel (which has no
    // conversation rows and so isn't handled by #onKey).
    document.addEventListener("keydown", this.#onEscapeCapture.bind(this), { capture: true, signal: this.abort.signal })
    this.element.addEventListener("click", this.#onClick.bind(this), { signal: this.abort.signal })
    this.highlightIndex = -1
    this.armedRow = null

    // Allow other controllers (home-transition, command-palette) to dismiss the
    // sidebar without holding a reference to this controller.
    this.#dismissHandler = () => this.dismiss()
    window.addEventListener("pito:resume:dismiss", this.#dismissHandler)

    // The sidebar content is injected via a Turbo Stream UPDATE (this controller
    // stays connected). Watch for it: when rows appear we (a) hide the command
    // dots — /resume is a sync command and never fires pito:done otherwise — and
    // (b) highlight the first row so arrow-nav is immediately visible.
    // subtree:true so a row REPLACE (e.g. after rename) re-pins the highlight to
    // the same position instead of losing it.
    this.observer = new MutationObserver(() => this.#onContentChange())
    this.observer.observe(this.element, { childList: true, subtree: true })

    // Restore a previously-open panel after reload.
    this.#restore()
  }

  disconnect() {
    this.abort?.abort()
    this.observer?.disconnect()
    window.removeEventListener("pito:resume:dismiss", this.#dismissHandler)
  }

  // Public: allows other controllers to dismiss the sidebar without a direct
  // reference. Called by the pito:resume:dismiss window event and can also be
  // invoked programmatically (e.g. from tests or sibling controllers).
  dismiss() {
    this.#clear()
  }

  // Re-open the panel that was open before reload. Skips if the sidebar is
  // already populated (e.g. a Turbo navigation kept it).
  #restore() {
    if (this.element.innerHTML.trim()) return
    const want = localStorage.getItem(SIDEBAR_KEY)
    if (!want) return

    let url
    if (want === "notifications") {
      url = "/notifications"
    } else if (want === "conversations") {
      const m = location.pathname.match(/\/chat\/([0-9a-f-]+)/i)
      url = "/resume" + (m ? `?uuid=${m[1]}` : "")
    } else {
      return
    }

    fetch(url, { headers: { Accept: "text/vnd.turbo-stream.html" } })
      .then((r) => (r.ok ? r.text() : null))
      .then((html) => { if (html) Turbo.renderStreamMessage(html) })
      .catch(() => {})
  }

  #onContentChange() {
    const rows = this.#rows()

    // Persist which panel is open so a reload can restore it.
    if (rows.length) {
      localStorage.setItem(SIDEBAR_KEY, "conversations")
    } else if (this.element.querySelector(".pito-notification-row")) {
      localStorage.setItem(SIDEBAR_KEY, "notifications")
    }

    if (!rows.length) {
      this.highlightIndex = -1
      return
    }

    if (this.highlightIndex === -1) {
      // Sidebar just opened — stop the command dots and highlight the first row.
      document.dispatchEvent(new CustomEvent("pito:done", { bubbles: true }))
      this.highlightIndex = 0
    } else {
      // Content changed (e.g. a row was renamed → Turbo-replaced) — keep the
      // highlight pinned to the same position so it stays selected.
      this.highlightIndex = Math.min(this.highlightIndex, rows.length - 1)
    }
    rows.forEach((r, i) => r.classList.toggle(HIGHLIGHT_CLASS, i === this.highlightIndex))
  }

  // Called by Turbo after the sidebar content is updated so we can initialise
  // the highlight. Turbo fires turbo:render which we listen to globally, but
  // it is simpler to rely on the MutationObserver-based connect/disconnect
  // lifecycle. When the element's children change (Turbo Stream update) the
  // controller is not re-connected, so we re-initialise on every keydown.

  // ── Private ────────────────────────────────────────────────────────────────

  #rows() {
    return Array.from(this.element.querySelectorAll(".pito-conversation-row"))
  }

  #onEscapeCapture(e) {
    if (e.key !== "Escape") return
    // When a row is armed, let the bubbling #onKey handler disarm it instead —
    // we don't swallow the event here so #onKey can decide.
    if (this.armedRow) return
    if (!this.element.innerHTML.trim()) return // nothing open — let it pass through
    e.preventDefault()
    e.stopImmediatePropagation()
    this.#clear()
  }

  #onKey(e) {
    const rows = this.#rows()
    if (!rows.length) return

    if (e.key === "ArrowDown") {
      e.preventDefault()
      this.#disarm()
      this.#move(rows, 1)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this.#disarm()
      this.#move(rows, -1)
    } else if (e.key === "Enter") {
      e.preventDefault()
      const highlighted = rows[this.highlightIndex]
      if (highlighted) this.#select(highlighted)
    } else if (e.key === "Escape") {
      e.preventDefault()
      if (this.armedRow) {
        this.#disarm()
      } else {
        this.#clear()
      }
    } else if (e.key === "d") {
      const highlighted = rows[this.highlightIndex]
      if (!highlighted) return
      e.preventDefault()
      if (this.armedRow === highlighted) {
        // Second d — confirm delete
        this.#deleteConversation(highlighted)
      } else {
        // First d — arm the row
        this.#disarm()
        this.#arm(highlighted)
      }
    } else if (e.key === "`") {
      // Inline-rename the highlighted conversation. The pito--rename controller
      // on that row listens for this event and swaps the name for an <input>.
      const highlighted = rows[this.highlightIndex]
      if (highlighted) {
        e.preventDefault()
        highlighted.dispatchEvent(new CustomEvent("pito:rename:start"))
      }
    }
  }

  #onClick(e) {
    const row = e.target.closest(".pito-conversation-row")
    if (!row) return
    this.#select(row)
  }

  #move(rows, delta) {
    // Initialise to first/last on first keypress
    if (this.highlightIndex === -1) {
      this.highlightIndex = delta > 0 ? 0 : rows.length - 1
    } else {
      this.highlightIndex = Math.max(0, Math.min(rows.length - 1, this.highlightIndex + delta))
    }
    rows.forEach((r, i) => r.classList.toggle(HIGHLIGHT_CLASS, i === this.highlightIndex))
    rows[this.highlightIndex]?.scrollIntoView({ block: "nearest" })
  }

  #select(row) {
    const uuid = row.dataset.conversationUuid
    if (!uuid) { this.#clear(); return }

    if (row.classList.contains("is-current")) {
      // Already on this conversation — just close the sidebar.
      this.#clear()
      return
    }

    this.#clear()
    Turbo.visit("/chat/" + uuid)
  }

  #clear() {
    this.#disarm()
    this.element.innerHTML = ""
    this.highlightIndex = -1
    // Forget the persisted panel so a reload doesn't re-open a dismissed sidebar.
    localStorage.removeItem(SIDEBAR_KEY)
  }

  // Arms a row for deletion: saves its original inner HTML and replaces the
  // visible content with a confirm prompt. Only one row is armed at a time.
  #arm(row) {
    this.armedRow = row
    row._resumeSavedHtml = row.innerHTML
    // Witty confirm copy injected server-side (Pito::Copy); orange = confirmation,
    // 16px (no size class — the app is 16px-only), italic.
    const prompt = this.element.querySelector("[data-delete-prompt]")?.dataset.deletePrompt
                   || "press d again to delete"
    row.innerHTML = `<span class="text-orange italic px-1">${prompt}</span>`
  }

  // Disarms any currently armed row, restoring its original HTML.
  #disarm() {
    if (!this.armedRow) return
    if (this.armedRow._resumeSavedHtml !== undefined) {
      this.armedRow.innerHTML = this.armedRow._resumeSavedHtml
      delete this.armedRow._resumeSavedHtml
    }
    this.armedRow = null
  }

  // Sends DELETE /chat/<uuid>, then removes the row from the list or redirects
  // to "/" if the deleted conversation is the currently-open one.
  #deleteConversation(row) {
    const uuid = row.dataset.conversationUuid
    if (!uuid) return

    const csrfToken = document.querySelector("meta[name=csrf-token]")?.content
    const headers = { "X-CSRF-Token": csrfToken || "" }

    // Determine the current conversation uuid from the hidden input on the chat page.
    const currentUuidInput = document.querySelector("input[name=uuid]")
    const currentUuid = currentUuidInput?.value

    fetch(`/chat/${uuid}`, { method: "DELETE", headers })
      .then((r) => {
        if (!r.ok) return
        if (currentUuid && uuid === currentUuid) {
          window.location.href = "/"
        } else {
          row.remove()
        }
      })
      .catch(() => {})

    // Clear armed state immediately (row will be removed or page will navigate).
    this.armedRow = null
  }
}
