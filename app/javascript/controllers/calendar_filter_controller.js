import { Controller } from "@hotwired/stimulus"

// Phase 15 §2 — filter chips. Keeps the URL in sync with the active
// filter via plain anchor navigation (Turbo handles the swap). The
// controller exists as a hook for future enhancements (multi-select,
// keyboard shortcuts) and to make the spec-required Stimulus footprint
// explicit.
export default class extends Controller {
  // No actions wired in v1 — the chips are plain `<a>` elements that
  // navigate via Turbo. Reserved for follow-up multi-select support.
  connect() {}
}
