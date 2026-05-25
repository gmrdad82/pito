import { Controller } from "@hotwired/stimulus"

/**
 * pito-auth-dialog — handles the TOTP / backup-code toggle on the
 * auth dialog overlay (Pito::AuthDialogComponent).
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
 * Note: each code field is now managed by the unified `tui-totp-code`
 * Stimulus controller. This controller focuses the first cell of the backup
 * field directly, and clears cells via the tui-totp-code controller's targets.
 *
 * Z3-redesign (2026-05-25) — migrated from TotpCodeInputComponent +
 * BackupCodeInputComponent to unified Tui::TotpCodeComponent.
 *
 * @contract see app/components/pito/auth_dialog_component.html.erb
 */
export default class extends Controller {
  static targets = ["totpField", "backupField", "toggleBtn"]

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
      this.backupFieldTarget.querySelectorAll("[data-tui-totp-code-target='char']").forEach(cell => {
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
