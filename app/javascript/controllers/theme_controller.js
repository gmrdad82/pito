import { Controller } from "@hotwired/stimulus"

// Module-level live read of the mandatory-2FA enrollment gate.
// Mirror of the helper in `keyboard_controller.js` /
// `leader_menu_controller.js`; kept duplicated rather than extracted
// to a shared module so each controller stays self-contained for
// importmap simplicity. See the layout's head comment for the full
// rationale on `<meta>`-in-head vs body-mounted signal.
function enrollTotpGateActive() {
  const meta = document.querySelector('meta[name="pito-enroll-totp-gate"]')
  return meta?.getAttribute("content") === "yes"
}

// Manages dark/light theme toggle.
//
// Phase 29 (settings refactor) — localStorage only. Server-side theme
// persistence (the `/settings/theme` PATCH endpoint and the
// `data-theme-preference` attribute on `<html>`) was dropped along
// with the Settings → ui/ux pane. The controller now reads + writes
// `pito-theme` in localStorage exclusively; absent value == auto
// (track system preference).
export default class extends Controller {
  static targets = ["toggle"]

  connect() {
    this.applyTheme()
    this.mediaQuery = window.matchMedia("(prefers-color-scheme: dark)")
    this.mediaQuery.addEventListener("change", this.onSystemChange)
    this.boundKeydown = this.onKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    this.mediaQuery?.removeEventListener("change", this.onSystemChange)
    document.removeEventListener("keydown", this.boundKeydown)
  }

  onKeydown(event) {
    // Mandatory-2FA enrollment gate. When the authenticated user has
    // not configured TOTP, the layout renders
    // `<meta name="pito-enroll-totp-gate" content="yes">` in `<head>`
    // and the `t` theme toggle is inert alongside every other global
    // shortcut — the enrollment dialog must be the only interactive
    // surface until 2FA is set up. The enrollment form's own keys
    // (typing the 6-digit code, Tab between fields, Enter to submit)
    // are unaffected because `t` only fires on non-input focus, and
    // typing in the code input is `<input>`-targeted anyway.
    // Released the moment enrollment completes (next page render
    // flips the meta content back to `"no"`).
    //
    // Why a `<meta>` in `<head>` rather than a body data-attribute
    // or inline body `<script>`: see the layout comment next to the
    // meta tag.
    if (enrollTotpGateActive()) return
    if (event.target.matches("input, textarea, select, [contenteditable]")) return
    if (event.metaKey || event.ctrlKey || event.altKey) return
    // Theme toggle keybind: `t`. Was `n` historically; moved to `t`
    // alongside the navbar redesign that retired the visible `n` keycap
    // affordance. The bracketed-link convention sweep treats theme
    // toggling as a Settings affordance now, so the visible chrome is
    // gone and only the keybind remains.
    if (event.key === "t") {
      event.preventDefault()
      this.doToggle()
    }
  }

  toggle(event) {
    event.preventDefault()
    this.doToggle()
  }

  doToggle() {
    const current = this.effectiveTheme()
    const next = current === "dark" ? "light" : "dark"
    localStorage.setItem("pito-theme", next)
    this.applyTheme()
  }

  applyTheme() {
    const theme = this.effectiveTheme()
    document.documentElement.setAttribute("data-theme", theme)
    if (window.recolorCharts) setTimeout(window.recolorCharts, 50)
  }

  effectiveTheme() {
    const stored = localStorage.getItem("pito-theme")
    if (stored === "light" || stored === "dark") return stored
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
  }

  onSystemChange = () => {
    const pref = localStorage.getItem("pito-theme")
    // Only react to system changes if user hasn't set an explicit
    // preference (absent localStorage entry == auto).
    if (!pref) {
      this.applyTheme()
    }
  }
}
