# frozen_string_literal: true

# Read-only mirror of a YouTube video, populated by `/import videos`
# (smart pull) + the nightly sync. A video-edit/publish pipeline is
# deferred and will be (re)designed later (see docs/follow-up.md).
class Video < ApplicationRecord
  belongs_to :channel

  has_many :video_game_links, dependent: :destroy
  has_many :linked_games, through: :video_game_links, source: :game
  has_many :stats, as: :entity, dependent: :destroy
  has_many :achievements, as: :achievable, dependent: :destroy
  has_many :achievement_metrics, as: :achievable, dependent: :destroy

  # Locally-cached thumbnail master (raw bytes from YouTube CDN). Attached
  # during sync/import via Video::Thumbnail::Ingest instead of hotlinking
  # i.ytimg.com (which 429s). Display resizing is handled by the named variant.
  has_one_attached :thumbnail do |attachable|
    attachable.variant :display, resize_to_fill: [ 450, 253 ]
  end

  has_neighbors :summary_embedding

  # Host-less ActiveStorage proxy path for the :display thumbnail variant
  # (450×253, 16:9), or nil when none is attached.
  def thumbnail_variant_url
    Pito::ImagePath.call(thumbnail, variant: :display)
  end

  # Stat readers — sourced from the polymorphic `stats` table via the
  # `Pito::Stats` facade. Each returns nil when no stat row exists.
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

  scope :published, -> { privacy_status_public }
  scope :unlisted,  -> { privacy_status_unlisted }
  # A future scheduled publish (the `publish_at` column carries the YouTube
  # scheduled go-live time; cleared/past once it has gone live).
  scope :scheduled, -> { where("publish_at > ?", Time.current) }

  validates :youtube_video_id, presence: true, uniqueness: true
  validates :title, presence: true
end
