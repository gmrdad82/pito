# Phase 27 follow-up (2026-05-11) — composite-cover warm-up for the
# `/games` Collections outer-shelf.
#
# `GamesController#index` calls this service with the list of
# collections that will render in the outer shelf. For each collection,
# the service asks `Collections::CoverComposer` to materialize the
# on-disk composite cover (or no-op on a fingerprint cache hit, or on
# the `:empty` / `:passthrough` layouts where the composer returns nil
# by design).
#
# Why a controller-level service instead of a view-side trigger:
#   - Predictable cost — the composer runs ONCE per request per
#     collection, not once per cover render call site.
#   - Single source of truth — the view stays declarative
#     (`<img src="<%= collection.cover_url %>">`) and the composer
#     stays out of the render path.
#   - Reviewer audit trail — the P27 reviewer flagged the composer as
#     dead code; the service surfaces the call site explicitly so a
#     future contributor reading `GamesController#index` sees how
#     covers get built.
#
# Failure policy: the composer's per-tile and per-composite degradation
# rules are already strict-but-soft (placeholder substitution, no
# re-raise). This wrapper does not add another retry layer — if a
# collection fails completely, the next render gets a fresh chance.
# Any exception that escapes the composer is logged and swallowed so
# one bad collection does not 500 the entire `/games` index.
module Games
  class PrepareCollectionsForShelf
    def initialize(composer: Collections::CoverComposer.new, logger: Rails.logger)
      @composer = composer
      @logger   = logger
    end

    # Walks every collection in `collections` (Enumerable or
    # ActiveRecord::Relation), invoking the composer on each. Returns
    # the input untouched so callers can chain.
    def call(collections)
      collections.each do |collection|
        @composer.call(collection)
      rescue StandardError => e
        # Composer is documented as soft-degradation, but be paranoid:
        # never let a single collection blow up the index render.
        @logger.warn(
          "Games::PrepareCollectionsForShelf swallowed " \
          "collection_id=#{collection.id} error_class=#{e.class} " \
          "message=#{e.message}"
        )
      end
      collections
    end
  end
end
