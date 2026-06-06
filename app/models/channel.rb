# frozen_string_literal: true

class Channel < ApplicationRecord
  belongs_to :youtube_connection, optional: true, inverse_of: :channels
  has_many :videos, dependent: :destroy
  has_many :stats, as: :entity, dependent: :destroy

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
