import { Controller } from "@hotwired/stimulus"

// Phase 26 — 01d. Layout-level webhook help modal.
//
// Mirrors the `notifications-modal` pattern: a `<dialog>` lives at the
// page bottom (`shared/_webhook_help_modal`) hosting a Turbo Frame
// (`webhook_help_modal_frame`). The Slack + Discord pane `[help]`
// links carry `data-action="click->webhook-help-modal#open"` plus a
// `data-webhook-help-modal-provider-param` value (`"slack"` or
// `"discord"`); on click the controller:
//
//   1. `event.preventDefault()` so the link does not navigate.
//   2. Sets the frame's `src` to `/settings/webhooks/help/<provider>`.
//      Turbo fetches the URL and swaps the matching `<turbo-frame>`
//      from the response into the dialog.
//   3. `dialog.showModal()`.
//
// Close paths:
//   - Esc (native `<dialog>` Escape handling + an explicit keydown
//     guard so embedded forms can't swallow the event).
//   - Backdrop click — `clickOutside`.
//   - `[close]` bracketed link inside the modal — `close`.
//
// NO JS `confirm()` / `alert()` / `prompt()` / `data-turbo-confirm`
// (CLAUDE.md hard rule).
export default class extends Controller {
  static values = {
    dialogId: { type: String, default: "webhook-help-modal" },
    frameId:  { type: String, default: "webhook_help_modal_frame" },
    urlTemplate: { type: String, default: "/settings/webhooks/help/" },
  }

  open(event) {
    if (event) event.preventDefault()

    const dialog = this._dialog()
    const frame  = this._frame()
    if (!dialog || !frame) return

    // The clicked link carries the provider as a Stimulus param
    // (`data-webhook-help-modal-provider-param`). Validate against the
    // server's allow-list before issuing the fetch so a malformed
    // attribute can't make the modal flash a 404 fragment.
    const provider = event && event.params ? event.params.provider : null
    if (provider !== "slack" && provider !== "discord") return

    frame.setAttribute("src", `${this.urlTemplateValue}${provider}`)

    // FB-103 (2026-05-20). Rewrite the dialog frame's top-border title
    // (`.tui-dialog-frame__title-left`) to the per-brand string. The
    // server-rendered initial text is the generic `webhook help`
    // fallback; the brand-specific strings come from data attributes
    // (`data-webhook-help-title-slack` / `data-webhook-help-title-discord`)
    // populated server-side from the `settings.webhooks.help.brand_title`
    // i18n key so the JS layer never invents copy. The in-body `<h1>`
    // (previously "Slack webhook setup" / "Discord webhook setup") is
    // gone from the markdown sources — the border title is now the
    // single canonical title surface for the dialog.
    const titleEl = dialog.querySelector("[data-webhook-help-title]")
    if (titleEl) {
      const brandTitle = dialog.getAttribute(`data-webhook-help-title-${provider}`)
      if (brandTitle) titleEl.textContent = brandTitle
    }

    if (typeof dialog.showModal === "function" && !dialog.open) {
      dialog.showModal()
    }
  }

  close(event) {
    if (event) event.preventDefault()

    const dialog = this._dialog()
    if (dialog && typeof dialog.close === "function" && dialog.open) {
      dialog.close()
    }

    const frame = this._frame()
    if (frame) {
      frame.removeAttribute("src")
      frame.replaceChildren()
    }
  }

  clickOutside(event) {
    const dialog = this._dialog()
    if (dialog && event.target === dialog) {
      this.close(event)
    }
  }

  keydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close(event)
    }
  }

  _dialog() {
    return document.getElementById(this.dialogIdValue)
  }

  _frame() {
    return document.getElementById(this.frameIdValue)
  }
}
