import { Controller } from "@hotwired/stimulus"

// Phase 14 §3 — drag-scroll + mouse-wheel-horizontal scroll on shelf
// rows. Listens for `wheel` events with `deltaY` and translates them
// into `scrollLeft += deltaY` so the user can spin the wheel anywhere
// over a shelf and slide the row sideways. Also supports
// click-and-drag to scroll (touchpad-less navigation).
//
// NO `confirm()` / `alert()` / `prompt()` — pure UI affordance.
export default class extends Controller {
  static targets = ["row"]

  connect() {
    const row = this.hasRowTarget ? this.rowTarget : this.element
    if (!row) return
    this.row = row

    this.onWheel = this.onWheel.bind(this)
    this.onMouseDown = this.onMouseDown.bind(this)
    this.onMouseMove = this.onMouseMove.bind(this)
    this.onMouseUp = this.onMouseUp.bind(this)

    row.addEventListener("wheel", this.onWheel, { passive: false })
    row.addEventListener("mousedown", this.onMouseDown)
  }

  disconnect() {
    if (!this.row) return
    this.row.removeEventListener("wheel", this.onWheel)
    this.row.removeEventListener("mousedown", this.onMouseDown)
    document.removeEventListener("mousemove", this.onMouseMove)
    document.removeEventListener("mouseup", this.onMouseUp)
  }

  onWheel(event) {
    // Ignore horizontal-dominant wheel (trackpad horizontal scrolls).
    if (Math.abs(event.deltaY) <= Math.abs(event.deltaX)) return

    // Compute whether the shelf can absorb the wheel in the requested direction.
    const wantsRight = event.deltaY > 0
    const wantsLeft = event.deltaY < 0
    const canScrollRight =
      this.row.scrollLeft < this.row.scrollWidth - this.row.clientWidth - 1
    const canScrollLeft = this.row.scrollLeft > 0

    // If shelf has nowhere to go in the requested direction, let the page
    // scroll naturally (fixes Brave wheel-debt accumulator bug).
    if ((wantsRight && !canScrollRight) || (wantsLeft && !canScrollLeft)) return

    // Intercept ONLY when shelf will actually move.
    event.preventDefault()
    this.row.scrollLeft += event.deltaY
  }

  onMouseDown(event) {
    if (event.button !== 0) return
    this.dragging = true
    this.startX = event.pageX - this.row.offsetLeft
    this.startScroll = this.row.scrollLeft
    document.addEventListener("mousemove", this.onMouseMove)
    document.addEventListener("mouseup", this.onMouseUp)
  }

  onMouseMove(event) {
    if (!this.dragging) return
    const x = event.pageX - this.row.offsetLeft
    const delta = x - this.startX
    this.row.scrollLeft = this.startScroll - delta
  }

  onMouseUp() {
    this.dragging = false
    document.removeEventListener("mousemove", this.onMouseMove)
    document.removeEventListener("mouseup", this.onMouseUp)
  }
}
