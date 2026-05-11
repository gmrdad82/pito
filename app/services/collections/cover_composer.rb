# Phase 27 §01h — Collection composite cover composer.
#
# Builds a single shelf-sized composite cover (98 × 130 JPEG) for a
# `Collection` by stitching together up to 6 member games' IGDB covers
# via `Collections::CompositeLayout`. Output is fingerprint-cached on
# disk under `<PITO_ASSETS_PATH>/composites/collection-<id>.jpg`.
#
# Public API:
#
#   Collections::CoverComposer.new.call(collection) -> Pathname | nil
#
# Returns:
#   - `Pathname` when a write occurred (cache miss → fresh JPEG bytes
#     written) OR when the existing on-disk file matches the
#     fingerprint (cache hit → returns the existing path WITHOUT
#     rewriting the file).
#   - `nil` for the `:empty` and `:passthrough` layouts (0 / 1 member
#     collections — the consumer view renders the empty placeholder or
#     the lone `Games::CoverComponent` directly).
#
# Member ordering: alphabetical by `Game#title` (case-insensitive).
# Deterministic ordering is load-bearing for the fingerprint to remain
# stable across renders.
#
# Membership cap: only the first 6 members (alphabetical) contribute to
# the layout AND the fingerprint. The 7th+ members are intentionally
# dropped — they are not represented anywhere in the composite.
#
# Degradation policy (LOCKED — substitute placeholder, do not re-raise):
#   When `Composite::TileCache#fetch(cover_image_id)` raises
#   `Composite::TileFetchError`, OR when libvips raises `Vips::Error`
#   during `thumbnail_image` / `join`, the failing slot is substituted
#   with the dark-grey placeholder block at the slot's target box
#   dimensions and the composite continues building. The composer logs
#   at WARN with the cover_image_id and the error class. No retry, no
#   re-raise — the composite ships with a grey hole; the next
#   collection update (which would change the fingerprint) gives the
#   cache another chance. This intentionally differs from
#   `BundleCoverBuild` (which re-raises so Sidekiq retries), because
#   the collection composer is intended to run synchronously inside
#   the page-render request path on first miss.
module Collections
  class CoverComposer
    JPEG_QUALITY = 80
    MAX_TILES    = 6

    def initialize(tile_cache: Composite::TileCache.new, logger: Rails.logger)
      @tile_cache = tile_cache
      @logger     = logger
    end

    # Build (or no-op on cache hit) the composite cover for `collection`.
    # Returns the absolute on-disk Pathname when a composite exists for
    # this collection (hit or miss), `nil` for 0 / 1 member collections.
    def call(collection)
      games  = ordered_games(collection)
      count  = games.size
      layout = Collections::CompositeLayout.choose(count)

      return nil if layout == :empty || layout == :passthrough

      cover_image_ids = games.map(&:cover_image_id)  # nil entries preserved
      fingerprint     = Composite::Checksum.compute(cover_image_ids, layout.to_s)
      path            = output_path(collection)

      return path if fingerprint_hit?(collection, fingerprint, path)

      tiles = cover_image_ids.map { |cid| safe_fetch_tile(cid) }
      composite =
        begin
          Collections::CompositeLayout.compose(layout, tiles)
        rescue Vips::Error => e
          # libvips failed during `join` / final composition — degrade
          # the entire composite to a uniform placeholder grid at the
          # canvas size. Same WARN convention as per-tile failures.
          warn_log(nil, e)
          fully_placeholder_composite(layout)
        end

      FileUtils.mkdir_p(path.dirname)
      composite.jpegsave(path.to_s, Q: JPEG_QUALITY, strip: true)

      relative = path.relative_path_from(Pito::AssetsRoot.root).to_s
      collection.update!(composite_cover_path:     relative,
                         composite_cover_checksum: fingerprint)
      path
    end

    # Absolute on-disk Pathname for the composite cover of `collection`.
    # Pathname is derived purely from `id` (one composite per collection).
    def output_path(collection)
      Pito::AssetsRoot.path("composites", "collection-#{collection.id}.jpg")
    end

    private

    # Ordered, limited list of member games. Alphabetical by
    # `LOWER(title)` for a stable, case-insensitive ordering; capped to
    # `MAX_TILES`. `.to_a` materializes so the fingerprint and the tile
    # iteration see the SAME set in the SAME order.
    def ordered_games(collection)
      collection.games
                .order(Arel.sql("LOWER(games.title)"))
                .limit(MAX_TILES)
                .to_a
    end

    # True iff the collection's recorded fingerprint matches the freshly
    # computed one AND the on-disk file is still present. Either side
    # missing → miss (re-render).
    def fingerprint_hit?(collection, fingerprint, path)
      collection.composite_cover_checksum == fingerprint && path.exist?
    end

    # Fetch a single tile from the cache, swallowing per-tile errors so
    # one bad IGDB asset cannot block the whole composite. Returns nil
    # on either a nil `cover_image_id` (game with no cover art) OR on
    # any `Composite::TileFetchError` / `Vips::Error` during fetch.
    # `Collections::CompositeLayout.compose` substitutes the placeholder
    # for nil entries.
    def safe_fetch_tile(cover_image_id)
      return nil if cover_image_id.blank?
      @tile_cache.fetch(cover_image_id)
    rescue Composite::TileFetchError, Vips::Error => e
      warn_log(cover_image_id, e)
      nil
    end

    # Build a placeholder-only composite for `layout` by passing nil for
    # every slot — `CompositeLayout.compose` substitutes the dark-grey
    # block at each slot's exact box. Used as the last-resort fallback
    # when even the join chain fails.
    def fully_placeholder_composite(layout)
      slots = Collections::CompositeLayout.tile_boxes(layout).size
      Collections::CompositeLayout.compose(layout, Array.new(slots, nil))
    end

    def warn_log(cover_image_id, error)
      @logger.warn(
        "Collections::CoverComposer tile fallback " \
        "cover_image_id=#{cover_image_id.inspect} " \
        "error_class=#{error.class} message=#{error.message}"
      )
    end
  end
end
