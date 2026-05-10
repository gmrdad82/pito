# Phase 9 — Login-with-Google Drop + GoogleIdentity → YoutubeConnection
# rename (ADR 0006). The model's role narrowed to "an OAuth grant that
# gives pito access to one or more YouTube channels." See
# `docs/plans/beta/09-login-with-google-drop/specs/01-google-identity-rename.md`.
#
# One row per (User, Google account) pair. The schema permits a User to
# hold multiple connections — `User has_many :youtube_connections` — so a
# single pito account holder can connect multiple Google accounts (one
# grant per account; each grant covers one or more channels).
#
# `google_subject_id` is install-wide unique (the upstream Google ID is
# globally unique on its own — Phase 8 dropped the tenant-scoped
# composite).
#
# Token columns are encrypted at the model layer with Active Record
# Encryption. The columns are `text` on the schema side because ARE
# writes a JSON-encoded ciphertext blob. Deterministic encryption is
# NOT used — tokens are not searchable.
class YoutubeConnection < ApplicationRecord
  belongs_to :user

  # Phase 7C disconnect-lifecycle decision (preserved): channels outlive
  # the connection. Destroying the connection nullifies the FK on
  # surviving channels so the user can re-connect later without losing
  # their star / saved-view state for those channels.
  has_many :channels,
           foreign_key: :youtube_connection_id,
           dependent: :nullify,
           inverse_of: :youtube_connection

  # Phase 7 Path A2 — videos may also be tagged with the connection that
  # synced them. Same nullify behavior so the Video row outlives the
  # connection it was synced through.
  has_many :videos,
           foreign_key: :youtube_connection_id,
           dependent: :nullify

  # Audit-row trail outlives the connection (decision 7C-disconnect-
  # lifecycle: destroy the connection row itself; the historical
  # "this user once authorized" trail lives in `youtube_api_calls`,
  # not on the connection row). Nullify rather than destroy so the
  # rows stay for Phase 11 observability.
  has_many :youtube_api_calls,
           foreign_key: :youtube_connection_id,
           dependent: :nullify,
           inverse_of: :youtube_connection

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
  # check is `connection.needs_reauth?`.
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
