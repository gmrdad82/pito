# Phase 27 v2 spec 07 — platform-logo rendering (v7: theme-aware).
#
# Tiny wrapper around the static PNG assets the
# `pito:platform_logos:download` Rake task drops into
# `public/platforms/`. The helper emits raw `<img>` tags pointing
# at `/platforms/<slug>-<size>-<color>.png` — no asset-pipeline
# digest, no fingerprint. Re-running the Rake task overwrites the
# files in place.
#
# Theme awareness:
#
#   The rake task ships TWO color variants per (platform, size):
#   `<slug>-<size>-black.png` and `<slug>-<size>-white.png`. The
#   active theme (`<html data-theme>`) is set client-side by the
#   layout boot script and the `theme` Stimulus controller, so the
#   server has no canonical knowledge of which variant the user
#   will see. The helper handles this by emitting BOTH variants in
#   parallel `<img>` tags and letting CSS hide the off-theme one
#   via `.platform-logo--{black,white}` rules. This mirrors the
#   pattern already used by `Games::CoverComponent` and
#   `shared/_igdb_cover` for the missing-cover fallback SVGs.
#
#   Callers that need an explicit color (e.g. a screenshot fixture
#   or a forced-theme preview) pass `color: :black` or
#   `color: :white`, which emits a single `<img>` for that variant.
#
# Surfaces:
#
#   - Tile footer on `/games`: one 14-px logo per tile, selected by
#     `game_index_tile_logo_slug(game)` (owned-wins-over-available,
#     `KNOWN_LOGOS` declaration order).
#   - Detail page LEFT pane: 0..3 logos at 64 px, returned by
#     `game_detail_logo_slugs(game)` in the locked PS5 / Switch2 /
#     Steam order. PC distribution stores (Steam) are inferred from
#     `external_steam_app_id`, NOT from `platforms_available`.
module PlatformLogosHelper
  # Locked set of platform slugs that have a downloaded logo asset.
  # Order matters — `game_index_tile_logo_slug` walks this list and
  # picks the FIRST applicable slug (so PS5 wins when a game is owned
  # on both PS5 and Steam).
  KNOWN_LOGOS = %w[ps5 switch2 steam].freeze

  # The only sizes the Rake task downloads. `platform_logo_tag`
  # raises `ArgumentError` for sizes outside this list — typos
  # surface at boot instead of as broken `<img>` tags at runtime.
  LOGO_SIZES = [ 16, 64 ].freeze

  # The two color variants the Rake task downloads. The helper
  # accepts `:black`, `:white`, or `:auto` (default) — `:auto`
  # emits both variants with CSS visibility scoped to the active
  # theme. Anything else raises `ArgumentError`.
  LOGO_COLORS = %i[black white].freeze

  # Brand-correct display labels for the alt text. Mirrors
  # `Platform::CANONICAL_SHORT_NAMES`, scoped to the 3-asset set
  # (Xbox dropped — no logo shipped; GoG + Epic collapsed into Steam
  # per the 2026-05-17 PC store collapse).
  LOGO_ALT_LABELS = {
    "ps5"     => "PS5",
    "switch2" => "Switch2",
    "steam"   => "Steam"
  }.freeze

  # Render a single platform-logo `<img>` tag (or a `<span>` wrapping
  # both color variants when `color: :auto`).
  #
  # Returns nil when `slug` is not in `KNOWN_LOGOS` so callers can
  # `<% if (tag = platform_logo_tag(...)) %><%= tag %><% end %>`
  # without an extra presence check.
  #
  # Raises `ArgumentError` when `size` is not in `LOGO_SIZES` — this
  # is a typo-catcher, not a runtime error path; the only legal
  # sizes are 16 and 64. Same for `color`: must be `:auto`, `:black`,
  # or `:white`.
  #
  # `display_size:` overrides the rendered pixel dimensions when the
  # asset is downloaded at a higher resolution than the on-screen
  # size (e.g. tile footers download the 16-px variant but render at
  # 14 px; detail-page logos download the 64-px variant but render
  # at 56 px). Defaults to `size` when omitted.
  def platform_logo_tag(slug, size:, color: :auto, display_size: nil)
    raise ArgumentError, "unknown logo size: #{size.inspect}" unless LOGO_SIZES.include?(size)
    raise ArgumentError, "unknown logo color: #{color.inspect}" unless color == :auto || LOGO_COLORS.include?(color)
    return nil unless KNOWN_LOGOS.include?(slug)

    render_size = display_size || size

    if color == :auto
      # Emit both color variants; CSS picks the visible one based on
      # `<html data-theme>`. Wrap in a `<span class="platform-logo-pair">`
      # so a caller's per-element layout (vertical-align, margin) hits
      # the wrapper, not the off-theme `<img>`. The wrapper itself is
      # inline-block at the rendered size so it occupies the same
      # footprint a single `<img>` would.
      content_tag(
        :span,
        class: "platform-logo-pair platform-logo-pair--#{slug}",
        style: "display: inline-block; width: #{render_size}px; height: #{render_size}px; vertical-align: middle; line-height: 0;"
      ) do
        safe_join([
          platform_logo_img(slug, size: size, color: :black, render_size: render_size),
          platform_logo_img(slug, size: size, color: :white, render_size: render_size)
        ])
      end
    else
      platform_logo_img(slug, size: size, color: color, render_size: render_size)
    end
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
  #      includes the PC-store inferences (Steam) so an unreleased
  #      Steam game still shows the Steam logo on its tile.
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
  #   - `steam` — the corresponding `external_steam_app_id` column
  #     is present.
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

  # Build a single-variant `<img>` tag. Centralizes the URL shape
  # and the per-color visibility class so `platform_logo_tag` and
  # the explicit-color paths stay consistent.
  def platform_logo_img(slug, size:, color:, render_size:)
    image_tag(
      "/platforms/#{slug}-#{size}-#{color}.png",
      width: render_size,
      height: render_size,
      alt: LOGO_ALT_LABELS.fetch(slug),
      data: { theme: (color == :black ? "light" : "dark") },
      class: "platform-logo platform-logo--#{slug} platform-logo--#{color}",
      style: "width: #{render_size}px; height: #{render_size}px; vertical-align: middle;"
    )
  end

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

  # PC-store inference. Steam is the sole PC-umbrella surface; GoG
  # and Epic collapsed into Steam per the 2026-05-17 PC store collapse
  # (the underlying `external_gog_id` / `external_epic_id` columns
  # were dropped from `games`).
  def pc_store_slugs(game)
    slugs = Set.new
    slugs << "steam" if game.external_steam_app_id.present?
    slugs
  end
end
