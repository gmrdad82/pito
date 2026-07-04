// Pito::AppBannerController
//
// Reveals the "get the app" banner unless this browser dismissed it before,
// and persists the dismissal. The banner ships hidden so a dismissed visitor
// never gets a flash of banner before the controller connects. Ephemeral
// per-browser preference → localStorage, not the server.

import { Controller } from "@hotwired/stimulus"

const DISMISSED_KEY = "pito:app-banner-dismissed"

export default class extends Controller {
  connect() {
    if (localStorage.getItem(DISMISSED_KEY)) return
    this.element.classList.remove("hidden")
  }

  dismiss() {
    localStorage.setItem(DISMISSED_KEY, "1")
    this.element.classList.add("hidden")
  }
}
