# Phase 7 — Step A (7a-google-oauth-and-identity.md) — encrypted
# Google OAuth identity record.
#
# One row per (User, Google account) pair. Beta UI in 7C enforces 1
# identity per user; the schema permits N (no unique on `user_id`)
# so Theta multi-account support is a future UI change, not a
# migration.
#
# Phase 8 — tenant drop. `google_subject_id` is now globally unique
# (the upstream Google ID is unique on its own).
#
# Token columns are encrypted at the model layer with Active Record
# Encryption. The columns are `text` on the schema side because ARE
# writes a JSON-encoded ciphertext blob. Deterministic encryption is
# NOT used — tokens are not searchable.
class GoogleIdentity < ApplicationRecord
  belongs_to :user

  has_many :channels,
           class_name: "Channel",
           foreign_key: :oauth_identity_id,
           dependent: :nullify,
           inverse_of: :oauth_identity

  # Phase 7 Path A2 — videos may also be tagged with the identity that
  # synced them. Same nullify behavior so the Video row outlives the
  # identity it was synced through.
  has_many :videos,
           class_name: "Video",
           foreign_key: :oauth_identity_id,
           dependent: :nullify

  # Audit-row trail outlives the identity (decision 7C-disconnect-
  # lifecycle: destroy the row; the historical "this user once
  # authorized" trail lives in `youtube_api_calls`, not on the
  # identity row). Nullify rather than destroy so the rows stay
  # for Phase 11 observability.
  has_many :youtube_api_calls,
           class_name: "YoutubeApiCall",
           foreign_key: :google_identity_id,
           dependent: :nullify,
           inverse_of: :google_identity

  encrypts :access_token
  encrypts :refresh_token

  validates :google_subject_id, presence: true,
            uniqueness: { case_sensitive: true }
  validates :email, presence: true
  validates :access_token, presence: true
  validates :expires_at, presence: true
  validates :last_authorized_at, presence: true
  validate :scopes_must_be_array

  before_validation :default_scopes_to_empty_array

  # Returns true when the access token is expired or about to expire
  # within `skew`. Default skew is 60 seconds — enough to survive a
  # single round-trip without a 401 storm.
  def access_token_expired?(skew: 60.seconds)
    return true if expires_at.nil?

    expires_at <= Time.current + skew
  end

  # Convenience reader — returns the column directly. The 7C banner
  # check is `identity.needs_reauth?`.
  def needs_reauth?
    !!needs_reauth
  end

  # Membership in the granted scopes array.
  def has_scope?(scope)
    Array(scopes).include?(scope.to_s)
  end

  # Space-joined string in the format Google's authorization endpoint
  # expects (e.g. for re-grant requests).
  def scope_string
    Array(scopes).join(" ")
  end

  private

  def default_scopes_to_empty_array
    self.scopes ||= []
  end

  def scopes_must_be_array
    return if scopes.is_a?(Array)

    errors.add(:scopes, "must be an Array")
  end
end
