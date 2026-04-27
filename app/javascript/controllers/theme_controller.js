import { Controller } from "@hotwired/stimulus"

// Manages dark/light theme toggle.
// Reads initial preference from data-theme-preference on <html>.
// Falls back to localStorage, then system preference.
export default class extends Controller {
  static targets = ["label", "toggle"]

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
    const current = this.effectiveTheme()
    const next = current === "dark" ? "light" : "dark"
    localStorage.setItem("pito-theme", next)
    this.applyTheme({ syncRadio: true })

    // Show loader while saving
    if (this.hasToggleTarget) {
      this.toggleTarget.textContent = ""
      const loader = document.createElement("span")
      loader.className = "dot-loader"
      this.toggleTarget.appendChild(loader)
    }

    // Persist to server
    fetch("/settings/theme", {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      body: JSON.stringify({ theme: next })
    }).then(() => {
      this.restoreToggle()
      this.showFlash(`theme changed to ${next}.`)
    })
  }

  applyTheme({ syncRadio = false } = {}) {
    const theme = this.effectiveTheme()
    document.documentElement.setAttribute("data-theme", theme)
    document.documentElement.dataset.themePreference = localStorage.getItem("pito-theme") || "auto"
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = theme === "dark" ? "light" : "dark"
    }
    if (window.recolorCharts) setTimeout(window.recolorCharts, 50)

    // Only sync radio buttons when triggered by the toggle button
    if (syncRadio) {
      const stored = localStorage.getItem("pito-theme")
      const value = stored || "auto"
      const radio = document.querySelector(`input[name="settings[theme]"][value="${value}"]`)
      if (radio) radio.checked = true
    }
  }

  restoreToggle() {
    if (!this.hasToggleTarget) return
    const theme = this.effectiveTheme()
    const label = theme === "dark" ? "light" : "dark"
    this.toggleTarget.textContent = ""

    const openBracket = document.createTextNode("[ ")
    const span = document.createElement("span")
    span.className = "bl"
    span.dataset.themeTarget = "label"
    span.textContent = label
    const closeBracket = document.createTextNode(" ]")

    this.toggleTarget.appendChild(openBracket)
    this.toggleTarget.appendChild(span)
    this.toggleTarget.appendChild(closeBracket)
  }

  effectiveTheme() {
    const stored = localStorage.getItem("pito-theme")
    if (stored === "light" || stored === "dark") return stored

    const server = document.documentElement.dataset.themePreference
    if (server === "light" || server === "dark") return server
    if (server === "auto" || !server) {
      return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
    }
    return "light"
  }

  showFlash(message) {
    const existing = document.querySelector(".flash-notice")
    if (existing) existing.remove()

    const flash = document.createElement("div")
    flash.className = "flash-notice"
    flash.style.cssText = "margin-bottom: 8px; padding: 4px 8px;"
    flash.textContent = message

    const main = document.querySelector("main")
    const firstChild = main.querySelector("nav, h1, .flash-notice, .flash-error")
    if (firstChild) {
      main.insertBefore(flash, firstChild)
    } else {
      main.prepend(flash)
    }

    setTimeout(() => flash.remove(), 3000)
  }

  onSystemChange = () => {
    const pref = localStorage.getItem("pito-theme")
    const server = document.documentElement.dataset.themePreference
    // Only react to system changes if preference is "auto"
    if (!pref && (!server || server === "auto")) {
      this.applyTheme()
    }
  }
}
