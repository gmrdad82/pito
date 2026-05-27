# frozen_string_literal: true

# Single-use TOTP backup code. The row stores only the BCrypt digest;
# the plaintext is shown to the owner exactly once at enrollment.
class TotpBackupCode < ApplicationRecord
  validates :code_digest, presence: true, uniqueness: true

  scope :unused, -> { where(used_at: nil) }
  scope :used,   -> { where.not(used_at: nil) }

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
