// pito--expand
//
// Collapsible content for error details and /help overflow.
//
// Ctrl+| (global, fires once) → toggles ALL rendered expandable segments at
// once: flips the server-side AppSetting, persists via POST /settings/expand_all,
// and immediately syncs every segment to the new state.
//
// connect() → if expand-all is currently ON, render this segment expanded so
// new cable-delivered segments respect the global flag on arrival.
//
// Required targets:
//   detail     — the hidden/shown content block
//   hint       — the "ctrl+| …" wrapper line (hidden while expanded)
//   hintLabel  — the text span whose content switches between expand/collapse labels
//
// Values (set by server template):
//   expandLabelValue   — e.g. "to expand"
//   collapseLabelValue — e.g. "to collapse"

import { Controller } from "@hotwired/stimulus"
import { isAuthenticated } from "pito/auth"
import { expandAllEnabled } from "pito/settings"

// One global ctrl+| handler shared across ALL instances.
// Registered on the first connect(), removed after the last disconnect().
let _activeCount   = 0
let _globalAbort   = null

function registerGlobalHandler() {
  if (_globalAbort) return
  _globalAbort = new AbortController()
  document.addEventListener("keydown", _onGlobalKeydown, { signal: _globalAbort.signal })
}

function unregisterGlobalHandler() {
  _globalAbort?.abort()
  _globalAbort = null
}

function _onGlobalKeydown(e) {
  if (!e.ctrlKey || e.key !== "|") return
  if (!isAuthenticated()) return
  e.preventDefault()
  toggleAll()
}

// Toggle ALL segments + persist to server.
function toggleAll() {
  const newState = !expandAllEnabled()
  // Update the #pito-settings data attribute immediately so expandAllEnabled()
  // returns the new value for any cable segment that connects before the Turbo
  // Stream replace arrives from pito:global.
  const settingsEl = document.getElementById("pito-settings")
  if (settingsEl) settingsEl.dataset.expandAll = String(newState)
  // Flip every rendered segment immediately (optimistic).
  document.querySelectorAll('[data-controller~="pito--expand"]').forEach(el => {
    const instance = el.__pito_expand_instance
    if (instance) instance.setExpanded(newState)
  })
  // Persist + broadcast via server (fire-and-forget, best-effort).
  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
  fetch("/settings/expand_all", {
    method:  "POST",
    headers: {
      "Content-Type": "application/json",
      "Accept":       "application/json",
      ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {}),
    },
    body: JSON.stringify({ expand_all: newState }),
  }).catch(err => {
    console.warn("[pito--expand] POST /settings/expand_all failed:", err)
  })
}

export default class extends Controller {
  static targets = ["hint", "hintAfter", "hintLabel", "detail"]
  static values  = { expandLabel: String, collapseLabel: String }

  connect() {
    if (!this.hasDetailTarget) return
    // Expose instance on the element so the global handler can reach it.
    this.element.__pito_expand_instance = this
    _activeCount++
    registerGlobalHandler()

    // Respect the global flag: if expand-all is ON, open immediately.
    if (expandAllEnabled()) this.setExpanded(true)
  }

  disconnect() {
    delete this.element.__pito_expand_instance
    _activeCount--
    if (_activeCount <= 0) {
      _activeCount = 0
      unregisterGlobalHandler()
    }
  }

  // ── Public API (used by global handler) ───────────────────────────────────

  setExpanded(nowExpanded) {
    this.element.dataset.expanded = String(nowExpanded)
    this.detailTarget.classList.toggle("hidden", !nowExpanded)

    if (this.hasHintTarget)      this.hintTarget.classList.toggle("hidden", nowExpanded)
    if (this.hasHintAfterTarget) this.hintAfterTarget.classList.toggle("hidden", !nowExpanded)

    if (this.hasHintLabelTarget) {
      this.hintLabelTarget.textContent = nowExpanded
        ? (this.collapseLabelValue || "to collapse")
        : (this.expandLabelValue   || "to expand")
    }
  }
}
