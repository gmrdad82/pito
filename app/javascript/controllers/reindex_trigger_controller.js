import { Controller } from "@hotwired/stimulus";

// FB-126 (2026-05-21). Click handler that opens a `Tui::ConfirmationDialogComponent`
// instance by id.
//
// Wired onto the `[reindex]` button in `_stack_pane.html.erb` for both the
// Meilisearch + Voyage sub-panels. The matching dialog (mounted once per
// brand at the bottom of the panel) carries the actual POST form to the
// existing reindex controller endpoint. On dialog confirm the browser
// submits normally; the controller redirects back, and the cable-driven
// `reindex-action` controller picks up the `reindex_started` broadcast and
// swaps `[reindex]` for the `Tui::ReindexProgressComponent` indicator.
export default class extends Controller {
  static values = { dialogId: String };

  open(event) {
    if (event) event.preventDefault();
    const dialog = document.getElementById(this.dialogIdValue);
    if (dialog && typeof dialog.showModal === "function") {
      dialog.showModal();
    }
  }
}
