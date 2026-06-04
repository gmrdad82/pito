// pito/ready.js
//
// Sets window.__pitoReady = true after the first full Turbo page load.
//
// Typewriter controllers check this flag on connect():
//   - If true  → the page already cycled through at least one turbo:load, so
//                 newly-appended segments are live cable arrivals → animate.
//   - If false → we are still in the initial server render (controllers connect
//                 before the load event fires) → show full text instantly.
//
// Import this module once from application.js so the listener is registered
// exactly once regardless of how many controllers are on the page.

document.addEventListener("turbo:load", () => {
  window.__pitoReady = true
}, { once: true })

// Belt-and-suspenders: also mark ready on DOMContentLoaded if Turbo fires
// turbo:load before this module is evaluated (edge-case in some Turbo builds).
document.addEventListener("DOMContentLoaded", () => {
  // Only set if turbo:load hasn't set it yet — Turbo fires both on first visit.
  // We do NOT set it here on purpose: initial page load is NOT "ready" for
  // animation.  The turbo:load handler above is the canonical setter.
  // This comment intentionally left as documentation.
}, { once: true })
