# Phase 14 §2 / Phase 27 follow-up (2026-05-17) — Bundle model.
#
# A curated grouping of Games used as a video-attribution pivot. After
# the 2026-05-17 simplification the model has exactly one attribute
# (`name`) plus a composite-cover artifact (`composite_cover_path` +
# `composite_cover_checksum`) and a name-derived `slug` for URL
# stability. The `bundle_type` / `igdb_source_*` / `last_error` columns
# and every IGDB-seeding path are gone. There is no notion of
# "collection" or "series" — every grouping is just a bundle.
#
# Composite cover lives at
# `<PITO_ASSETS_PATH>/covers/bundles/<id>/composite.jpg` and is served
# via `public/covers/bundles/<id>/composite.jpg` (Rails' static-file
# middleware through the `public/covers` symlink — same path shape the
# game masters at `covers/games/<id>/master.jpg` use). The `Compositable`
# concern stores the relative path on `composite_cover_path` and the
# URL helper just prepends a leading slash.
#
# Membership is many-to-many through `bundle_members(position)`.
# Cover regeneration is async via Sidekiq (`BundleCoverBuild`); the
# multi-bundle case (a game's cover changes, fanning out to N bundles)
# goes through `Bundles::CompositeRebuildQueue` so the rebuilds run as
# a deterministic sequential chain (alphabetical by `Bundle.name`).
class Bundle < ApplicationRecord
  # Phase 20 — friendly URLs. Name-derived slug + history-on-rename.
  extend FriendlyId
  friendly_id :slug_candidates, use: %i[slugged history finders]

  # Phase 27 §01h — shared composite-cover interface
  # (`composite_cover_url`, `composite_cover_absolute_path`,
  # `sweep_composite_cover_file`).
  include Compositable

  has_many :bundle_members, -> { order(:position) }, dependent: :destroy
  has_many :games, through: :bundle_members

  # Phase 14 §3 — video attribution. CASCADE on the FK plus `dependent:
  # :destroy` so the AR callbacks fire when the bundle is destroyed.
  has_many :video_game_links, dependent: :destroy
  has_many :videos, through: :video_game_links

  validates :name, presence: true, length: { maximum: 255 }

  after_save :enqueue_cover_build_if_changed
  before_destroy :sweep_composite_cover_file

  # Phase 34 (2026-05-18) — Bundle records join the unified `/games`
  # Meilisearch corpus alongside Game records. The hook fires on
  # create / update so a rename or composite-cover change re-embeds
  # the bundle. Membership changes are handled by `BundleMember`'s
  # own `after_commit` hook (it re-enqueues the parent bundle).
  after_commit :enqueue_voyage_index, on: %i[create update]

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

  def enqueue_cover_build_if_changed
    return if destroyed?
    return unless saved_change_to_id? || needs_cover_rebuild?
    BundleCoverBuild.perform_async(id)
  end

  # Phase 34 (2026-05-18) — enqueue the Voyage + Meilisearch indexer
  # on the `:search` queue. The job itself guards on a missing record
  # and on blank input text; this hook stays a one-liner.
  def enqueue_voyage_index
    return if destroyed?
    BundleVoyageIndexJob.perform_later(id)
  end
end
