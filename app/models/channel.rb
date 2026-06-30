# frozen_string_literal: true

class Channel < ApplicationRecord
  belongs_to :youtube_connection, optional: true, inverse_of: :channels
  has_many :videos, dependent: :destroy
  has_many :stats, as: :entity, dependent: :destroy
  has_many :achievements, as: :achievable, dependent: :destroy
  has_many :achievement_metrics, as: :achievable, dependent: :destroy

  # Locally-cached avatar (240x240 JPEG). We attach OUR copy during sync via
  # Channel::Avatar::Ingest instead of hotlinking yt3.ggpht.com (which 429s).
  has_one_attached :avatar

  # Host-less ActiveStorage proxy path for the avatar variant, or nil when none
  # is attached (the view falls back to the placeholder). Host-less so the image
  # loads from whatever host serves the page (localhost, tunnel, production).
  def avatar_variant_url
    Pito::ImagePath.call(avatar, variant: { resize_to_limit: [ 240, 240 ] })
  end

  # Host-less proxy path for the SMALL (50%) avatar variant — a real 120×120
  # ActiveStorage variant (displayed at 60px) used in the show-channel kv-table,
  # NOT a CSS-scaled full image. Derived from the attached avatar, so it is
  # available for any channel with an avatar (no sync needed) and auto-recomputes
  # when the avatar blob changes on a later sync.
  def avatar_inline_variant_url
    Pito::ImagePath.call(avatar, variant: { resize_to_limit: [ 120, 120 ] })
  end

  # Locally-cached channel BANNER (374x210 JPEG, 16:9 — the same box as a video
  # thumbnail). We attach OUR copy during sync via Channel::Banner::Ingest from
  # brandingSettings.image.banner_external_url, instead of hotlinking YouTube.
  has_one_attached :banner

  # Host-less ActiveStorage proxy path for the banner variant, or nil when none
  # is attached (the detail card falls back to the avatar in the banner spot).
  def banner_variant_url
    Pito::ImagePath.call(banner, variant: { resize_to_limit: [ 374, 210 ] })
  end

  # Stat readers — sourced from the polymorphic `stats` table via the
  # `Pito::Stats` facade. Return nil when no stat row exists.
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

  # YouTube channel page URL.
  # Handle present: https://www.youtube.com/@<handle without leading @>
  # Otherwise:      https://www.youtube.com/channel/<youtube_channel_id>
  def youtube_channel_url
    if handle.present?
      "https://www.youtube.com/@#{handle.to_s.sub(/\A@+/, '')}"
    else
      "https://www.youtube.com/channel/#{youtube_channel_id}"
    end
  end

  # YouTube Studio management URL for this channel.
  def youtube_studio_url
    "https://studio.youtube.com/channel/#{youtube_channel_id}"
  end
end
