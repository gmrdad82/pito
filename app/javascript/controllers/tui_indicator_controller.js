import { Controller } from "@hotwired/stimulus"

// Beta 4 — Phase F2. Stimulus controller for `Tui::IndicatorComponent`
// in :idle and :indeterminate modes. Advances the frame index at the
// variant's locked cadence. :progress and :error modes are static and
// don't mount this controller.
//
// `startOffsetValue` lets multiple instances on the page de-sync so a
// shelf of spinners doesn't beat in unison.
//
// ADR 0016 locks frames + cadence. Drifting either silently changes
// the feel of every indicator in the app.
export default class extends Controller {
  static values = {
    variant: String,
    startOffset: { type: Number, default: 0 }
  }

  static FRAMES = {
    bounce_equals: ["=---", "-=--", "--=-", "---=", "--=-", "-=--"],
    braille: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  }

  static CADENCE_MS = {
    bounce_equals: 120,
    braille: 100
  }

  connect() {
    const frames = this.constructor.FRAMES[this.variantValue]
    if (!frames) return
    this.frames = frames
    this.idx = this.startOffsetValue % frames.length
    const cadence = this.constructor.CADENCE_MS[this.variantValue]
    this.element.textContent = this.frames[this.idx]
    this.timer = setInterval(() => this.tick(), cadence)
  }

  disconnect() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  tick() {
    this.idx = (this.idx + 1) % this.frames.length
    this.element.textContent = this.frames[this.idx]
  }
}
