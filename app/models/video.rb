# frozen_string_literal: true

# Read-only mirror of a YouTube video. Never edited directly — the
# Video table is populated solely by `/import videos` (smart pull)
# and re-populated after VideoPreview publishes succeed. Edits are
# staged in `VideoPreview` and applied through the YouTube Data API.
class Video < ApplicationRecord
  belongs_to :channel

  has_many :video_game_links, dependent: :destroy
  has_many :linked_games, through: :video_game_links, source: :game

  has_neighbors :summary_embedding

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
