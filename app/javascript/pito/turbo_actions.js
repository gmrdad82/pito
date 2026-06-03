// Custom Turbo Stream actions for pito.
//
// navigate — triggers a real browser navigation to `target`. Used by /connect
// (OAuth) because Turbo submits forms via fetch, which cannot cross-origin
// redirect the browser to Google's auth endpoint. A Turbo Stream navigate
// action uses window.location.href, which IS a real browser navigation.
//
// Usage: <turbo-stream action="navigate" target="/auth/google_oauth2"></turbo-stream>

// @hotwired/turbo is not pinned separately — turbo-rails bundles everything into
// turbo.min.js and exposes window.Turbo globally. Access StreamActions via the
// global rather than an ES module import.
window.addEventListener("turbo:load", function registerTurboActions() {
  Turbo.StreamActions.navigate = function() {
    window.location.href = this.target
  }
  window.removeEventListener("turbo:load", registerTurboActions)
})
