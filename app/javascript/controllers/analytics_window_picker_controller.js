import { Controller } from "@hotwired/stimulus"

// Phase 13.3 — Window picker. The picker partial renders four
// bracketed links that already carry `?window=...` as a query string
// — this controller is a marker so future enhancements (Turbo Frame
// fetches, prefetch on hover) attach without re-templating the view.
export default class extends Controller {
  static targets = ["button"]
  static values = { current: String }
}
