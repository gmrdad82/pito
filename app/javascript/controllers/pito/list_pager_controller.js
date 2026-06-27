// pito--list-pager
//
// Generic keyset / infinite-scroll pager. DOMAIN-AGNOSTIC by design — it never
// knows what it is paging, so it drops onto any keyset-paginated list
// (notifications today; videos/games later) untouched.
//
// Markup contract:
//   - the controller element wraps the list and a bottom "sentinel"
//   - targets:
//       list     — the container new rows are appended into (server-driven)
//       sentinel — the bottom marker; carries an OPAQUE server-built
//                  `data-pager-next-url` while more pages exist, and is REPLACED
//                  after each page (new url, or the end-of-list state with none)
//       loader   — (optional, inside the sentinel) a shimmer shown while fetching
//
// Trigger: the sentinel scrolling into view (IntersectionObserver, rooted at the
// nearest scroll container) OR a `pito:list-pager:more` event on the element
// (dispatched by a list's own keyboard nav when ↓ is pressed at the last row).
//
// On trigger it fetches the sentinel's url as a Turbo Stream; the server appends
// the next page's rows and replaces the sentinel. No url → end of list → stop.
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "sentinel", "loader"]

  connect() {
    this.loading = false
    this.element.addEventListener("pito:list-pager:more", this.#onMore)
  }

  disconnect() {
    this.element.removeEventListener("pito:list-pager:more", this.#onMore)
    this.observer?.disconnect()
  }

  // The sentinel is replaced after every page, so (re)bind the observer whenever
  // a fresh one connects. Stimulus fires this for the initial sentinel too.
  sentinelTargetConnected(el) {
    this.observer?.disconnect()
    const root = this.element.closest(".overflow-y-auto") || null
    this.observer = new IntersectionObserver(
      (entries) => { if (entries.some((e) => e.isIntersecting)) this.#load() },
      { root, rootMargin: "200px" }
    )
    this.observer.observe(el)
  }

  sentinelTargetDisconnected() {
    this.observer?.disconnect()
  }

  // Arrow function → stable reference for add/removeEventListener.
  #onMore = () => this.#load()

  #load() {
    if (this.loading) return
    const url = this.hasSentinelTarget ? this.sentinelTarget.dataset.pagerNextUrl : null
    if (!url) return // end of list — nothing more to fetch

    this.loading = true
    if (this.hasLoaderTarget) this.loaderTarget.classList.remove("hidden")

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content || ""
    fetch(url, {
      headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": csrf }
    })
      .then((r) => r.text())
      .then((html) => window.Turbo.renderStreamMessage(html))
      .catch((err) => console.warn("[pito--list-pager] fetch failed:", err))
      .finally(() => { this.loading = false })
  }
}
