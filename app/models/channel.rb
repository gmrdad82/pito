# frozen_string_literal: true

class Channel < ApplicationRecord
  belongs_to :youtube_connection, optional: true, inverse_of: :channels
  has_many :videos, dependent: :destroy
  has_many :stats, as: :entity, dependent: :destroy
  has_many :achievements, as: :achievable, dependent: :destroy
  has_many :achievement_metrics, as: :achievable, dependent: :destroy

  # Locally-cached avatar (RAW master blob). We attach the unprocessed source
  # bytes during sync via Channel::Avatar::Ingest instead of hotlinking
  # yt3.ggpht.com (which 429s). Display resizing is handled by named variants:
  #   :lg — 120×120 fill (item lists, recommended channels)
  #   :sm —  60×60  fill (kv-table inline row in the show-channel detail card)
  #   :xs —  35×35  fill (game channel-recommendation kv-table rows, item 16) —
  #          a DISTINCT variant (no browser downscale), sized to ONE braille bar
  #          (2.5em @ 14px = 35px) so each avatar row aligns with its bar (17.9)
  has_one_attached :avatar do |attachable|
    attachable.variant :lg, resize_to_fill: [ 120, 120 ]
    attachable.variant :sm, resize_to_fill: [ 60, 60 ]
    attachable.variant :xs, resize_to_fill: [ 35, 35 ]
  end

  # Host-less ActiveStorage proxy path for the :lg avatar variant (120×120),
  # or nil when none is attached (the view falls back to the placeholder).
  def avatar_variant_url
    Pito::ImagePath.call(avatar, variant: :lg)
  end

  # Host-less proxy path for the :sm avatar variant (60×60) — used in the
  # show-channel kv-table. Derived from the master blob; auto-recomputes when
  # the avatar blob changes on a later sync.
  def avatar_inline_url
    Pito::ImagePath.call(avatar, variant: :sm)
  end

  # Host-less proxy path for the :xs avatar variant (35×35) — used in the
  # show-game channel-recommendation kv-table (item 16). nil when none attached.
  def avatar_xs_url
    Pito::ImagePath.call(avatar, variant: :xs)
  end

  # Locally-cached channel BANNER (RAW master blob, sourced from the
  # 2560×1440 YouTube CDN original). We attach the unprocessed bytes during
  # sync via Channel::Banner::Ingest from
  # brandingSettings.image.banner_external_url, instead of hotlinking YouTube.
  # Display resizing is handled by the named variant:
  #   :display — 450×253 fill (16:9, detail card banner spot)
  has_one_attached :banner do |attachable|
    attachable.variant :display, resize_to_fill: [ 450, 253 ]
  end

  # Host-less ActiveStorage proxy path for the :display banner variant
  # (450×253), or nil when none is attached (the detail card falls back
  # gracefully).
  def banner_url
    Pito::ImagePath.call(banner, variant: :display)
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
