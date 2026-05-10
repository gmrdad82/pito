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
    // Only intercept vertical wheel; leave touchpad horizontal swipes alone.
    if (Math.abs(event.deltaY) <= Math.abs(event.deltaX)) return
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
