// Phase 7.5 §06 — Footage scrub Stimulus controller.
//
// DaVinci-style scrub layout for the footage detail page. Mirrors the
// `pito` CLI's `extras/cli/src/ui/footage_detail/` screen — same wire
// shape (manifest JSON + per-frame JPEG GETs), same scrub semantics
// (hover-on-preview maps cursor X ratio to a timestamp; strip scroll
// under fixed center playhead picks the active cell).
//
// On connect:
//   1. Fetch `<manifestUrl>` (returns `{duration_seconds, timestamps[]}`).
//   2. If `timestamps` is empty, surface the "no frames yet" placeholder
//      and bail out of scrub wiring. The detail page still renders the
//      metadata table below — scrub is additive.
//   3. Otherwise: render strip cells (one `<img>` per timestamp), set
//      the big preview to the median timestamp's master, and bind the
//      scrub interactions.
//
// The two scrub interactions both update a single `activeIndex` into
// the manifest's `timestamps` array. Mouse-move on the big preview
// converts cursor X / preview width into a 0..1 ratio over the manifest
// length. Scrolling the strip uses the strip's centered cell as the
// authority.
//
// Strip cells are built via `document.createElement` (not innerHTML)
// so the integer timestamps from the JSON manifest can never escape
// into the DOM as HTML — defense-in-depth even though the values come
// from our own server.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bigPreview", "emptyState", "strip"]
  static values = {
    footageId: Number,
    durationSeconds: Number,
    manifestUrl: String,
    masterUrlTemplate: String,
    thumbUrlTemplate: String,
  }

  connect() {
    this.timestamps = []
    this.activeIndex = 0
    this.fetchManifest()
  }

  async fetchManifest() {
    try {
      const response = await fetch(this.manifestUrlValue, {
        headers: { Accept: "application/json" },
      })
      if (!response.ok) {
        this.showEmpty()
        return
      }
      const manifest = await response.json()
      this.timestamps = Array.isArray(manifest.timestamps) ? manifest.timestamps : []
      if (this.timestamps.length === 0) {
        this.showEmpty()
        return
      }
      this.renderStrip()
      this.setActiveIndex(Math.floor(this.timestamps.length / 2))
      this.bindScrubInteractions()
    } catch (_e) {
      this.showEmpty()
    }
  }

  showEmpty() {
    if (this.hasBigPreviewTarget) {
      this.bigPreviewTarget.hidden = true
    }
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.hidden = false
    }
  }

  renderStrip() {
    if (!this.hasStripTarget) return
    const strip = this.stripTarget
    while (strip.firstChild) strip.removeChild(strip.firstChild)
    this.timestamps.forEach((ts, idx) => {
      const stamp = this.formatTimestamp(ts)
      const cell = document.createElement("img")
      cell.className = "footage-scrub-cell"
      cell.setAttribute("data-index", String(idx))
      cell.setAttribute("data-timestamp", String(ts))
      cell.alt = ""
      cell.loading = "lazy"
      cell.src = this.thumbUrlTemplateValue.replace("%{timestamp}", stamp)
      strip.appendChild(cell)
    })
  }

  bindScrubInteractions() {
    if (this.hasBigPreviewTarget) {
      this.bigPreviewTarget.addEventListener("mousemove", this.onPreviewMove)
    }
    if (this.hasStripTarget) {
      this.stripTarget.addEventListener("click", this.onStripClick)
      this.stripTarget.addEventListener("scroll", this.onStripScroll, { passive: true })
    }
  }

  disconnect() {
    if (this.hasBigPreviewTarget) {
      this.bigPreviewTarget.removeEventListener("mousemove", this.onPreviewMove)
    }
    if (this.hasStripTarget) {
      this.stripTarget.removeEventListener("click", this.onStripClick)
      this.stripTarget.removeEventListener("scroll", this.onStripScroll)
    }
  }

  onPreviewMove = (event) => {
    const rect = event.currentTarget.getBoundingClientRect()
    if (rect.width <= 0) return
    const ratio = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width))
    const idx = Math.min(
      this.timestamps.length - 1,
      Math.floor(ratio * this.timestamps.length)
    )
    this.setActiveIndex(idx)
  }

  onStripClick = (event) => {
    const target = event.target
    if (!(target instanceof HTMLElement)) return
    const idxAttr = target.getAttribute("data-index")
    if (idxAttr === null) return
    const idx = parseInt(idxAttr, 10)
    if (Number.isNaN(idx)) return
    this.setActiveIndex(idx)
  }

  onStripScroll = () => {
    if (!this.hasStripTarget || this.timestamps.length === 0) return
    const strip = this.stripTarget
    const center = strip.scrollLeft + strip.clientWidth / 2
    const cells = strip.querySelectorAll(".footage-scrub-cell")
    let bestIdx = 0
    let bestDist = Infinity
    cells.forEach((cell, idx) => {
      const cellCenter = cell.offsetLeft + cell.offsetWidth / 2
      const dist = Math.abs(cellCenter - center)
      if (dist < bestDist) {
        bestDist = dist
        bestIdx = idx
      }
    })
    this.setActiveIndex(bestIdx)
  }

  setActiveIndex(idx) {
    if (idx < 0 || idx >= this.timestamps.length) return
    this.activeIndex = idx
    const ts = this.timestamps[idx]
    if (this.hasBigPreviewTarget) {
      const stamp = this.formatTimestamp(ts)
      this.bigPreviewTarget.src = this.masterUrlTemplateValue.replace("%{timestamp}", stamp)
      this.bigPreviewTarget.hidden = false
    }
  }

  // Mirrors the wire-format helper in `extras/cli/src/api/thumbnails.rs`'s
  // `format_timestamp`. Zero-padded `HH-MM-SS` from a u64 of seconds.
  formatTimestamp(seconds) {
    const h = Math.floor(seconds / 3600)
    const m = Math.floor((seconds % 3600) / 60)
    const s = Math.floor(seconds % 60)
    return `${String(h).padStart(2, "0")}-${String(m).padStart(2, "0")}-${String(s).padStart(2, "0")}`
  }
}
