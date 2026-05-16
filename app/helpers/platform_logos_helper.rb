# Phase 27 v2 spec 07 — platform-logo rendering.
#
# Tiny wrapper around the static PNG assets the
# `pito:platform_logos:download` Rake task drops into
# `public/platform_logos/`. The helper emits raw `<img>` tags pointing
# at `/platform_logos/<slug>-<size>.png` — no asset-pipeline digest,
# no fingerprint. Re-running the Rake task overwrites the files in
# place.
#
# Surfaces:
#
#   - Tile footer on `/games`: one 14-px logo per tile, selected by
#     `game_index_tile_logo_slug(game)` (owned-wins-over-available,
#     `KNOWN_LOGOS` declaration order).
#   - Detail page LEFT pane: 0..5 logos at 56 px, returned by
#     `game_detail_logo_slugs(game)` in the locked PS5 / Switch2 /
#     Steam / GoG / Epic order. PC distribution stores (Steam / GoG /
#     Epic) are inferred from `external_steam_app_id` /
#     `external_gog_id` / `external_epic_id`, NOT from
#     `platforms_available`.
module PlatformLogosHelper
  # Locked set of platform slugs that have a downloaded logo asset.
  # Order matters — `game_index_tile_logo_slug` walks this list and
  # picks the FIRST applicable slug (so PS5 wins when a game is owned
  # on both PS5 and Steam).
  KNOWN_LOGOS = %w[ps5 switch2 steam gog epic].freeze

  # The only sizes the Rake task downloads. `platform_logo_tag`
  # raises `ArgumentError` for sizes outside this list — typos
  # surface at boot instead of as broken `<img>` tags at runtime.
  LOGO_SIZES = [ 16, 64 ].freeze

  # Brand-correct display labels for the alt text. Mirrors
  # `Platform::CANONICAL_SHORT_NAMES`, scoped to the 5-asset set
  # (Xbox is dropped — no logo).
  LOGO_ALT_LABELS = {
    "ps5"     => "PS5",
    "switch2" => "Switch2",
    "steam"   => "Steam",
    "gog"     => "GoG",
    "epic"    => "Epic"
  }.freeze

  # Render a single platform-logo `<img>` tag.
  #
  # Returns nil when `slug` is not in `KNOWN_LOGOS` so callers can
  # `<% if (tag = platform_logo_tag(...)) %><%= tag %><% end %>`
  # without an extra presence check.
  #
  # Raises `ArgumentError` when `size` is not in `LOGO_SIZES` — this
  # is a typo-catcher, not a runtime error path; the only legal
  # sizes are 16 and 64.
  def platform_logo_tag(slug, size:)
    raise ArgumentError, "unknown logo size: #{size.inspect}" unless LOGO_SIZES.include?(size)
    return nil unless KNOWN_LOGOS.include?(slug)

    image_tag(
      "/platform_logos/#{slug}-#{size}.png",
      width: size,
      height: size,
      alt: LOGO_ALT_LABELS.fetch(slug),
      class: "platform-logo platform-logo--#{slug}",
      style: "width: #{size}px; height: #{size}px; vertical-align: middle;"
    )
  end

  # Pick the ONE platform slug to render in the tile footer. Returns
  # a string slug from `KNOWN_LOGOS` or nil when no known platform
  # applies.
  #
  # Selection rule, in order:
  #
  #   1. The first slug from `game.owned_platforms` (mapped to
  #      canonical) intersected with `KNOWN_LOGOS`, walked in
  #      `KNOWN_LOGOS` declaration order.
  #   2. The first slug from `game.platforms_available` (mapped to
  #      canonical) intersected with `KNOWN_LOGOS`, same walk. Also
  #      includes the PC-store inferences (Steam / GoG / Epic) so an
  #      unreleased Steam game still shows the Steam logo on its tile.
  #   3. Nil — no logo segment renders.
  def game_index_tile_logo_slug(game)
    owned     = canonical_logo_slugs(game.owned_platforms)
    available = canonical_logo_slugs(game.platforms_available) | pc_store_slugs(game)

    KNOWN_LOGOS.find { |slug| owned.include?(slug) } ||
      KNOWN_LOGOS.find { |slug| available.include?(slug) }
  end

  # Detail-page LEFT pane — every slug from `KNOWN_LOGOS` that
  # applies to the game, in `KNOWN_LOGOS` declaration order.
  # Inclusion conditions:
  #
  #   - `ps5` / `switch2` — the canonical Platform row is in
  #     `game.platforms_available` (matched by slug OR by
  #     `IGDB_ID_TO_CANONICAL_SLUG`).
  #   - `steam` / `gog` / `epic` — the corresponding
  #     `external_*_id` column is present.
  #
  # PC (Microsoft Windows) `platforms_available` rows are IGNORED —
  # per the project's canonical mapping, PC distribution is
  # represented by the per-store external IDs, not the generic PC
  # platform row.
  def game_detail_logo_slugs(game)
    set = canonical_logo_slugs(game.platforms_available) | pc_store_slugs(game)
    KNOWN_LOGOS.select { |slug| set.include?(slug) }
  end

  private

  # Map a collection of `Platform` records to the set of canonical
  # logo slugs they belong to. A row's `slug` wins when it matches
  # one of `KNOWN_LOGOS` directly; otherwise the IGDB-id alias map
  # (`Platform::IGDB_ID_TO_CANONICAL_SLUG`) is consulted.
  def canonical_logo_slugs(platforms)
    Array(platforms).each_with_object(Set.new) do |platform, set|
      slug = canonical_slug_for_platform(platform)
      set << slug if slug && KNOWN_LOGOS.include?(slug)
    end
  end

  def canonical_slug_for_platform(platform)
    return platform.slug if KNOWN_LOGOS.include?(platform.slug)

    Platform::IGDB_ID_TO_CANONICAL_SLUG[platform.igdb_id]
  end

  # PC-store inference. The three store columns each independently
  # contribute a logo slug. A game with both `external_steam_app_id`
  # and `external_gog_id` set contributes both `steam` and `gog`.
  def pc_store_slugs(game)
    slugs = Set.new
    slugs << "steam" if game.external_steam_app_id.present?
    slugs << "gog"   if game.external_gog_id.present?
    slugs << "epic"  if game.external_epic_id.present?
    slugs
  end
end
