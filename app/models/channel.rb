# frozen_string_literal: true

class Channel < ApplicationRecord
  belongs_to :youtube_connection, optional: true, inverse_of: :channels
  has_many :videos, dependent: :destroy
  # The channel's games are its videos' games (links are explicit, never
  # inferred): distinct via the through-chain for the games grid + guard.
  has_many :video_game_links, through: :videos
  has_many :linked_games, -> { distinct }, through: :video_game_links, source: :game
  has_many :stats, as: :entity, dependent: :destroy
  has_many :achievements, as: :achievable, dependent: :destroy
  has_many :achievement_metrics, as: :achievable, dependent: :destroy

  # Locally-cached avatar (RAW master blob). We attach the unprocessed source
  # bytes during sync via Channel::Avatar::Ingest instead of hotlinking
  # yt3.ggpht.com (which 429s). Display resizing is handled by named variants —
  # each variant is 2× its CSS display size so hiDPI/retina screens (every
  # phone) get a sharp render; the display size is pinned in CSS:
  #   :sm — 120×120 fill, displayed  60px (show-channel kv-table inline row)
  #   :xs —  70×70  fill, displayed  35px (game channel-recommendation rows) —
  #          a DISTINCT variant sized to ONE braille bar (2.5em @ 14px = 35px)
  #          so each avatar row aligns with its bar
  has_one_attached :avatar do |attachable|
    attachable.variant :sm, resize_to_fill: [ 120, 120 ]
    attachable.variant :xs, resize_to_fill: [ 70, 70 ]
  end

  # Host-less proxy path for the :sm avatar variant (60×60) — used in the
  # show-channel kv-table. Derived from the master blob; auto-recomputes when
  # the avatar blob changes on a later sync.
  def avatar_inline_url
    Pito::ImagePath.call(avatar, variant: :sm)
  end

  # Host-less proxy path for the :xs avatar variant (35×35) — used in the
  # show-game channel-recommendation kv-table. nil when none attached.
  def avatar_xs_url
    Pito::ImagePath.call(avatar, variant: :xs)
  end

  # Locally-cached channel BANNER (RAW master blob, sourced from the
  # 2560×1440 YouTube CDN original). We attach the unprocessed bytes during
  # sync via Channel::Banner::Ingest from
  # brandingSettings.image.banner_external_url, instead of hotlinking YouTube.
  # Display resizing is handled by the named variant (2× the 450×253 CSS box
  # for retina):
  #   :display — 900×506 fill (16:9, detail card banner spot @ 450 CSS px)
  has_one_attached :banner do |attachable|
    attachable.variant :display, resize_to_fill: [ 900, 506 ]
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

  # YouTube exposes NO channel-level like counter (verified against the
  # channels.list docs: statistics = viewCount/subscriberCount/videoCount;
  # relatedPlaylists.likes is a playlist ID of owner-LIKED videos, not a
  # count) — the channel's likes are MATERIALIZED into its own Pito::Stats
  # row by Channel::StatsRefresh (sum of its videos; recomputed at every
  # stats pass). `.to_i` → 0 before the first rollup.
  def like_count
    Pito::Stats.get(self, :likes).to_i
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

  # Resolve a "@handle" / bare "handle" string to a Channel. Exact,
  # @-agnostic, case-insensitive match FIRST; then a pg_trgm fuzzy fallback (best
  # match above the trigram threshold) so "fighter" finds "@fighterpro". Returns
  # nil when nothing matches. The fuzzy query uses the same REPLACE(handle,'@','')
  # expression as index_channels_on_normalized_handle_trigram, so it's index-backed.
  # Shared by the typed `show channel <handle>` path and the :channel_by_handle
  # reply resolver.
  def self.resolve_handle(input)
    norm = input.to_s.sub(/\A@+/, "").downcase
    return nil if norm.blank?

    exact = find_by("LOWER(REPLACE(handle, '@', '')) = LOWER(?)", norm)
    return exact if exact

    where("REPLACE(handle, '@', '') % ?", norm)
      .order(Arel.sql("similarity(REPLACE(handle, '@', ''), #{connection.quote(norm)}) DESC"))
      .first
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
