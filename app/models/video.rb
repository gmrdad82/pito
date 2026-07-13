# frozen_string_literal: true

# Read-only mirror of a YouTube video, populated by `/import videos`
# (smart pull) + the nightly sync. A video-edit/publish pipeline is
# deferred and will be (re)designed later (see docs/follow-up.md).
class Video < ApplicationRecord
  # One picker page (PICKER_PAGE_SIZE rows) in case-stable title order plus
  # the opaque next-page cursor (nil on the last page) — feeds the `show vid`
  # picker sidebar's scroll pager and the TUI's JSON picker. LOWER() keys the
  # keyset so paging never trips over the DB collation's idea of case.
  PICKER_PAGE_SIZE = 50

  def self.picker_page(after: nil, q: nil)
    scope = includes(:channel).order(Arel.sql("LOWER(videos.title) ASC, videos.id ASC"))
    # Same ILIKE as /videos/search-local, but keyset-paged: a filtered picker
    # feed (the TUI's server-side search) pages exactly like the full list.
    scope = scope.where("videos.title ILIKE ?", "%#{q}%") if q.present?
    if (cursor = Pito::ListCursor.decode(after))
      title, id = cursor
      scope = scope.where(
        "(LOWER(videos.title), videos.id) > (?, ?)", title.to_s, id.to_i
      )
    end

    rows = scope.limit(PICKER_PAGE_SIZE + 1).to_a
    more = rows.size > PICKER_PAGE_SIZE
    rows = rows.first(PICKER_PAGE_SIZE)
    [ rows, (more ? picker_cursor_for(rows.last) : nil) ]
  end

  # The opaque cursor for a row's position in picker order.
  def self.picker_cursor_for(row)
    Pito::ListCursor.encode([ row.title.to_s.downcase, row.id ])
  end
  belongs_to :channel

  has_many :video_game_links, dependent: :destroy
  has_many :linked_games, through: :video_game_links, source: :game
  has_many :stats, as: :entity, dependent: :destroy
  has_many :achievements, as: :achievable, dependent: :destroy
  has_many :achievement_metrics, as: :achievable, dependent: :destroy

  # Locally-cached thumbnail master (raw bytes from YouTube CDN, maxres).
  # Attached during sync/import via Video::Thumbnail::Ingest instead of
  # hotlinking i.ytimg.com (which 429s). Display resizing is handled by the
  # named variant — 2× the 450×253 CSS box so retina screens render sharp.
  has_one_attached :thumbnail do |attachable|
    attachable.variant :display, resize_to_fill: [ 900, 506 ]
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
  # `private` filter (D2): privacy_status private AND NOT scheduled — a
  # future-dated scheduled upload is privacy-private on YouTube too, but it
  # is surfaced via the `scheduled` filter/slate instead, never here. NULL or
  # past publish_at both read as "not scheduled".
  scope :private_unscheduled, -> { privacy_status_private.where("publish_at IS NULL OR publish_at <= ?", Time.current) }

  validates :youtube_video_id, presence: true, uniqueness: true
  validates :title, presence: true
end
