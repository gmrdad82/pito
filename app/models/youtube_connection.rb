# frozen_string_literal: true

# OAuth grant that lets pito reach one or more YouTube channels. Token
# columns are encrypted at rest via Active Record Encryption.
class YoutubeConnection < ApplicationRecord
  has_many :channels,
           foreign_key: :youtube_connection_id,
           dependent: :nullify,
           inverse_of: :youtube_connection

  encrypts :access_token
  encrypts :refresh_token

  validates :google_subject_id, presence: true,
                                uniqueness: { case_sensitive: true }
  validates :email,              presence: true
  validates :access_token,       presence: true
  validates :expires_at,         presence: true
  validates :last_authorized_at, presence: true
  validate  :scopes_must_be_array

  before_validation :default_scopes_to_empty_array

  scope :active, -> { where(needs_reauth: false) }

  def access_token_expired?(skew: 60.seconds)
    return true if expires_at.nil?

    expires_at <= Time.current + skew
  end

  def has_scope?(scope)
    Array(scopes).include?(scope.to_s)
  end

  def scope_string
    Array(scopes).join(" ")
  end

  # Flip the connection to needs-reauth AND surface the dedup'd reauth
  # Notification (which pings any configured webhook). The notification is
  # idempotent via the source's unread-dedup, so this is safe to call on every
  # 401 storm. The single entry point for "this grant is dead" across the live
  # sync / remote-write flows.
  def flag_needs_reauth!
    update_columns(needs_reauth: true)
    Pito::Notifications::Source::YoutubeReauth.report!(self)
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
