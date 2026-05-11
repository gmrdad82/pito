// Phase 25 — 01a (LD-2). Login-page fingerprint hint collector.
//
// Reads two privacy-bounded signals from the browser and stuffs them
// into hidden form fields BEFORE the login form submits:
//
//   - screen hint:  window.screen.width + "x" + window.screen.height
//                   + "@" + window.devicePixelRatio
//   - locale hint:  Intl.DateTimeFormat().resolvedOptions().timeZone
//                   + "/" + navigator.language
//
// Server-side composition + hashing happens in
// `Auth::FingerprintComposer`; the controller posts the raw hints so
// the user can read the composition in plain text from one place.
//
// **Forbidden inputs.** This controller deliberately does NOT collect
// canvas, AudioContext, WebGL, font enumeration, or battery info.
// Those signals offer high entropy but invasive tracking — the
// project rule rejects them. The server-side composer rejects them
// defensively as well.
//
// Failure mode: if `window.screen` or `Intl` throws (very old / very
// locked-down browsers), the controller leaves the fields empty and
// proceeds. The server composes the fingerprint without those inputs
// and still records the attempt.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["screen", "locale"]

  connect() {
    try {
      this.fillScreen()
    } catch (_e) {
      // Leave the field blank; the server tolerates an empty hint.
    }
    try {
      this.fillLocale()
    } catch (_e) {
      // Leave the field blank; the server tolerates an empty hint.
    }
  }

  fillScreen() {
    if (!this.hasScreenTarget) return
    const w = window.screen && window.screen.width ? window.screen.width : ""
    const h = window.screen && window.screen.height ? window.screen.height : ""
    const dpr = window.devicePixelRatio || 1
    if (w && h) {
      this.screenTarget.value = `${w}x${h}@${dpr}`
    }
  }

  fillLocale() {
    if (!this.hasLocaleTarget) return
    let tz = ""
    try {
      tz = Intl.DateTimeFormat().resolvedOptions().timeZone || ""
    } catch (_e) {
      tz = ""
    }
    const lang = (navigator && navigator.language) ? navigator.language : ""
    if (tz || lang) {
      this.localeTarget.value = `${tz}/${lang}`
    }
  }
}
