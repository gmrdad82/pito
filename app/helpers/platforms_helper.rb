# Phase 27 follow-up (2026-05-11) — canonical platform display.
#
# The project tracks four canonical platforms (`PS5`, `Switch2`,
# `Steam`, `Xbox`). IGDB returns verbose, generation-specific names
# ("PlayStation 5", "Xbox Series X|S", "PC (Microsoft Windows)") that
# don't match the canonical list directly. This helper canonicalises a
# game's platform exposure into the project's locked short labels for
# display.
#
# Phase 27 v2 spec 06 (2026-05-17 PC store collapse): GoG + Epic were
# collapsed into Steam. The Steam logo now represents the PC umbrella
# (Steam-distributed games, GoG-only games, Epic-only games all
# surface under `Steam`). The `external_gog_id` and `external_epic_id`
# columns are gone (see `CollapsePcPlatformsIntoSteam` migration).
#
# Mapping rules (locked):
#
#   - `game.platforms_available` rows whose `slug` or `igdb_id`
#     match a canonical platform (per `Platform::CANONICAL_SHORT_NAMES`
#     / `Platform::IGDB_ID_TO_CANONICAL_SLUG`) render as the canonical
#     short name. Xbox One + Xbox Series X|S both collapse to `Xbox`.
#   - Verbose IGDB names without a canonical alias (e.g.
#     `PlayStation 4`, `Nintendo Switch` (OG), `PC (Microsoft Windows)`)
#     are DROPPED — the project does not track ownership for them and
#     the four canonical short names are the only labels rendered.
#   - The PC umbrella (Steam) is surfaced from the game's
#     `external_steam_app_id` column, NOT from `platforms_available`.
#     IGDB models PC distribution as external games, not platforms.
#
# Output order matches `Platform::CANONICAL_SHORT_NAMES` insertion
# order (PS5, Switch2, Steam, Xbox). Duplicates are deduplicated.
module PlatformsHelper
  # Returns the canonical short-name list for `game` as an array of
  # strings. Empty array when no canonical platform applies (caller
  # renders `—`).
  def canonical_platform_short_names_for(game)
    slugs = canonical_slugs_for(game)
    Platform::CANONICAL_SHORT_NAMES.each_with_object([]) do |(slug, label), acc|
      acc << label if slugs.include?(slug)
    end
  end

  # Render the show-page `platforms:` value: comma-joined canonical
  # short names, or `—` when the game maps to none of the canonical
  # six. Plain text (no HTML) — caller wraps in its own markup.
  def display_platforms(game)
    names = canonical_platform_short_names_for(game)
    names.any? ? names.join(", ") : "—"
  end

  private

  # Returns the set of canonical slugs that apply to `game`, computed
  # from (1) `platforms_available` rows whose slug or igdb_id matches
  # a canonical entry and (2) PC store presence inferred from the
  # external_* id columns.
  def canonical_slugs_for(game)
    slugs = Set.new

    Array(game.platforms_available).each do |platform|
      canonical_slug = platform_canonical_slug(platform)
      slugs << canonical_slug if canonical_slug
    end

    slugs << "steam" if game.external_steam_app_id.present?

    slugs
  end

  def platform_canonical_slug(platform)
    return platform.slug if Platform::CANONICAL_SHORT_NAMES.key?(platform.slug)

    Platform::IGDB_ID_TO_CANONICAL_SLUG[platform.igdb_id]
  end
end
