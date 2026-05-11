# Phase 4 §3.2 — Collection groups Games. Phase 8 — install-wide
# (no tenant scope). Phase 27 §01h — composite cover support.
class Collection < ApplicationRecord
  # Phase 20 — friendly URLs. Name-derived slug + history-on-rename.
  extend FriendlyId
  friendly_id :slug_candidates, use: %i[slugged history finders]

  # Phase 27 §01h — composite cover (`composite_cover_path` +
  # `composite_cover_checksum` columns; `#composite_cover_url`,
  # `#composite_cover_absolute_path`, `#sweep_composite_cover_file`
  # methods).
  include Compositable

  has_many :games, dependent: :nullify

  validates :name, presence: true, length: { maximum: 255 }

  attribute :name, :string, default: "Untitled collection"

  # Phase 27 §01h — best-effort sweep of the on-disk composite cover.
  # Survives `Errno::ENOENT` and any unexpected error during delete (we
  # never want destroy to fail because the cache happened to be in a
  # weird state). The reap-orphans rake task (deferred follow-up) picks
  # up anything that survives this hook.
  before_destroy :sweep_composite_cover_file

  # Phase 20 — friendly URLs.
  def slug_limit
    80
  end

  def slug_candidates
    [
      normalized_name_slug,
      [ normalized_name_slug, id ].compact.reject(&:blank?).join("-"),
      "collection-#{id}"
    ]
  end

  def should_generate_new_friendly_id?
    will_save_change_to_name? || super
  end

  def normalize_friendly_id(value)
    Pito::SlugBuilder.build(value.to_s, limit: slug_limit).presence ||
      "collection-#{id || SecureRandom.hex(4)}"
  end

  # Phase 27 §01h — Public URL for the sub-shelf composite cover.
  # Returns `nil` until `Collections::CoverComposer` has stamped the
  # fingerprint on this row (counts of 0 and 1 never stamp). The `?v=`
  # query parameter is the cache-buster: browsers and CDN edges evict
  # when the fingerprint changes.
  #
  # The `variant:` kwarg is reserved for future shelf-size variants and
  # is currently ignored (the composer has a single output size).
  def cover_url(variant: nil)
    _ = variant
    return nil if composite_cover_checksum.blank?
    "/composites/collection-#{id}.jpg?v=#{composite_cover_checksum}"
  end

  private

  def normalized_name_slug
    Pito::SlugBuilder.build(name.to_s, limit: slug_limit)
  end
end
