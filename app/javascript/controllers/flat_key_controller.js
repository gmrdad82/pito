import { Controller } from "@hotwired/stimulus"

// Module-level live read of the mandatory-2FA enrollment gate. Mirror
// of the helper in `leader_menu_controller.js` /
// `keyboard_controller.js`; kept duplicated rather than extracted to a
// shared module so each controller stays self-contained for importmap
// simplicity.
function enrollTotpGateActive() {
  const meta = document.querySelector('meta[name="pito-enroll-totp-gate"]')
  return meta?.getAttribute("content") === "yes"
}

// Flat-key (leader-less) entry-point controller. Reads the `flat:`
// block of the unified keybindings schema embedded in
// `<script id="pito-keybindings">`, listens for keydown at document
// level, and dispatches the matching action verbatim. Three action
// types are supported:
//
//   open_modal { modal_id: <dom-id> }
//     Locates `<dialog id=...>` and opens it. Prefers the modal's
//     own Stimulus controller `.open()` method when available (the
//     omnisearch modal exposes `open()` so state is reset + input
//     focused); falls back to a bare `.showModal()` so any future
//     consumer that mounts a plain dialog still works.
//
//   open_section_modal_or_fallback { fallback_modal_id: <dom-id> }
//     Resolves the section→modal-id map at runtime against
//     `document.body.dataset.section` (set by
//     ApplicationHelper#current_section). If the current section has
//     a section-specific Omnisearch modal AND it's mounted on the
//     page, open it; otherwise open `fallback_modal_id`. The map is
//     intentionally hardcoded in JS (not config-driven) because
//     sections gain / lose section-specific modals over time as
//     features land. Today only `games` maps to a section modal;
//     `channels`, `settings`, and `home` fall through to the
//     fallback.
//
//   open_leader_with_prefix { prefix: <string> }
//     Dispatches a `flat-key:open-leader-with-prefix` CustomEvent on
//     `document` carrying `{ prefix }`. The leader controller listens
//     for this event, opens its popup (same code path SPACE triggers),
//     flips `data-compact="true"` on the popup dialog so CSS hides
//     the local section, and seeds the prefix accumulator.
//
// The keydown gate mirrors the leader controller's gate — every
// keystroke is ignored when:
//   * the 2FA enrollment meta tag is "yes" (mandatory-2FA gate)
//   * focus sits on a form-entry surface (input, textarea, select,
//     button, [contenteditable]) so native typing still works
//   * any modifier key is held (Ctrl/Meta/Alt) — Shift is allowed
//     because uppercase letters need it
//   * any keyed `<dialog open>` is on the page (modal-context — the
//     leader popup's modal_actions take over)
//   * the leader popup itself is open (SPACE has already engaged the
//     leader flow; the leader controller owns key dispatch from then
//     on)
//   * a list-row context is active (keyboard_controller's
//     `[data-keyboard-row].keyboard-highlight` row) so SPACE / arrow
//     navigation stays bound to the row selection surface
export default class extends Controller {
  connect() {
    // Listener is registered unconditionally — the schema is read
    // LAZILY on each keystroke via `this.bindings` (see getter below).
    // This mirrors `leader_menu_controller#connect()` which also binds
    // unconditionally so a body-swap during Turbo Drive navigation
    // can never leave the surface dead. Historically the listener was
    // only attached when the schema-lookup succeeded at connect time;
    // if Turbo Drive's body-swap ordering caused the new
    // `<script id="pito-keybindings">` tag to be missing or stale at
    // the precise moment Stimulus reconnected the controller to the
    // new `<body>`, the controller silently bailed with no listener —
    // and `g` / `q` / `?` stopped responding until a full refresh.
    // The fresh-on-keystroke read also covers the rare case where the
    // schema content changes across pages in the future (it does not
    // today — the helper emits the same JSON on every page — but the
    // defensive read costs O(items) per keystroke, trivial).
    this.boundKeydown = this.onKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    if (this.boundKeydown) document.removeEventListener("keydown", this.boundKeydown)
  }

  // Fresh-read the schema + flat items map on every access. The
  // `<script id="pito-keybindings">` tag lives in the body (not
  // `data-turbo-permanent`) so it is re-emitted on every Turbo Drive
  // page swap with identical content. Reading per-keystroke removes
  // any window where a cached-at-connect-time bindings map could be
  // stale relative to the live DOM.
  get bindings() {
    const node = document.getElementById("pito-keybindings")
    if (!node) return null
    let schema
    try {
      schema = JSON.parse(node.textContent || "{}")
    } catch (_err) {
      return null
    }
    const flat = schema && schema.flat
    const items = flat && Array.isArray(flat.items) ? flat.items : []
    const map = new Map()
    items.forEach((item) => {
      if (item && typeof item.key === "string" && item.action && item.action.type) {
        map.set(item.key, item)
      }
    })
    return map
  }

  onKeydown(event) {
    const bindings = this.bindings
    if (!bindings || bindings.size === 0) return
    // Mandatory-2FA gate — the layout flips the meta tag to "yes"
    // for users who haven't enrolled TOTP. Flat keys must not bypass
    // the gate (would expose navigation surfaces server-side blocks).
    if (enrollTotpGateActive()) return
    // Form-control pass-through — same skip set as
    // `leader_menu_controller#isEditableTarget`. A focused button
    // + SPACE still submits; a focused checkbox + SPACE still
    // toggles; `/` typed in a text input lands as a literal slash.
    if (this.isEditableTarget(event.target)) return
    // Modifier-key guard. Ctrl/Cmd/Alt combos are app / browser
    // shortcuts; Shift stays allowed (`/` lives on Shift+7 on some
    // layouts; capital letters need Shift).
    if (event.metaKey || event.ctrlKey || event.altKey) return
    // List-row context (keyboard_controller `[data-keyboard-row]`
    // highlight) owns SPACE for selection toggle. Same guard the
    // leader controller uses before opening the root menu.
    if (document.querySelector("[data-keyboard-row].keyboard-highlight")) return
    // Open-dialog guard. When ANY `<dialog open>` is on the page —
    // the leader popup itself, a keyed modal, or any other modal —
    // the flat-key controller defers: the leader popup owns key
    // dispatch from the moment SPACE opens it; keyed modals route
    // through the leader's modal_actions surface; plain modals
    // (omnisearch, confirm dialogs) own their own keys. The flat-
    // key surface only fires on the neutral page chrome.
    if (document.querySelector("dialog[open]")) return

    const item = bindings.get(event.key)
    if (!item) return

    event.preventDefault()
    this.fire(item)
  }

  // Dispatch the matched binding's action. Each branch is the flat
  // surface's equivalent of the leader controller's `fireAction`
  // pipeline — no CustomEvent fallback here because the flat block
  // ships a small fixed set of action types today and any future
  // type lives in the YAML alongside an explicit handler.
  fire(item) {
    const action = item.action
    if (!action || !action.type) return

    if (action.type === "open_modal" && action.modal_id) {
      this.openModal(action.modal_id)
      return
    }
    if (action.type === "open_section_modal_or_fallback" && action.fallback_modal_id) {
      this.openSectionModalOrFallback(action.fallback_modal_id)
      return
    }
    if (action.type === "open_leader_with_prefix" && action.prefix) {
      this.openLeaderWithPrefix(action.prefix)
      return
    }
  }

  // Section → section-specific Omnisearch modal-id map. Resolved at
  // runtime against `document.body.dataset.section` (set by
  // ApplicationHelper#current_section). When the current section has
  // an entry AND the matching dialog is mounted on the page, the
  // section modal is opened. Otherwise the fallback modal is opened.
  //
  // Today only `games` has a section modal — `omnisearch-modal-games-search`
  // (local games + bundles + IGDB), mounted at the bottom of
  // `app/views/games/index.html.erb`. Other sections (`channels`,
  // `settings`, `home`) have no section-specific surface and pass
  // through to the layout-mounted everywhere modal.
  //
  // To add a section-specific modal in the future:
  //   1. Mount `<dialog id="omnisearch-modal-<section>">` on that
  //      section's view (or in a partial reachable from it).
  //   2. Add an entry below mapping the section name to the dialog id.
  // No keybindings.yml change required.
  get sectionModalMap() {
    return {
      games: "omnisearch-modal-games-search"
    }
  }

  openSectionModalOrFallback(fallbackModalId) {
    const section = document.body.dataset.section || ""
    const sectionModalId = this.sectionModalMap[section]
    if (sectionModalId) {
      const sectionDlg = document.getElementById(sectionModalId)
      if (sectionDlg) {
        this.openModal(sectionModalId)
        return
      }
    }
    this.openModal(fallbackModalId)
  }

  // Locate the `<dialog id=action.modal_id>` and open it. Prefers the
  // modal's own Stimulus controller `.open()` (omnisearch modal
  // resets state + focuses input on open) and falls back to a bare
  // `showModal()` so future plain-dialog targets still work. No-op
  // when the dialog isn't on the page (e.g. the games-search modal
  // isn't mounted on /channels yet — Phase B grows it).
  openModal(modalId) {
    const dlg = document.getElementById(modalId)
    if (!dlg) return
    const app = window.Stimulus
    if (app && typeof app.getControllerForElementAndIdentifier === "function") {
      // Try every controller identifier the dialog declares; pick the
      // first one that exposes a callable `.open()`. The omnisearch
      // dialog identifies as `omnisearch-modal` today.
      const identifiers = (dlg.dataset.controller || "").split(/\s+/).filter(Boolean)
      for (const id of identifiers) {
        const ctrl = app.getControllerForElementAndIdentifier(dlg, id)
        if (ctrl && typeof ctrl.open === "function") {
          ctrl.open()
          return
        }
      }
    }
    if (typeof dlg.showModal === "function" && !dlg.open) {
      dlg.showModal()
    }
  }

  // Dispatch a custom event the leader controller listens for; the
  // leader opens its popup, flips `data-compact="true"`, and seeds
  // its prefix accumulator with `prefix`. Centralising the open +
  // seed flow on the leader controller keeps every popup-open path
  // routed through one code path (SPACE-toggle, `[_]` link click,
  // flat-key compact open).
  openLeaderWithPrefix(prefix) {
    document.dispatchEvent(
      new CustomEvent("flat-key:open-leader-with-prefix", {
        detail: { prefix: prefix }
      })
    )
  }

  // Pass-through gate: while focus sits on a form-entry surface the
  // flat-key controller MUST NOT swallow the keypress — SPACE has to
  // land in the input, a `/` typed in a search box stays literal, a
  // focused button + SPACE still submits the form. Mirror of
  // `leader_menu_controller#isEditableTarget`.
  isEditableTarget(target) {
    if (!target || !target.matches) return false
    return target.matches(
      "input, textarea, select, button, [contenteditable], [contenteditable='true']"
    )
  }
}
