// pito--quick-run
//
// Attached to the scrollback container. Previously listened for ctrl+/ to
// populate the chatbox with the last segment suggestion command.
//
// ctrl+/ is now reserved for opening the notifications sidebar
// (handled by pito--command-palette#onGlobalKey). Quick-run is a no-op
// controller stub kept so existing data-controller="pito--quick-run"
// attributes in the DOM do not raise Stimulus errors.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // No-op: ctrl+/ → notifications (see command_palette_controller.js).
}
