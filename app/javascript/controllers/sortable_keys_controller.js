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

    // FB (2026-05-24) — when a sub-panel is focused inside the focused
    // panel, narrow scope to it so `s` / `S` only sort the sub-panel
    // the cursor is in (e.g. Meilisearch vs Voyage on the stack panel).
    // Without this scoping, the outer focused panel finds ALL sub-panel
    // sortable headers and picks the DOM-first one, which is wrong when
    // the cursor is elsewhere.
    const focusedSubPanel = document.querySelector(
      '[data-tui-cursor-sub-panel-focused="yes"]',
    );
    const scope = focusedSubPanel || focusedPanel;

    // Only act when the scope actually contains a sortable table.
    if (!scope.querySelector("th.sortable")) return;

    if (event.key === "s" && !event.shiftKey) {
      if (this.cycleNextSortable(scope)) {
        event.preventDefault();
      }
    } else if (event.key === "S" && event.shiftKey) {
      if (this.toggleCurrentDirection(scope)) {
        event.preventDefault();
      }
    }
  }

  // Two rendering shapes are supported:
  //   * `<th class="sortable"><a>...</a></th>` — server-rendered via
  //     `sort_link_to`. The active sort lives on the inner anchor
  //     (`<a class="sort-asc">`). Click the anchor to sort.
  //   * `<th class="sortable">...</th>` — client-side rendered via
  //     `SortableHeaderComponent` + `sortable_table_controller`. The
  //     active sort lives on the `<th>` itself (`<th class="sortable
  //     sort-asc">`). Click the `<th>` to sort.
  // The helpers below pick the right element shape per call so both
  // patterns participate in `s` / `S` keyboard sort.
  _sortableTargets(panel) {
    return Array.from(panel.querySelectorAll("th.sortable")).map(th => {
      const anchor = th.querySelector(":scope > a");
      return anchor || th;
    });
  }

  _activeSortable(panel) {
    const ths = Array.from(panel.querySelectorAll("th.sortable"));
    for (const th of ths) {
      const anchor = th.querySelector(":scope > a");
      if (anchor && (anchor.classList.contains("sort-asc") || anchor.classList.contains("sort-desc"))) {
        return anchor;
      }
      if (th.classList.contains("sort-asc") || th.classList.contains("sort-desc")) {
        return th;
      }
    }
    return null;
  }

  // Returns true when a click was dispatched, false on no-op.
  cycleNextSortable(panel) {
    const targets = this._sortableTargets(panel);
    if (targets.length === 0) return false;

    const active = this._activeSortable(panel);
    let nextIndex = 0;
    if (active) {
      const currentIndex = targets.indexOf(active);
      if (currentIndex >= 0) {
        nextIndex = (currentIndex + 1) % targets.length;
      }
    }
    targets[nextIndex].click();
    return true;
  }

  // Returns true when a click was dispatched, false on no-op.
  toggleCurrentDirection(panel) {
    const active = this._activeSortable(panel);
    if (!active) return false;
    // `sort_link_to` flips asc<->desc on each repeat click of the
    // currently-active column. `sortable_table_controller` also
    // toggles direction on repeat click. Single click works for
    // both shapes.
    active.click();
    return true;
  }
}
