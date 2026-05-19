import { Controller } from "@hotwired/stimulus"

// Module-level live read of the mandatory-2FA enrollment gate.
// Reads `<meta name="pito-enroll-totp-gate">` from `<head>` on every
// invocation — the meta tag is re-merged by Turbo on every navigation
// (`mergeProvisionalElements` diffs head children by `isEqualNode`),
// so a live read is guaranteed-fresh per page. When the meta is
// absent (defensive — the layout renders it unconditionally) the gate
// is treated as inactive so missing markup never silently bricks
// global keybindings. See the layout's head comment for the full
// reason this lives in head rather than body.
function enrollTotpGateActive() {
  const meta = document.querySelector('meta[name="pito-enroll-totp-gate"]')
  return meta?.getAttribute("content") === "yes"
}

// Global keyboard shortcuts — YAML-driven only.
//
// User rule (locked 2026-05-17): ALL action keybindings are
// LEADER-PREFIXED. The user must press SPACE (the leader key) to open
// the popup before any action key (`/`, `s`, `-`, `d`, …) fires. There
// is NO direct keypress dispatch from this controller; every action key
// resolves through the leader-menu popup (`leader_menu_controller.js`),
// which reads `config/keybindings.yml` (`page_actions:` + `menus:`) and
// dispatches via Stimulus into the action handlers exposed below.
//
// What this controller still owns:
//   Esc   cancel on action-confirmation pages (form-bound `[cancel]` link)
//
// What it EXPOSES (called from `leader_menu_controller.fireAction` via
// the Stimulus app — NOT bound to direct keypresses):
//   page_sync(event)        — POSTs to `<body data-page-sync-url>`
//   page_delete(event)      — opens `<dialog id=...>` per
//                             `<body data-page-delete-modal-id>`
//   openGlobalSearch()      — opens the layout `global-search-modal`
//
// What was removed 2026-05-19 (single-theme cleanup):
//   theme_toggle(event)     — the localStorage-driven dark/light toggle
//                             was retired along with `theme_controller.js`.
//                             CSS now ships a single (dark) palette.
//
// What was removed 2026-05-17 (legacy sweep — not in YAML):
//   `i`           → IGDB add modal. Replaced by the `[+]` bracketed link
//                   in /games chrome that opens the same modal.
//   `g d/c/v/s/e` → nav prefixes. Replaced by leader-menu (SPACE → c/h/etc).
//   `f s`         → starred filter. Replaced by the bracketed filter chip.
//   `j` `k`       → row / tile highlight up/down.
//   `h` `l`       → tile-grid horizontal, detail-page prev/next,
//                   paginator prev/next.
//   ` `           → toggle highlighted row's checkbox.
//   `v`           → open external url on the highlighted row.
//   `D` `Y`       → bulk delete / sync from selection or highlight.
//   `y`           → submit action-confirmation form (the [confirm] button
//                   click is the canonical surface; Enter on a focused
//                   submit button also works natively).
//   All associated machinery: row/grid highlight state, prefix state
//   machine + 1s timer, calendar-month/tile-grid navigation, paginator
//   sibling navigation, list-row bulk-id resolution, action-screen
//   confirm helper.
//
// What became LEADER-PREFIXED 2026-05-17 (direct case branches removed
// from this controller; the methods stay and are invoked from
// `leader_menu_controller.fireAction`):
//   `/`   open global search modal — was `case "/"` here, now resolves
//         through the leader popup (page_actions: `open_modal` with
//         modal_id `search_placeholder`).
//   `s`   page_sync — was `case "s"` here.
//   `-`   page_delete — was `case "-"` here.
//   (2026-05-19 — the leader-prefixed `theme_toggle` action key was
//   deleted with the rest of the theme machinery.)
//
// Bindings are gated when focus sits inside `<input>`, `<textarea>`,
// `<select>`, or `[contenteditable]`.
export default class extends Controller {
  connect() {
    this.boundKeydown = this.onKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    if (this.boundKeydown) {
      document.removeEventListener("keydown", this.boundKeydown)
    }
  }

  onKeydown(event) {
    // Mandatory-2FA enrollment gate. When the authenticated user has
    // not configured TOTP, every global shortcut is inert until they
    // complete enrollment. The enrollment form's own keys (typing the
    // 6-digit code, Tab between fields, Enter to submit) fire on a
    // focused `<input>` via native browser behaviour, so they never
    // reach this document-level listener. See the layout comment next
    // to the `<meta name="pito-enroll-totp-gate">` tag for the full
    // <meta>-in-head vs body-mounted-signal rationale.
    if (enrollTotpGateActive()) return

    // Hard guard: never intercept while typing.
    if (this.isEditableTarget(event.target)) return

    // Browser-native shortcuts always pass through.
    if (event.metaKey || event.ctrlKey || event.altKey) return

    // Esc on action-confirmation pages clicks `[cancel]` (standard
    // editor expectation — Escape closes / cancels the current modal-
    // like surface).
    if (event.key === "Escape") {
      if (this.handleActionScreenCancel()) {
        event.preventDefault()
      }
      return
    }

    // No direct action dispatch. All `page_actions` (page_sync,
    // page_delete, open_modal/search) and `menus` items resolve through
    // the leader popup — see `leader_menu_controller.fireAction`, which
    // reaches back into the handlers defined below via the Stimulus app.
    // Esc-on-confirmation (above) is the only direct keypress this
    // controller still owns.
  }

  // ---------- page_actions handlers (YAML-driven) ----------

  // `page_sync` — POSTs to `data-page-sync-url` (e.g.
  // `/games/:id/resync`). On success the page's existing ActionCable
  // subscription handles the live update; we don't wait on the
  // response body. Returns true when a sync was fired so the caller
  // can short-circuit, false when no page-sync was wired.
  page_sync(event) {
    const url = document.body?.dataset?.pageSyncUrl
    if (!url) return false
    event.preventDefault()
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(url, {
      method: "POST",
      headers: {
        "X-CSRF-Token": token || "",
        Accept: "text/vnd.turbo-stream.html",
      },
    }).catch((err) => console.error("page_sync failed:", err))
    return true
  }

  // `page_delete` — opens the per-page confirm `<dialog>` by id (per
  // the per-game / per-bundle delete modal). Returns true when a
  // dialog was opened so the caller can short-circuit, false when no
  // page-delete was wired or the dialog is missing.
  page_delete(event) {
    const modalId = document.body?.dataset?.pageDeleteModalId
    if (!modalId) return false
    event.preventDefault()
    const dialog = document.getElementById(modalId)
    if (dialog && typeof dialog.showModal === "function") {
      dialog.showModal()
      return true
    }
    return false
  }

  // ---------- helpers ----------

  isEditableTarget(target) {
    if (!target || !target.matches) return false
    return target.matches("input, textarea, select, [contenteditable], [contenteditable='true']")
  }

  // `/` opens the global search modal (`shared/_search_modal`). Returns
  // false when the dialog isn't on the page so the keystroke falls
  // through (e.g. into an open page-local search input) instead of
  // being swallowed.
  openGlobalSearch() {
    return this.openLayoutDialog("global-search-modal", "global-search-modal")
  }

  // Resolves the layout-level <dialog> by id, looks up its controller
  // via `window.Stimulus`, and calls `open()`. Falls back to a direct
  // `showModal()` if the controller isn't wired. Returns true when a
  // dialog was opened, false otherwise.
  openLayoutDialog(elementId, controllerIdentifier) {
    const dialog = document.getElementById(elementId)
    if (!dialog) return false
    const app = window.Stimulus
    if (app && typeof app.getControllerForElementAndIdentifier === "function") {
      const ctrl = app.getControllerForElementAndIdentifier(dialog, controllerIdentifier)
      if (ctrl && typeof ctrl.open === "function") {
        ctrl.open()
        return true
      }
    }
    if (typeof dialog.showModal === "function") {
      dialog.showModal()
      return true
    }
    return false
  }

  // ---------- action confirmation page (Esc → cancel) ----------

  handleActionScreenCancel() {
    const cancel = document.querySelector("[data-keyboard-confirmation-cancel]")
    if (!cancel) return false
    if (cancel instanceof HTMLAnchorElement) {
      window.location.assign(cancel.href)
    } else {
      cancel.click()
    }
    return true
  }
}
