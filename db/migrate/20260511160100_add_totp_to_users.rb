# Phase 25 — 01e. TOTP 2FA columns on users.
#
# `totp_seed_encrypted` carries the base32 TOTP seed encrypted at rest
# via `ActiveRecord::Encryption` (LD-9). Storing as `:text` because
# `encrypts` envelope-encrypts to a JSON-ish blob that comfortably
# exceeds the 32-char plaintext seed.
#
# `totp_enabled_at` is set when the user successfully confirms a freshly
# generated seed with a valid 6-digit code from their authenticator app.
# `totp_disabled_at` is stamped on the disable path so the audit trail
# can answer "was TOTP ever on" without scraping `AuthAuditLog`.
#
# The two `_at` timestamps live alongside the encrypted seed rather than
# in a side table because they're rare reads, never indexed, and always
# fetched together with the user's auth state.
class AddTotpToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :totp_seed_encrypted, :text
    add_column :users, :totp_enabled_at, :datetime
    add_column :users, :totp_disabled_at, :datetime
  end
end
