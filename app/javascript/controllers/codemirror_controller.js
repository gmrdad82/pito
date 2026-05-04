import { Controller } from "@hotwired/stimulus"

// Phase 4 §9.5 — CodeMirror 6 in markdown mode.
//
// Targets a textarea. On connect, attempts to load CodeMirror 6 dynamically
// via importmap. If the import fails (the codemirror packages aren't pinned
// yet — vendoring is a separate Phase B follow-up), the controller falls
// back to the plain textarea so the form remains usable. On submit, the
// editor view is destroyed and the textarea retains the latest content.
//
// Plain markdown mode only — no preview pane, no language extensions.
// Styling honours design.md tokens via inline CSS variables.
export default class extends Controller {
  static targets = ["textarea"]

  connect() {
    this._mountFallbackTextarea()
    this._loadEditor().catch((err) => {
      // Quiet fallback — the textarea is already visible and usable.
      // eslint-disable-next-line no-console
      console.warn("[codemirror] editor load failed; falling back to textarea", err)
    })
  }

  disconnect() {
    if (this._editorView) {
      this._editorView.destroy()
      this._editorView = null
    }
  }

  // Mirror the textarea's current value to the underlying form field on
  // submit. Stimulus form-submit hook.
  sync() {
    if (!this._editorView) return
    const textarea = this._textareaEl()
    textarea.value = this._editorView.state.doc.toString()
  }

  _textareaEl() {
    return this.hasTextareaTarget ? this.textareaTarget : this.element.querySelector("textarea")
  }

  _mountFallbackTextarea() {
    const textarea = this._textareaEl()
    if (!textarea) return
    textarea.classList.add("codemirror-fallback")
    textarea.style.fontFamily = "var(--font-mono, ui-monospace)"
    textarea.style.fontSize = "13px"
    textarea.style.minHeight = "240px"
    textarea.style.width = "100%"
  }

  async _loadEditor() {
    const textarea = this._textareaEl()
    if (!textarea) return

    const [
      { EditorState },
      { EditorView, lineNumbers, highlightActiveLine, keymap },
      { defaultKeymap, history, historyKeymap },
      { markdown }
    ] = await Promise.all([
      import("@codemirror/state"),
      import("@codemirror/view"),
      import("@codemirror/commands"),
      import("@codemirror/lang-markdown")
    ])

    const view = new EditorView({
      state: EditorState.create({
        doc: textarea.value,
        extensions: [
          lineNumbers(),
          highlightActiveLine(),
          history(),
          markdown(),
          keymap.of([...defaultKeymap, ...historyKeymap]),
          EditorView.updateListener.of((u) => {
            if (u.docChanged) textarea.value = u.state.doc.toString()
          })
        ]
      }),
      parent: this.element
    })

    // Hide the fallback textarea once the editor mounted successfully.
    textarea.style.display = "none"
    this._editorView = view

    // Sync on form submit.
    const form = this.element.closest("form")
    if (form) form.addEventListener("submit", () => this.sync())
  }
}
