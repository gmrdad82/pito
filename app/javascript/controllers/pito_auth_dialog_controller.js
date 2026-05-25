import { Controller } from "@hotwired/stimulus"

/**
 * pito-auth-dialog — handles the TOTP / backup-code toggle + CTRL+j/k flat
 * navigation on the auth dialog overlay (Pito::AuthDialogComponent).
 *
 * The dialog renders:
 *   - totpField   — Tui::TotpCodeComponent (mode=digits, shown by default)
 *   - backupField — Tui::TotpCodeComponent (mode=backup, hidden by default)
 *
 * The `[ use backup code ]` / `[ use TOTP code ]` toggle button swaps
 * visibility between them, clears the inactive field, and updates its own
 * label text (from data attrs: data-use-backup-label / data-use-totp-label).
 *
 * Targets:
 *   totpField   — the Tui::TotpCodeComponent wrapper for the 6-digit code
 *   backupField — the Tui::TotpCodeComponent wrapper for the 8-char backup code
 *   toggleBtn   — the toggle <button> whose label swaps between modes
 *
 * Actions:
 *   toggleBackup() — swap between TOTP and backup-code fields
 *
 * Keyboard nav (CTRL+j / CTRL+k):
 *   While the dialog is open, CTRL+j advances focus through the visible
 *   focusables (toggle → input cells → submit, wrap around), CTRL+k goes
 *   backwards. Plain j/k is not used — the code cells consume them as text.
 *   Listener attached on `document` in connect(), removed in disconnect().
 *
 * Z3-redesign (2026-05-25) — migrated from TotpCodeInputComponent +
 * BackupCodeInputComponent to unified Tui::TotpCodeComponent.
 * Keyboard nav (2026-05-25) — CTRL+j/k flat cycle through visible controls.
 *
 * @contract see app/components/pito/auth_dialog_component.html.erb
 */
export default class extends Controller {
  static targets = ["totpField", "backupField", "toggleBtn"]

  connect() {
    this._onKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this._onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
  }

  handleKeydown(event) {
    if (!event.ctrlKey) return
    if (event.key !== "j" && event.key !== "k") return
    event.preventDefault()
    if (event.key === "j") this.focusNext()
    else this.focusPrev()
  }

  // Ordered list of visible focusables in the dialog. Visibility is
  // determined by querying inputs/buttons that are not inside a `hidden`
  // ancestor — the inactive code field's wrapper is `hidden`, so its cells
  // drop out automatically when the mode flips.
  visibleFocusables() {
    const sel = "button, input[type='text']"
    return Array.from(this.element.querySelectorAll(sel)).filter((el) => {
      if (el.disabled) return false
      // offsetParent is null when the element (or any ancestor) is hidden
      // via display:none or the `hidden` attribute.
      return el.offsetParent !== null
    })
  }

  focusNext() {
    const list = this.visibleFocusables()
    if (list.length === 0) return
    const idx = list.indexOf(document.activeElement)
    const next = list[(idx + 1) % list.length] || list[0]
    this.focusAndMark(next)
  }

  focusPrev() {
    const list = this.visibleFocusables()
    if (list.length === 0) return
    const idx = list.indexOf(document.activeElement)
    const prev = list[(idx - 1 + list.length) % list.length]
    this.focusAndMark(prev)
  }

  // Apply the canonical focus-tint cursor by setting
  // `data-tui-focusable-focused="yes"` + `data-tui-focusable-style="action"`
  // on the focused element when it's a button. The existing CSS rule
  // (`[data-tui-focusable-focused][data-tui-focusable-style="action"]`)
  // paints the Solid variant D tint. Inputs rely on their own `:focus`
  // styling (.totp-modal-box bottom-border-accent) per the input contract.
  // Clears prior marks from the dialog so only one cursor at a time.
  focusAndMark(el) {
    this.element.querySelectorAll('[data-tui-focusable-focused="yes"]').forEach((prev) => {
      prev.removeAttribute("data-tui-focusable-focused")
      // only strip our injected style — leave any author-supplied style alone
      if (prev.dataset.tuiFocusableInjected === "yes") {
        prev.removeAttribute("data-tui-focusable-style")
        delete prev.dataset.tuiFocusableInjected
      }
    })
    if (el.tagName === "BUTTON" && !el.hasAttribute("data-tui-focusable-style")) {
      el.setAttribute("data-tui-focusable-style", "action")
      el.dataset.tuiFocusableInjected = "yes"
    }
    if (el.tagName === "BUTTON") {
      el.setAttribute("data-tui-focusable-focused", "yes")
    }
    el.focus()
    if (el.select) el.select()
  }

  toggleBackup() {
    const backupHidden = this.backupFieldTarget.hidden

    if (backupHidden) {
      // Switch to backup code mode
      this.backupFieldTarget.hidden = false
      this.totpFieldTarget.hidden = true
      // Focus the first char cell inside the backup field
      const firstChar = this.backupFieldTarget.querySelector("[data-tui-totp-code-target='char']")
      if (firstChar) firstChar.focus()
      // Swap toggle label to "[ use TOTP code ]"
      if (this.hasToggleBtnTarget) {
        const label = this.toggleBtnTarget.getAttribute("data-use-totp-label")
        this.toggleBtnTarget.querySelector(".bl").textContent = label
      }
    } else {
      // Switch back to TOTP mode — clear backup cells
      this.backupFieldTarget.hidden = true
      this.totpFieldTarget.hidden = false
      // Clear all char cells in the backup field
      this.backupFieldTarget.querySelectorAll("[data-tui-totp-code-target='char']").forEach((cell) => {
        cell.value = ""
      })
      // Swap toggle label back to "[ use backup code ]"
      if (this.hasToggleBtnTarget) {
        const label = this.toggleBtnTarget.getAttribute("data-use-backup-label")
        this.toggleBtnTarget.querySelector(".bl").textContent = label
      }
      // Focus the first digit box after returning to TOTP mode
      const firstDigit = this.totpFieldTarget.querySelector("[data-tui-totp-code-target='digit']")
      if (firstDigit) firstDigit.focus()
    }
  }
}
