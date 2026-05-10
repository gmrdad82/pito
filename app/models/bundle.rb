# Phase 14 §2 — Bundle model.
#
# A curated grouping of Games used as a video-attribution pivot in
# analytics ("series", "collection", "genre", "custom"). Each Bundle
# has a composite cover image stitched together from its members'
# IGDB covers, regenerated whenever membership changes.
#
# Decisions (master-agent locked 2026-05-10):
#   - `bundle_type` is immutable post-create (the form does not expose
#     the field on edit; strong params drop it on update).
#   - Composite cover is built async via Sidekiq (`BundleCoverBuild`).
#   - `last_error` text column surfaces the most recent build / seed
#     failure inline on the show page.
#   - On destroy, the on-disk cover file is removed (`before_destroy`).
#   - `/composites/:filename.jpg` route is auth-gated.
#
# IGDB-source provenance:
#   - `igdb_source_type` ∈ { franchise, source_collection, source_genre }
#     (Rails enum prefix `igdb_source` to avoid clashes with Game#genres
#     etc.; predicates read e.g. `igdb_source_franchise?`).
#   - `igdb_source_id` is the IGDB-side ID; composite-unique with
#     `igdb_source_type` (one local bundle per IGDB-source pair).
#   - For `custom` bundles both columns are NULL.
class Bundle < ApplicationRecord
  # Phase 20 — friendly URLs. Name-derived slug + history-on-rename.
  extend FriendlyId
  friendly_id :slug_candidates, use: %i[slugged history finders]

  enum :bundle_type,
       { series: 0, collection: 1, genre: 2, custom: 3 },
       prefix: :type

  enum :igdb_source_type,
       { franchise: 0, source_collection: 1, source_genre: 2 },
       prefix: :igdb_source

  has_many :bundle_members, -> { order(:position) }, dependent: :destroy
  has_many :games, through: :bundle_members

  # Phase 14 §3 — video attribution. CASCADE on the FK plus `dependent:
  # :destroy` so the AR callbacks fire when the bundle is destroyed.
  has_many :video_game_links, dependent: :destroy
  has_many :videos, through: :video_game_links

  validates :name, presence: true, length: { maximum: 255 }
  validates :bundle_type, presence: true
  validates :igdb_source_id,
            uniqueness: { scope: :igdb_source_type, allow_nil: true }
  validate  :igdb_source_pair_consistency

  after_save :enqueue_cover_build_if_changed
  before_destroy :sweep_composite_cover_file

  # Public URL for the composite cover. Returns nil when the bundle has
  # not been built yet. Routes through the auth-gated
  # `/composites/:filename` controller (see `CompositesController`).
  def composite_cover_url
    return nil if composite_cover_path.blank?
    "/composites/#{File.basename(composite_cover_path)}"
  end

  # Absolute on-disk Pathname for the composite cover. Returns nil when
  # the bundle has not been built yet.
  def composite_cover_absolute_path
    return nil if composite_cover_path.blank?
    Pito::AssetsRoot.path(*Pathname.new(composite_cover_path).each_filename.to_a)
  rescue Pito::AssetsRoot::Error
    nil
  end

  # True when the cover on disk is stale relative to the current member
  # set. The checksum is computed over the sorted list of member
  # `cover_image_id` values plus the layout name; reordering the
  # members alone does NOT trigger a rebuild.
  def needs_cover_rebuild?
    member_count = bundle_members.size
    return composite_cover_path.present? if member_count.zero? && composite_cover_checksum.blank?
    return false                          if member_count.zero?

    image_ids = bundle_members.includes(:game).map { |bm| bm.game.cover_image_id }.compact
    return composite_cover_path.blank? if image_ids.empty?

    layout = Composite::LayoutChooser.choose(image_ids.size)
    expected = Composite::Checksum.compute(image_ids, layout.layout_name)
    composite_cover_checksum != expected
  end

  # True when a cover-rebuild job is in flight for this bundle. Surfaced
  # on the show page as a "regenerating…" indicator. Best-effort —
  # checks Sidekiq's queue / retry / scheduled sets and falls back to
  # `false` if Sidekiq's testing API is in :fake mode.
  def cover_rebuild_in_flight?
    return false unless defined?(BundleCoverBuild)

    if Sidekiq::Testing.respond_to?(:fake?) && Sidekiq::Testing.fake?
      jobs = BundleCoverBuild.jobs
      return jobs.any? { |j| j["args"].first == id }
    end

    false
  rescue StandardError
    false
  end

  # Phase 20 — friendly URLs.
  def slug_limit
    80
  end

  def slug_candidates
    [
      normalized_name_slug,
      [ normalized_name_slug, id ].compact.reject(&:blank?).join("-"),
      "bundle-#{id}"
    ]
  end

  def should_generate_new_friendly_id?
    will_save_change_to_name? || super
  end

  def normalize_friendly_id(value)
    Pito::SlugBuilder.build(value.to_s, limit: slug_limit).presence ||
      "bundle-#{id || SecureRandom.hex(4)}"
  end

  private

  def normalized_name_slug
    Pito::SlugBuilder.build(name.to_s, limit: slug_limit)
  end

  def igdb_source_pair_consistency
    if type_custom? && (igdb_source_type.present? || igdb_source_id.present?)
      errors.add(:igdb_source_type, "must be blank for custom bundles")
      errors.add(:igdb_source_id,   "must be blank for custom bundles") if igdb_source_id.present?
    end
    return if type_custom?

    if igdb_source_type.blank? != igdb_source_id.blank?
      errors.add(:igdb_source_id, "must be set when igdb_source_type is set")
    end
  end

  def enqueue_cover_build_if_changed
    return if destroyed?
    return unless saved_change_to_id? || needs_cover_rebuild?
    BundleCoverBuild.perform_async(id)
  end

  # Best-effort cleanup. The reap-orphans rake task picks up anything
  # that survives this hook (e.g. when `composite_cover_path` got
  # blanked before destroy).
  def sweep_composite_cover_file
    abs = composite_cover_absolute_path
    File.delete(abs) if abs && File.exist?(abs)
  rescue StandardError
    nil
  end
end
