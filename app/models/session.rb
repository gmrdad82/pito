# frozen_string_literal: true

# Server-side session row. The cookie holds an opaque plaintext token
# whose `HMAC-SHA256` digest lives in `token_digest`. P14 rebuilds the
# auth flow on top of this row.
class Session < ApplicationRecord
  ACTIVITY_DEBOUNCE = 5.minutes

  attribute :state, :integer
  enum :state,
       { active: 0, expired: 1, revoked: 2 },
       prefix: :state

  validates :token_digest, presence: true, uniqueness: true

  scope :active_sessions, -> { state_active.where(revoked_at: nil) }

  def revoked?
    revoked_at.present?
  end

  def touch_activity!
    return if last_activity_at.present? && last_activity_at >= ACTIVITY_DEBOUNCE.ago

    update_columns(last_activity_at: Time.current)
  end

  def revoke!
    return if revoked?

    update_columns(revoked_at: Time.current, state: self.class.states[:revoked])
  end
end
