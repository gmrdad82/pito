import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="tui-bottom-status-bar"
//
// FB-112 (2026-05-20) — NORMAL/INSERT mode indicator.
// Listens for the `tui:mode-changed` event broadcast by the
// `tui-cursor` controller and repaints the mode lozenge text +
// `.bsb-mode--<mode>` class so the color cycles per ADR 0017
// (cyan for normal, future purple for insert, etc.).
//
// The initial paint comes from the SSR `mode:` arg on the component
// (today always `:normal`). This controller takes over after mount.
export default class extends Controller {
  static targets = ["mode"]

  // Whitelist of valid mode classes — keep in sync with
  // `Tui::BottomStatusBarComponent::MODES` (normal / command / search)
  // plus the new `insert` mode introduced in FB-112.
  static MODE_CLASSES = [
    "bsb-mode--normal",
    "bsb-mode--command",
    "bsb-mode--search",
    "bsb-mode--insert"
  ]

  connect() {
    this.boundModeChanged = this.handleModeChanged.bind(this)
    document.addEventListener("tui:mode-changed", this.boundModeChanged)
  }

  disconnect() {
    if (this.boundModeChanged) {
      document.removeEventListener("tui:mode-changed", this.boundModeChanged)
      this.boundModeChanged = null
    }
  }

  handleModeChanged(event) {
    if (!this.hasModeTarget) return
    const mode = event?.detail?.mode
    if (!mode) return
    this.modeTarget.textContent = mode
    this.constructor.MODE_CLASSES.forEach((cls) => {
      this.modeTarget.classList.remove(cls)
    })
    this.modeTarget.classList.add(`bsb-mode--${mode}`)
  }
}
