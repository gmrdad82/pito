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
// `data-current="yes"` attribute baked on each row checkbox in the
// template (only the row whose session id matches the current
// session carries `yes`). The warning line is hidden unless at
// least one checked row is `yes`.
//
// Markup contract:
//
//   <fieldset data-controller="sessions-bulk-revoke">
//     <a data-sessions-bulk-revoke-target="link"
//        class="bracketed-muted">[revoke]</a>
//     <table>
//       <thead>
//         <tr>
//           <th>
//             <input type="checkbox"
//                    data-sessions-bulk-revoke-target="headerCheckbox"
//                    data-action="change->sessions-bulk-revoke#toggleAll">
//           </th>
//           …
//         </tr>
//       </thead>
//       <tbody>
//         <tr>
//           <td>
//             <input type="checkbox"
//                    value="<session.id>"
//                    data-current="yes|no"
//                    data-sessions-bulk-revoke-target="checkbox"
//                    data-action="change->sessions-bulk-revoke#toggle">
//           </td>
//           …
//         </tr>
//       </tbody>
//     </table>
//     <dialog data-sessions-bulk-revoke-target="modal" …>
//       <div data-sessions-bulk-revoke-target="modalTitle">…</div>
//       <div data-sessions-bulk-revoke-target="modalWarning" hidden>…</div>
//       <form data-sessions-bulk-revoke-target="modalForm"
//             data-action="submit->sessions-bulk-revoke#refreshCsrf"
//             action="…PLACEHOLDER…">
//         <input type="hidden" name="authenticity_token" value="…">
//         …
//       </form>
//     </dialog>
//   </fieldset>
export default class extends Controller {
  static targets = [
    "link", "headerCheckbox", "checkbox",
    "modal", "modalTitle", "modalWarning", "modalForm"
  ]

  connect() {
    this.update()
  }

  toggle() {
    this.update()
  }

  toggleAll() {
    const checked = this.headerCheckboxTarget.checked
    this.checkboxTargets.forEach(cb => {
      if (!cb.disabled) cb.checked = checked
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
      const total = this.checkboxTargets.filter(cb => !cb.disabled).length
      this.headerCheckboxTarget.checked = count > 0 && count === total
      this.headerCheckboxTarget.indeterminate = count > 0 && count < total
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

  get selectedIds() {
    return this.checkboxTargets
      .filter(cb => cb.checked && !cb.disabled)
      .map(cb => cb.value)
  }

  get currentSessionInSelection() {
    return this.checkboxTargets
      .filter(cb => cb.checked && !cb.disabled)
      .some(cb => cb.dataset.current === "yes")
  }
}
