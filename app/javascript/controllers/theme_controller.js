import { Controller } from "@hotwired/stimulus"

// Manages dark/light theme toggle.
//
// Phase 29 (settings refactor) — localStorage only. Server-side theme
// persistence (the `/settings/theme` PATCH endpoint and the
// `data-theme-preference` attribute on `<html>`) was dropped along
// with the Settings → ui/ux pane. The controller now reads + writes
// `pito-theme` in localStorage exclusively; absent value == auto
// (track system preference).
//
// 2026-05-17 — the global `t` keybind that toggled the theme was
// removed in the legacy-keyboard-shortcut sweep. Theme toggling now
// happens exclusively via the `toggle` action wired on the visible
// `[theme]` affordance in the header / settings; per the user rule
// the only allowed global keybindings are the leader-menu (SPACE,
// driven by `config/keybindings.yml` `menus:`) and the per-page
// actions (`page_actions:` in the same file). `t` was in neither.
export default class extends Controller {
  static targets = ["toggle"]

  connect() {
    this.applyTheme()
    this.mediaQuery = window.matchMedia("(prefers-color-scheme: dark)")
    this.mediaQuery.addEventListener("change", this.onSystemChange)
  }

  disconnect() {
    this.mediaQuery?.removeEventListener("change", this.onSystemChange)
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
