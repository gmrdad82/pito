# frozen_string_literal: true

# A Share record mints a public, unguessable URL for a single conversation Event.
# Re-sharing the same event (by event_id) is idempotent — find_or_create_by!(event:)
# returns the same Share (and thus the same /share/:uuid URL) every time.
#
# == URL
#   /share/:uuid  — unauthenticated; loaded by SharesController#show.
#   If the Share is absent/destroyed the controller renders a GONE (404) page.
#
# == Lifecycle
#   Created:  Pito::Share::UniversalActions `#<handle> share` → find_or_create_by!(event:)
#   Revoked:  RevokeShareJob destroys by event_id (async, idempotent).
class Share < ApplicationRecord
  belongs_to :conversation
  belongs_to :event

  before_validation :set_uuid, on: :create

  normalizes :uuid, with: ->(value) { value&.downcase }

  validates :uuid,     presence: true, uniqueness: { case_sensitive: true }
  validates :event_id, uniqueness: true

  def to_param
    uuid
  end

  private

  def set_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
