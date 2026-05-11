import { Controller } from "@hotwired/stimulus"

// Phase 7.5 §11c — Channel edit form, watermark variant.
//
// Validates a picked image file BEFORE submission per D14 / D22
// (hard reject with specific reason). The watermark spec per
// YouTube docs (verified for 11c): 800×800 PNG or JPEG, max 1 MB.
//
// Server-side validation is the authoritative gate; this controller
// is UX — instant feedback so the user does not roundtrip through
// the form submit to learn the file is the wrong shape.
//
// Banner variant of file-upload is owned by sub-spec 11f and lives
// in a separate controller (`banner_upload_controller.js`); the
// dimension / size / type spec differs.
//
// Strict no `confirm()` / `alert()` / `prompt()` per CLAUDE.md hard rule.
const ALLOWED_TYPES = ["image/png", "image/jpeg"]
const MAX_SIZE_BYTES = 1_048_576 // 1 MB
const REQUIRED_DIMENSION = 800

export default class extends Controller {
  static targets = ["input", "error", "timing", "offsetContainer", "removeFlag"]

  connect() {
    this.toggleOffset()
  }

  // Hooked from the watermark `<select>` `change` event. Reveals /
  // hides the `offset_ms` input depending on the picked timing.
  toggleOffset() {
    if (!this.hasOffsetContainerTarget || !this.hasTimingTarget) return
    const t = this.timingTarget.value
    const needsOffset = t === "offset_from_start" || t === "offset_from_end"
    this.offsetContainerTarget.hidden = !needsOffset
  }

  // Hooked from the file `<input type="file">` `change` event.
  validate() {
    if (!this.hasInputTarget) return
    const file = this.inputTarget.files && this.inputTarget.files[0]
    this.clearError()
    if (!file) return

    if (!ALLOWED_TYPES.includes(file.type)) {
      this.showError("file type: PNG or JPEG required")
      this.inputTarget.value = ""
      return
    }
    if (file.size > MAX_SIZE_BYTES) {
      this.showError(`file size: exceeds ${MAX_SIZE_BYTES / 1024 / 1024} MB`)
      this.inputTarget.value = ""
      return
    }

    this.validateDimensions(file)
  }

  validateDimensions(file) {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      URL.revokeObjectURL(url)
      if (img.naturalWidth !== REQUIRED_DIMENSION || img.naturalHeight !== REQUIRED_DIMENSION) {
        this.showError(`pixel dimensions: ${REQUIRED_DIMENSION}×${REQUIRED_DIMENSION} required`)
        this.inputTarget.value = ""
      }
    }
    img.onerror = () => {
      URL.revokeObjectURL(url)
      this.showError("could not read image file")
      this.inputTarget.value = ""
    }
    img.src = url
  }

  showError(msg) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = msg
    this.errorTarget.hidden = false
  }

  clearError() {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = ""
    this.errorTarget.hidden = true
  }
}
