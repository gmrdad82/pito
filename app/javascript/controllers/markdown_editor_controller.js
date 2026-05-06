import { Controller } from "@hotwired/stimulus"

// Phase B post-commit (2026-05-04) — Note revamp.
//
// Live markdown editor: source <textarea> on the right, rendered preview
// on the left, status bar (words) at the bottom-right of the source
// pane. On every `input` event we re-parse the source via `marked`,
// sanitize the resulting HTML with DOMPurify, and inject it into the
// preview node. The same parsed-HTML output drives the live word count
// so it matches the SSR-side count produced by NoteHelper.word_count.
//
// SECURITY: the rendered HTML is ALWAYS run through DOMPurify before
// `innerHTML` assignment. DOMPurify is the canonical HTML sanitizer for
// this exact use case — preventing XSS from user-supplied markdown.
// `marked` does NOT sanitize on its own.
//
// `marked` and `dompurify` are pinned via importmap (config/importmap.rb).
// They load via dynamic import — if either fails the textarea remains
// usable; the preview stays at the SSR-rendered initial paint until the
// user reloads. Until `marked` is ready the live word count falls back
// to a whitespace tokenizer (close enough for the moment between page
// paint and the dynamic import resolving).
//
// 2026-05-06 — chars count removed (UI + DB). Word count is now
// markdown-aware: render to HTML, strip tags, tokenize `\p{L}+`. So
// `# Hi\nHow are you all doing?` reports 6 words; the `#` heading
// marker is consumed by `marked` and never reaches the tokenizer.
export default class extends Controller {
  static targets = ["source", "preview", "wordCount"]

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
    // Re-render once libraries land — both preview and counts now go
    // through the markdown pipeline so they match the SSR output.
    this._updateCounts()
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
    if (!this.hasSourceTarget || !this.hasWordCountTarget) return
    const value = this.sourceTarget.value || ""
    const words = this._countWords(value)
    this.wordCountTarget.textContent = words.toLocaleString()
  }

  // Markdown-aware word count. When `marked` is loaded we render to HTML,
  // strip tags, then tokenize Unicode word characters (`\p{L}` letters
  // plus `\p{N}` digits). When it isn't (initial paint, library failure),
  // fall back to a whitespace tokenizer so the count is close instead of
  // stuck at zero.
  _countWords(raw) {
    if (!raw) return 0
    if (this._marked) {
      let html
      try {
        html = this._marked.parse(raw, { breaks: true, gfm: true })
      } catch (err) {
        return (raw.match(/\S+/g) || []).length
      }
      const plain = html.replace(/<[^>]+>/g, " ")
      const tokens = plain.match(/[\p{L}\p{N}]+/gu) || []
      return tokens.length
    }
    return (raw.match(/\S+/g) || []).length
  }
}
