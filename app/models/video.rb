# frozen_string_literal: true

# Read-only mirror of a YouTube video, populated by `/import videos`
# (smart pull) + the nightly sync. A video-edit/publish pipeline is
# deferred and will be (re)designed later (see docs/follow-up.md).
class Video < ApplicationRecord
  belongs_to :channel

  has_many :video_game_links, dependent: :destroy
  has_many :linked_games, through: :video_game_links, source: :game
  has_many :stats, as: :entity, dependent: :destroy

  # Locally-cached thumbnail (480x270 JPEG). Attached during sync/import via
  # Video::Thumbnail::Ingest instead of hotlinking i.ytimg.com (which 429s).
  has_one_attached :thumbnail

  has_neighbors :summary_embedding

  # Display variant URL for the thumbnail, or nil when none is attached.
  def thumbnail_variant_url
    return nil unless thumbnail.attached?

    thumbnail.variant(resize_to_limit: [ 480, 270 ])
  rescue StandardError
    nil
  end

  # Stat readers — sourced from the polymorphic `stats` table via the
  # `Pito::Stats` facade (P4). Each returns nil when no stat row exists.
  def view_count
    Pito::Stats.get(self, :views)
  end

  def like_count
    Pito::Stats.get(self, :likes)
  end

  def comment_count
    Pito::Stats.get(self, :comments)
  end

  # Human name for the YouTube category id (Gaming, People & Blogs, …), or
  # nil when the id is blank/unknown. Reuses the canonical id→name table.
  def category_name
    Video::EmbedText::YOUTUBE_CATEGORIES[category_id]
  end

  attribute :privacy_status, :integer
  enum :privacy_status,
       { private: 0, public: 1, unlisted: 2 },
       prefix: true

  validates :youtube_video_id, presence: true, uniqueness: true
  validates :title, presence: true
end
