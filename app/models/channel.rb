# frozen_string_literal: true

class Channel < ApplicationRecord
  belongs_to :youtube_connection, optional: true, inverse_of: :channels
  has_many :videos, dependent: :destroy
  has_many :stats, as: :entity, dependent: :destroy

  # Locally-cached avatar (240x240 JPEG). We attach OUR copy during sync via
  # Channel::Avatar::Ingest instead of hotlinking yt3.ggpht.com (which 429s).
  has_one_attached :avatar

  # Display variant URL for the avatar, or nil when none is attached (the view
  # falls back to the placeholder). Rescues variant/processing errors.
  def avatar_variant_url
    return nil unless avatar.attached?

    avatar.variant(resize_to_limit: [ 240, 240 ])
  rescue StandardError
    nil
  end

  # Stat readers — sourced from the polymorphic `stats` table via the
  # `Pito::Stats` facade (P4). Return nil when no stat row exists.
  def subscriber_count
    Pito::Stats.get(self, :subscribers)
  end

  def view_count
    Pito::Stats.get(self, :views)
  end

  validates :youtube_channel_id,
            presence: true,
            uniqueness: { case_sensitive: true }

  # Returns the canonical at-prefixed handle exactly once, regardless of
  # whether the DB value already includes a leading "@".
  # e.g. "@foo" → "@foo", "foo" → "@foo", "@@oops" → "@oops"
  def at_handle
    "@#{handle.to_s.sub(/\A@+/, '')}"
  end
end
