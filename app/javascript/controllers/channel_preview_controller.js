import { Controller } from "@hotwired/stimulus"

// Phase 7.5 §11d — Channel multi-layout preview controller.
//
// Two responsibilities, both bound to the same controller scope (the
// wide-modal dialog wrapping the component):
//
//   1. Top-nav toggle. `[desktop]`, `[mobile]`, `[tv]` bracketed
//      links carry `data-action="click->channel-preview#selectLayout"`
//      and `data-layout="<name>"`. The handler flips the `.active`
//      class on the matching panel and removes it from the others,
//      then mirrors the choice into the top-nav links so the
//      active-style on the chosen one is correct.
//
//   2. Form-input listener. Form fields tagged with
//      `data-action="input->channel-preview#updatePreview"` debounce
//      300ms (configurable via `debounceMsValue`), then issue a
//      Turbo-Stream `GET /channels/:id/preview?...` carrying the
//      dirty subset. The server re-renders the component and
//      replaces `#channel-preview` in-place.
//
// NO `confirm()` / `alert()` / `prompt()` — CLAUDE.md hard rule.
export default class extends Controller {
  static values = {
    url: String,
    debounceMs: { type: Number, default: 300 }
  }
  static targets = ["panel", "navLink", "frame"]

  connect() {
    this._timer = null
    // Snapshot the form element the controller is mounted on so the
    // `input` listener can read every editable field's value at
    // fire-time without re-querying the DOM scope.
    this._form = this.element.querySelector("form") || this.element.closest("form")
  }

  disconnect() {
    if (this._timer) {
      clearTimeout(this._timer)
      this._timer = null
    }
  }

  selectLayout(event) {
    if (event) event.preventDefault()
    const trigger = event.currentTarget
    const next = trigger && trigger.dataset ? trigger.dataset.layout : null
    if (!next) return

    this.panelTargets.forEach((panel) => {
      const isActive = panel.dataset.layout === next
      panel.classList.toggle("active", isActive)
      if (isActive) {
        panel.removeAttribute("hidden")
      } else {
        panel.setAttribute("hidden", "")
      }
    })

    if (this.hasNavLinkTarget) {
      this.navLinkTargets.forEach((link) => {
        const isActive = link.dataset.layout === next
        link.classList.toggle("preview-nav-active", isActive)
      })
    }

    if (this.hasFrameTarget) {
      this.frameTarget.dataset.activeLayout = next
    }
  }

  updatePreview() {
    if (this._timer) clearTimeout(this._timer)
    this._timer = setTimeout(() => this._fire(), this.debounceMsValue)
  }

  _fire() {
    if (!this.hasUrlValue) return

    const url = new URL(this.urlValue, window.location.origin)
    const params = this._collectParams()
    Object.keys(params).forEach((k) => {
      url.searchParams.set(k, params[k])
    })

    // Carry the currently-active layout through to the server render
    // so the streamed replacement keeps the user on the panel they
    // were watching — otherwise the server would reset to `desktop`
    // on every keystroke.
    if (this.hasFrameTarget && this.frameTarget.dataset.activeLayout) {
      url.searchParams.set("active_layout", this.frameTarget.dataset.activeLayout)
    }

    fetch(url.toString(), {
      headers: { "Accept": "text/vnd.turbo-stream.html" },
      credentials: "same-origin"
    })
      .then((response) => response.text())
      .then((html) => {
        if (window.Turbo && typeof window.Turbo.renderStreamMessage === "function") {
          window.Turbo.renderStreamMessage(html)
        }
      })
      .catch(() => {
        // Silent failure — the modal stays on the last-rendered
        // preview. No alert / no console-toast.
      })
  }

  // Walks every input the host form exposes through
  // `data-channel-preview-field-param` and collects its current
  // value into a plain object keyed by the param name. Inputs
  // without that data attribute are skipped.
  _collectParams() {
    const out = {}
    if (!this._form) return out

    const fields = this._form.querySelectorAll("[data-channel-preview-field-param]")
    fields.forEach((field) => {
      const name = field.dataset.channelPreviewFieldParam
      if (!name) return
      out[name] = field.value || ""
    })
    return out
  }
}
