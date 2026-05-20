import { Controller } from "@hotwired/stimulus";

// FB-110 — Sortable column UX keybindings.
//
// Contract:
//   * `s` (NORMAL mode, no shift / ctrl / alt / meta) — cycle to the
//     NEXT sortable column header inside the currently focused panel.
//     "Next" means: if there is an active sort link, move to the next
//     sibling sortable header in DOM order (wrapping back to the first
//     after the last); otherwise click the first sortable header.
//   * `S` (Shift + s) — reverse the direction on the CURRENTLY active
//     sort column. Implemented as a click on the active sort link,
//     since `ApplicationHelper#sort_link_to` toggles asc<->desc on each
//     repeat click of the same column. No-op when no column is active.
//
// Mode + focus contract:
//   * INSERT mode (anything writing to an input/textarea, contenteditable,
//     or a host that explicitly marks itself with `data-tui-mode="insert"`)
//     is a no-op — the user is typing, the bare `s` / `S` keys should
//     reach the input as text.
//   * No focused panel (no `[data-tui-cursor-focused="yes"]` ancestor on
//     the page) is a no-op — keybindings only fire inside the active
//     TUI panel, matching the tui-cursor / sub-cursor focus hierarchy.
//   * Open `<dialog>` elements take precedence — when a dialog is open
//     the panel-scoped sort keybindings are suppressed so dialog text
//     entry / its own keybindings remain unmolested.
//
// Mount: registered on `<body data-controller="... sortable-keys">` in
// `app/views/layouts/application.html.erb`. The listener attaches to
// `document` so it can intercept the keydown before any element-level
// handlers fire — and it `preventDefault()`s when it acts so `s` / `S`
// don't bubble into other global keybindings.
export default class extends Controller {
  connect() {
    this.boundHandler = this.handleKeydown.bind(this);
    document.addEventListener("keydown", this.boundHandler);
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandler);
  }

  handleKeydown(event) {
    // Only the bare `s` / Shift+s flavours matter; bail on any other
    // modifier so Ctrl-s (save), Meta-s, Alt-s remain untouched.
    if (event.ctrlKey || event.metaKey || event.altKey) return;
    if (event.key !== "s" && event.key !== "S") return;

    // INSERT-mode guard: never fire while the user is typing.
    const target = event.target;
    if (target) {
      const tag = target.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
      if (target.isContentEditable) return;
    }
    if (document.querySelector('[data-tui-mode="insert"]')) return;

    // Dialog precedence: skip while any `<dialog>` is open.
    if (document.querySelector("dialog[open]")) return;

    // Panel focus is required — bail when there is no focused panel.
    const focusedPanel = document.querySelector(
      '[data-tui-cursor-focused="yes"]',
    );
    if (!focusedPanel) return;

    // Only act when the focused panel actually contains a sortable table.
    if (!focusedPanel.querySelector("th.sortable")) return;

    if (event.key === "s" && !event.shiftKey) {
      if (this.cycleNextSortable(focusedPanel)) {
        event.preventDefault();
      }
    } else if (event.key === "S" && event.shiftKey) {
      if (this.toggleCurrentDirection(focusedPanel)) {
        event.preventDefault();
      }
    }
  }

  // Returns true when a click was dispatched, false on no-op.
  cycleNextSortable(panel) {
    // Sortable links live in `<th class="sortable"><a>...</a></th>`
    // (server-rendered via `sort_link_to`) — find every such anchor.
    const links = Array.from(panel.querySelectorAll("th.sortable > a"));
    if (links.length === 0) return false;

    const active = panel.querySelector(
      "th.sortable > a.sort-asc, th.sortable > a.sort-desc",
    );
    let nextIndex = 0;
    if (active) {
      const currentIndex = links.indexOf(active);
      if (currentIndex >= 0) {
        nextIndex = (currentIndex + 1) % links.length;
      }
    }
    links[nextIndex].click();
    return true;
  }

  // Returns true when a click was dispatched, false on no-op.
  toggleCurrentDirection(panel) {
    const active = panel.querySelector(
      "th.sortable > a.sort-asc, th.sortable > a.sort-desc",
    );
    if (!active) return false;
    // `sort_link_to` flips asc<->desc on each repeat click of the
    // currently-active column, so a single click is enough.
    active.click();
    return true;
  }
}
