# frozen_string_literal: true

# Read-only mirror of a YouTube video, populated by `/import videos`
# (smart pull) + the nightly sync. A video-edit/publish pipeline is
# deferred and will be (re)designed later (see docs/follow-up.md).
class Video < ApplicationRecord
  belongs_to :channel

  has_many :video_game_links, dependent: :destroy
  has_many :linked_games, through: :video_game_links, source: :game
  has_many :stats, as: :entity, dependent: :destroy

  has_neighbors :summary_embedding

  # Stat reader — sourced from the polymorphic `stats` table via the
  # `Pito::Stats` facade (P4). Returns nil when no stat row exists.
  def view_count
    Pito::Stats.get(self, :views)
  end

  attribute :privacy_status, :integer
  enum :privacy_status,
       { private: 0, public: 1, unlisted: 2 },
       prefix: true

  validates :youtube_video_id, presence: true, uniqueness: true
  validates :title, presence: true

  # ── Change detection (smart import) ──────────────────────────
  # Returns true when the given etag differs from the stored value
  # (or when no etag is stored yet), indicating the video should be
  # re-fetched from YouTube.
  def etag_changed?(new_etag)
    etag.blank? || etag != new_etag
  end
end
