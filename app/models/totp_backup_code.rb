# Phase 25 — 01e. Single-use TOTP backup code.
#
# Ten codes are minted at enrollment by `Auth::TotpEnroller` (and on
# regenerate by `Auth::BackupCodeRegenerator`). Each row stores ONLY
# the BCrypt digest — the plaintext is shown to the user exactly once,
# on the one-shot enrollment view.
#
# Consumption (login-flow) flips `used_at` and leaves the row in place
# so the audit trail records "this code was used at this timestamp".
# Disabling 2FA destroys every row outright via `Auth::TotpDisabler`.
#
# The code alphabet is the safe 28-char base32 subset (no `0` / `O` /
# `1` / `I` / `L` / `B` / `8`); the alphabet is owned by the enroller
# service, not the model, because the model only ever sees the digest.
class TotpBackupCode < ApplicationRecord
  belongs_to :user

  validates :code_digest, presence: true

  scope :unused, -> { where(used_at: nil) }
  scope :used,   -> { where.not(used_at: nil) }

  # Constant-time compare against the stored BCrypt digest. Iterating
  # the `unused` scope and asking each row `matches?(plaintext)` is the
  # documented consumption shape; BCrypt's `==` is constant-time-ish
  # per the gem's notes.
  def matches?(plaintext)
    return false if plaintext.blank?
    BCrypt::Password.new(code_digest) == plaintext.to_s
  rescue BCrypt::Errors::InvalidHash
    false
  end

  def used?
    used_at.present?
  end
end
