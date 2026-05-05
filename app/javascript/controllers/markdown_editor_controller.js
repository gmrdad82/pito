import { Controller } from "@hotwired/stimulus"

// Phase B post-commit (2026-05-04) — Note revamp.
//
// Live markdown editor: source <textarea> on the right, rendered preview
// on the left, status bar (chars · words) at the bottom-right of the
// source pane. On every `input` event we re-parse the source via `marked`,
// sanitize the resulting HTML with DOMPurify, and inject it into the
// preview node.
//
// SECURITY: the rendered HTML is ALWAYS run through DOMPurify before
// `innerHTML` assignment. DOMPurify is the canonical HTML sanitizer for
// this exact use case — preventing XSS from user-supplied markdown.
// `marked` does NOT sanitize on its own.
//
// `marked` and `dompurify` are pinned via importmap (config/importmap.rb).
// They load via dynamic import — if either fails the textarea remains
// usable; the preview stays at the SSR-rendered initial paint until the
// user reloads.
//
// Char count uses JavaScript's `String#length` (UTF-16 code units) which is
// close enough to the Ruby-side `body.chars.size` (codepoints) for ASCII
// markdown. Both ends format with `toLocaleString()` / `number_with_delimiter`.
export default class extends Controller {
  static targets = ["source", "preview", "charCount", "wordCount"]

  connect() {
    this._renderInitial()
    this._loadLibraries().catch((err) => {
      // eslint-disable-next-line no-console
      console.warn("[markdown-editor] library load failed", err)
    })
  }

  // Stimulus action — wired from the source textarea via `data-action`.
  onInput() {
    this._updateCounts()
    this._renderPreview()
  }

  _renderInitial() {
    if (this.hasSourceTarget) this._updateCounts()
  }

  async _loadLibraries() {
    const [{ marked }, dompurifyModule] = await Promise.all([
      import("marked"),
      import("dompurify")
    ])
    this._marked = marked
    // DOMPurify ships with a default export; jsDelivr ESM bundle exposes it.
    this._purify = dompurifyModule.default || dompurifyModule
    this._renderPreview()
  }

  _renderPreview() {
    if (!this._marked || !this._purify) return
    if (!this.hasSourceTarget || !this.hasPreviewTarget) return

    const raw = this.sourceTarget.value
    let html
    try {
      html = this._marked.parse(raw, { breaks: true, gfm: true })
    } catch (err) {
      // eslint-disable-next-line no-console
      console.warn("[markdown-editor] marked.parse failed", err)
      return
    }
    // DOMPurify sanitizes — guards against XSS from markdown HTML embeds.
    const clean = this._purify.sanitize(html)
    this.previewTarget.innerHTML = clean // sanitized above
  }

  _updateCounts() {
    if (!this.hasSourceTarget) return
    const value = this.sourceTarget.value || ""
    const chars = value.length
    const words = (value.match(/\S+/g) || []).length

    if (this.hasCharCountTarget) {
      this.charCountTarget.textContent = chars.toLocaleString()
    }
    if (this.hasWordCountTarget) {
      this.wordCountTarget.textContent = words.toLocaleString()
    }
  }
}
