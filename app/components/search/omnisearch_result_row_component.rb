# 2026-05-18 — Per-row markup for an omnisearch result list.
#
# One component, five kinds — each kind maps to a `<li>` shape used
# across the three omnisearch modes (game_index / bundle_add /
# games_search). Modes pick which kinds they render; the row
# component itself only knows how to render a single row.
#
# Kinds:
#   :local_game_link  — clickable title → /games/:slug, muted "game"
#                        label. Used by :games_search.
#   :local_bundle_link— clickable title → /bundles/:slug, muted
#                        "bundle" label. Used by :games_search.
#   :igdb_add         — title + [add] POST /games. Used by
#                        :game_index and :games_search.
#   :local_game_add_to_bundle — title + [add] POST
#                        /bundles/:bundle_id/members. Used by
#                        :bundle_add.
#   :igdb_add_to_bundle — title + [add] POST
#                        /bundles/:bundle_id/members/from_igdb. Used
#                        by :bundle_add.
#
# 2026-05-19 — Dropped the `:igdb_open` kind. The dispatcher
# (`Game::SearchService`) now dedupes IGDB rows against local Games
# by `igdb_id` before reaching the view, so an IGDB row that exists
# locally is never rendered — there is no [open] branch to maintain.
# A local hit always wins via the `:local_game_link` row above.
#
# Args (vary by kind):
#   kind:           one of the five symbols above.
#   record:         the Game / Bundle (for *_link / *_add_to_bundle
#                    when local). nil for raw IGDB rows.
#   igdb_row:       the IGDB hash (id, name, first_release_date)
#                    for :igdb_add / :igdb_add_to_bundle. nil otherwise.
#   bundle:         the host Bundle for :*_to_bundle kinds. nil
#                    otherwise.
module Search
  class OmnisearchResultRowComponent < ViewComponent::Base
    KINDS = %i[
      local_game_link
      local_bundle_link
      igdb_add
      local_game_add_to_bundle
      igdb_add_to_bundle
    ].freeze

    def initialize(kind:, record: nil, igdb_row: nil, bundle: nil)
      raise ArgumentError, "unknown row kind: #{kind.inspect}" unless KINDS.include?(kind)
      @kind = kind
      @record = record
      @igdb_row = igdb_row
      @bundle = bundle
    end

    attr_reader :kind, :record, :igdb_row, :bundle

    # Release year extracted from the IGDB hash; nil-safe. Returns nil
    # when the IGDB row carries no `first_release_date`.
    def igdb_release_year
      ts = igdb_row && igdb_row["first_release_date"]
      return nil if ts.blank?
      Time.at(ts).utc.year
    end
  end
end
