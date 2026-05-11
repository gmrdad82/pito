import { Controller } from "@hotwired/stimulus"

// Phase 7.5 §11f — Channel edit form, banner-upload variant.
//
// Drag-drop + file-picker + client-side validation (type / dimensions
// / aspect / size) + multi-size preview generation. Server-side
// validation is the authoritative gate (per D14); this controller is
// UX — instant feedback so the user does not roundtrip through the
// submit to learn the file is the wrong shape.
//
// Validation rules (D14 / D22 — clear reasons on every reject):
//   - File type: JPEG or PNG only
//   - Dimensions: minimum 2048x1152
//   - Aspect ratio: 16:9 (with a small tolerance for JPEG rounding)
//   - File size: max 6MB
//
// All rejection reasons render simultaneously (no first-fail-only).
// `URL.createObjectURL` blob URLs are revoked after preview
// generation completes. Form submit is blocked while the async
// client check is running; a progress indicator shows during the
// async wait.
//
// Strict no `alert()` / `confirm()` / `prompt()` per CLAUDE.md.
//
// Watermark variant of the upload UX lives in
// `file_upload_controller.js` — distinct dimensions / aspect / size.

const ALLOWED_TYPES = ["image/png", "image/jpeg"]
const ALLOWED_TYPE_LABEL = "JPEG or PNG"

export default class extends Controller {
  static targets = [
    "input",
    "dropZone",
    "pickerButton",
    "progress",
    "errors",
    "previewContainer",
    "previewWeb",
    "previewMobile",
    "previewTv"
  ]

  static values = {
    minWidth: { type: Number, default: 2048 },
    minHeight: { type: Number, default: 1152 },
    aspectRatio: { type: Number, default: 16 / 9 },
    aspectTolerance: { type: Number, default: 0.02 },
    maxSizeBytes: { type: Number, default: 6 * 1024 * 1024 }
  }

  connect() {
    this._validating = false
    this._validFile = false
    this._blobUrls = []
    this._form = this.element.closest("form")
    if (this._form) {
      this._submitListener = (event) => this.onFormSubmit(event)
      this._form.addEventListener("submit", this._submitListener)
    }
  }

  disconnect() {
    if (this._form && this._submitListener) {
      this._form.removeEventListener("submit", this._submitListener)
    }
    this.revokeAllBlobUrls()
  }

  // Click on the `[pick file]` link forwards to the hidden file input.
  openPicker(event) {
    event.preventDefault()
    if (this.hasInputTarget) {
      this.inputTarget.click()
    }
  }

  // dragover: indicate drop is OK (cursor + outline hint).
  onDragOver(event) {
    event.preventDefault()
    if (this.hasDropZoneTarget) {
      this.dropZoneTarget.style.borderColor = "#1a1a1a"
    }
  }

  onDragLeave(event) {
    event.preventDefault()
    if (this.hasDropZoneTarget) {
      this.dropZoneTarget.style.borderColor = "#ddd"
    }
  }

  // drop: forward the dropped file into the hidden input then run
  // validation, mirroring the file-picker path.
  onDrop(event) {
    event.preventDefault()
    if (this.hasDropZoneTarget) {
      this.dropZoneTarget.style.borderColor = "#ddd"
    }
    const dt = event.dataTransfer
    if (!dt || !dt.files || dt.files.length === 0) return
    const file = dt.files[0]
    if (this.hasInputTarget) {
      // Assign the dropped file to the hidden input so form submit
      // carries it; some browsers require a DataTransfer round-trip.
      try {
        const transfer = new DataTransfer()
        transfer.items.add(file)
        this.inputTarget.files = transfer.files
      } catch (_e) {
        // Older Safari fallback — leave the input empty and the
        // file in dt; validate against `file` directly.
      }
    }
    this.validate(file)
  }

  onFilePicked() {
    if (!this.hasInputTarget) return
    const file = this.inputTarget.files && this.inputTarget.files[0]
    if (!file) return
    this.validate(file)
  }

  // Main entrypoint. Synchronous checks first (type, size); then
  // load the image to read pixel dimensions (async). All rejection
  // reasons accumulate so the user sees every failure at once.
  validate(file) {
    this.clearErrors()
    this.hidePreview()
    this._validFile = false
    const errors = []

    if (!ALLOWED_TYPES.includes(file.type)) {
      errors.push(`File type: ${ALLOWED_TYPE_LABEL} required.`)
    }

    if (file.size > this.maxSizeBytesValue) {
      errors.push(`File size: max ${this.humanMb(this.maxSizeBytesValue)} (got ${this.humanBytes(file.size)}).`)
    }

    this._validating = true
    this.showProgress()

    this.readDimensions(file).then((dims) => {
      this._validating = false
      this.hideProgress()

      if (!dims) {
        errors.push("Could not read image dimensions.")
      } else {
        const { width, height } = dims
        if (width < this.minWidthValue || height < this.minHeightValue) {
          errors.push(`Dimensions: minimum ${this.minWidthValue}x${this.minHeightValue} required (got ${width}x${height}).`)
        }
        const actualAspect = width / height
        if (Math.abs(actualAspect - this.aspectRatioValue) > this.aspectToleranceValue) {
          errors.push(`Aspect ratio: 16:9 required (got ${actualAspect.toFixed(3)}:1).`)
        }
      }

      if (errors.length > 0) {
        this.showErrors(errors)
        this.clearStagedFile()
      } else {
        this._validFile = true
        this.renderPreview(file)
      }
    }).catch(() => {
      this._validating = false
      this.hideProgress()
      errors.push("Could not read image dimensions.")
      this.showErrors(errors)
      this.clearStagedFile()
    })
  }

  // Returns a Promise<{width, height} | null>.
  readDimensions(file) {
    return new Promise((resolve) => {
      const url = URL.createObjectURL(file)
      this._blobUrls.push(url)
      const img = new Image()
      img.onload = () => {
        const dims = { width: img.naturalWidth, height: img.naturalHeight }
        URL.revokeObjectURL(url)
        this._blobUrls = this._blobUrls.filter((u) => u !== url)
        resolve(dims)
      }
      img.onerror = () => {
        URL.revokeObjectURL(url)
        this._blobUrls = this._blobUrls.filter((u) => u !== url)
        resolve(null)
      }
      img.src = url
    })
  }

  // Generate one preview blob URL, point all three preview `<img>`s
  // at it (CSS sizing handles the size variants), then revoke after
  // every image has loaded. Browsers cache the decoded image so the
  // single blob URL feeds all three previews cheaply.
  renderPreview(file) {
    if (!this.hasPreviewContainerTarget) return
    const url = URL.createObjectURL(file)
    this._blobUrls.push(url)

    const targets = []
    if (this.hasPreviewWebTarget) targets.push(this.previewWebTarget)
    if (this.hasPreviewMobileTarget) targets.push(this.previewMobileTarget)
    if (this.hasPreviewTvTarget) targets.push(this.previewTvTarget)

    let pending = targets.length
    if (pending === 0) {
      URL.revokeObjectURL(url)
      this._blobUrls = this._blobUrls.filter((u) => u !== url)
      return
    }

    const onAnyLoad = () => {
      pending -= 1
      if (pending <= 0) {
        URL.revokeObjectURL(url)
        this._blobUrls = this._blobUrls.filter((u) => u !== url)
      }
    }

    targets.forEach((img) => {
      img.onload = onAnyLoad
      img.onerror = onAnyLoad
      img.src = url
    })

    this.previewContainerTarget.hidden = false
  }

  hidePreview() {
    if (this.hasPreviewContainerTarget) {
      this.previewContainerTarget.hidden = true
    }
    if (this.hasPreviewWebTarget) this.previewWebTarget.removeAttribute("src")
    if (this.hasPreviewMobileTarget) this.previewMobileTarget.removeAttribute("src")
    if (this.hasPreviewTvTarget) this.previewTvTarget.removeAttribute("src")
  }

  showProgress() {
    if (this.hasProgressTarget) {
      this.progressTarget.hidden = false
    }
  }

  hideProgress() {
    if (this.hasProgressTarget) {
      this.progressTarget.hidden = true
    }
  }

  showErrors(messages) {
    if (!this.hasErrorsTarget) return
    while (this.errorsTarget.firstChild) {
      this.errorsTarget.removeChild(this.errorsTarget.firstChild)
    }
    messages.forEach((msg) => {
      const line = document.createElement("p")
      line.style.margin = "0"
      line.textContent = msg
      this.errorsTarget.appendChild(line)
    })
    this.errorsTarget.hidden = false
  }

  clearErrors() {
    if (!this.hasErrorsTarget) return
    while (this.errorsTarget.firstChild) {
      this.errorsTarget.removeChild(this.errorsTarget.firstChild)
    }
    this.errorsTarget.hidden = true
  }

  clearStagedFile() {
    if (this.hasInputTarget) {
      this.inputTarget.value = ""
    }
  }

  revokeAllBlobUrls() {
    this._blobUrls.forEach((url) => {
      try { URL.revokeObjectURL(url) } catch (_e) { /* noop */ }
    })
    this._blobUrls = []
  }

  // Form submit gate: block if validation is still running OR if a
  // file is staged but failed client checks. If no file is staged
  // at all (user is editing other fields), let the submit through.
  onFormSubmit(event) {
    if (this._validating) {
      event.preventDefault()
      this.showErrors([ "Still validating image; please wait." ])
      return
    }

    const hasFile = this.hasInputTarget && this.inputTarget.files && this.inputTarget.files.length > 0
    if (hasFile && !this._validFile) {
      event.preventDefault()
      // Errors already on screen from the failed validate(); leave them.
    }
  }

  humanBytes(bytes) {
    if (bytes >= 1024 * 1024) {
      return `${(bytes / (1024 * 1024)).toFixed(1)}MB`
    }
    if (bytes >= 1024) {
      return `${Math.round(bytes / 1024)}KB`
    }
    return `${bytes}B`
  }

  humanMb(bytes) {
    return `${Math.round(bytes / (1024 * 1024))}MB`
  }
}
