import { Controller } from "@hotwired/stimulus"

// 2026-05-16 (sessions revamp v2) — dedicated bulk-revoke header for
// the inline sessions table in the `/settings` Security pane. The
// shared `bulk_select_controller` is not reused here because its
// `revokeAction` branch hard-codes `data-turbo-frame="_top"` on the
// constructed link, which is unnecessary on this surface (there is no
// enclosing Turbo Frame on `/settings`) and confusing to read at the
// call site.
//
// 2026-05-16 (sessions revamp v3 — modal-confirm) — the standalone
// `/settings/sessions/revokes/:ids` action-screen confirmation page
// is GONE. The `[revoke N]` link no longer navigates; clicking it
// opens an in-page `<dialog>` confirm modal (mounted at the bottom
// of `_security_pane.html.erb`). This controller populates the
// modal's title text, conditional current-session warning, and form
// `action` attribute at click time based on the current selection.
//
// 2026-05-20 (Beta 4 F3-C) — row + header checkboxes now render via
// `Tui::CheckboxComponent` (form mode). The primitive does not accept
// `data:` passthrough by design, so the stimulus targets +
// `data-current` host element move to a `<span class=
// "sessions-table__checkbox">` wrapper that encloses the component
// render. The controller dereferences each wrapper to its inner
// `<input type="checkbox">` (excluding the form-mode hidden friend)
// for `.checked` / `.value` / `.disabled` state. The wrapper carries
// `data-value="<id>"` for selection-id lookup so we don't have to
// reach into the input's value attr.
//
// Behaviour:
//
//   - `[ revoke ]` is rendered idle (muted, non-clickable) when no
//     checkboxes are ticked.
//   - As soon as one or more checkboxes flip on, the same surface
//     becomes a live `[ revoke <N> ]` link. Clicking it populates
//     the modal (title / warning / form action) and `showModal()`s
//     the dialog. The dialog form POSTs to
//     `/settings/sessions/revokes/<ids>` with `confirm=yes`.
//   - The header checkbox toggles every row checkbox, and the row
//     checkboxes drive header state (checked / indeterminate /
//     unchecked).
//
// "Current session in selection" is detected client-side via the
// `data-current="yes"` attribute baked on each row's wrapper span in
// the template (only the row whose session id matches the current
// session carries `yes`). The warning line is hidden unless at
// least one checked row is `yes`.
// 2026-05-20 (FB-14) — the `[revoke]` action no longer lives in a
// row above the table. It lives INSIDE the `<thead>` row.
//
// 2026-05-20 (FB-116) — header swap is now ROW-level, not inner-
// content-level: the `<thead>` carries two `<tr>` siblings —
// `defaultHeader` (per-column `<th>` cells aligned with body data)
// and `actionHeader` (checkbox + `<th colspan>` action bar). On any
// selection change `update()` flips the `hidden` attribute on
// whichever row is inactive. This restores column→data alignment
// (per FB-108) that the previous single-row colspan approach broke.
// TUI parity: Ratatui's `Row::new` accepts dynamic content, so the
// Rust client performs the same conditional header-row swap when
// selection state flips.
export default class extends Controller {
  static targets = [
    "link", "headerCheckbox", "checkbox",
    "defaultHeader", "actionHeader", "actions", "counter",
    "modal", "modalTitle", "modalWarning", "modalForm"
  ]

  connect() {
    this.update()
  }

  toggle() {
    this.update()
  }

  toggleAll() {
    const checked = this._inputFor(this.headerCheckboxTarget)?.checked || false
    this.checkboxTargets.forEach(wrapper => {
      const input = this._inputFor(wrapper)
      if (input && !input.disabled) input.checked = checked
    })
    this.update()
  }

  // Click handler on the `[revoke N]` link. Populates the modal with
  // the current selection, then opens it. Pre-rendered modal markup
  // means the CSRF token in the form is bound to the current session
  // and stays valid for the submit.
  open(event) {
    if (event) event.preventDefault()
    const ids = this.selectedIds
    if (ids.length === 0) return
    if (!this.hasModalTarget) return

    this.populateModal(ids)
    this.modalTarget.showModal()
  }

  populateModal(ids) {
    const count = ids.length
    const label = count === 1 ? "session" : "sessions"

    if (this.hasModalTitleTarget) {
      this.modalTitleTarget.textContent = `revoke ${count} ${label}?`
    }

    if (this.hasModalWarningTarget) {
      this.modalWarningTarget.hidden = !this.currentSessionInSelection
    }

    if (this.hasModalFormTarget) {
      // The form's `action` attribute carries a literal `0` ids
      // segment at render time (route constraint `[0-9,]+` requires
      // a digit; `0` is filtered out server-side by `parse_ids`).
      // Swap the trailing segment with the joined id list.
      const form = this.modalFormTarget
      const current = form.getAttribute("action") || ""
      const next = current.replace(/\/revokes\/[\d,]+\b/, `/revokes/${ids.join(",")}`)
      form.setAttribute("action", next)
    }
  }

  update() {
    const ids = this.selectedIds
    const count = ids.length

    if (this.hasHeaderCheckboxTarget) {
      const headerInput = this._inputFor(this.headerCheckboxTarget)
      const enabled = this.checkboxTargets
        .map(w => this._inputFor(w))
        .filter(input => input && !input.disabled)
      const total = enabled.length
      if (headerInput) {
        headerInput.checked = count > 0 && count === total
        headerInput.indeterminate = count > 0 && count < total
      }
    }

    // FB-116: header row swap — `defaultHeader` (per-column <th>
    // cells) when nothing is selected; `actionHeader` (checkbox +
    // colspan action bar) when ≥1 row is checked. Both rows live
    // in the DOM under `<thead>`; we flip `hidden` on the inactive
    // one. Per-column cells in `defaultHeader` keep header labels
    // aligned over their body columns.
    if (this.hasDefaultHeaderTarget && this.hasActionHeaderTarget) {
      const selectionMode = count > 0
      this.defaultHeaderTarget.hidden = selectionMode
      this.actionHeaderTarget.hidden = !selectionMode
    }
    if (this.hasCounterTarget) {
      const label = count === 1 ? "session" : "sessions"
      this.counterTarget.textContent = `${count} ${label} selected`
    }

    if (!this.hasLinkTarget) return

    const link = this.linkTarget
    if (count === 0) {
      link.removeAttribute("href")
      link.removeAttribute("data-action")
      link.classList.remove("bracketed", "text-danger")
      link.classList.add("bracketed-muted")
      link.textContent = "[revoke]"
    } else {
      // No `href` — clicking the link opens the modal, not a
      // navigation. We set `href="#"` for keyboard / accessibility
      // affordance and `preventDefault()` in `#open` swallows the
      // synthetic navigation.
      link.setAttribute("href", "#")
      link.setAttribute("data-action", "click->sessions-bulk-revoke#open")
      link.classList.remove("bracketed-muted")
      link.classList.add("bracketed", "text-danger")
      // Bracket characters live in literal text nodes so a `<span class="bl">`
      // wrapper around the inner label keeps the bracket → label →
      // bracket structure consistent with `BracketedLinkComponent`.
      link.replaceChildren()
      link.appendChild(document.createTextNode("["))
      const span = document.createElement("span")
      span.className = "bl"
      span.textContent = `revoke ${count}`
      link.appendChild(span)
      link.appendChild(document.createTextNode("]"))
    }
  }

  // `submit` action on the modal form. Copies the live
  // `<meta name="csrf-token">` value into the form's hidden
  // `authenticity_token` input immediately before the native POST
  // fires. The hidden field is auto-rendered by `form_with`, so it
  // exists at page-load time and the token there is bound to the
  // current session. This handler is belt-and-suspenders: if the
  // baked token went stale (session rotation between render and
  // confirm-click), the meta tag — re-emitted on every request —
  // carries the page's freshest valid token, and the request always
  // sends that one.
  //
  // No `preventDefault()`: the native submit proceeds with the
  // updated hidden field. If either the input or the meta tag is
  // missing (defensive), the handler is a no-op and the native
  // submit still runs with whatever token is already in the field.
  refreshCsrf(event) {
    const form = event.currentTarget
    if (!form) return
    const tokenInput = form.querySelector('input[name="authenticity_token"]')
    if (!tokenInput) return
    const meta = document.querySelector('meta[name="csrf-token"]')
    if (!meta) return
    const fresh = meta.getAttribute("content")
    if (fresh && fresh.length > 0) {
      tokenInput.value = fresh
    }
  }

  // Pull the real `<input type="checkbox">` out of a wrapper span.
  // The Tui::CheckboxComponent form mode renders a hidden friend
  // (`<input type="hidden">`) alongside the visible checkbox — skip
  // the hidden friend.
  _inputFor(wrapper) {
    if (!wrapper) return null
    return wrapper.querySelector('input[type="checkbox"]')
  }

  get selectedIds() {
    return this.checkboxTargets
      .filter(wrapper => {
        const input = this._inputFor(wrapper)
        return input && input.checked && !input.disabled
      })
      .map(wrapper => wrapper.dataset.value || this._inputFor(wrapper).value)
  }

  get currentSessionInSelection() {
    return this.checkboxTargets
      .filter(wrapper => {
        const input = this._inputFor(wrapper)
        return input && input.checked && !input.disabled
      })
      .some(wrapper => wrapper.dataset.current === "yes")
  }
}
