# Phase 25 — 01e. TOTP backup codes table.
#
# Ten single-use codes per enrollment (LD locked: 10 codes, 28-char safe
# alphabet, BCrypt-hashed at rest, single-use). The plaintext is shown
# ONCE on the enrollment one-shot view; we store only the bcrypt digest.
#
# `used_at` is `NULL` for unused codes and stamped on consumption. The
# row stays after consumption so the audit trail records "this code
# was used at this timestamp" — purge on disable destroys the rows
# explicitly (see `Auth::TotpDisabler`).
#
# Indexes: `(user_id)` for the unused-count query and the row-lookup on
# consumption; the `code_digest` column is intentionally NOT indexed
# because BCrypt digests vary by salt and we compare by iterating
# `unused` rows on consume (10 BCrypt compares per attempt is fast
# enough at the human-rate of login attempts).
class CreateTotpBackupCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :totp_backup_codes do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :code_digest, null: false
      t.datetime :used_at

      t.timestamps
    end

    add_index :totp_backup_codes, :used_at
  end
end
