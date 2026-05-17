# 2026-05-17 (Wave B6) — file trimmed to slug-collapse logic only.
#
# This module used to emit `<img>` tags for the per-platform PNG
# assets shipped by the now-deleted `pito:platform_logos:download`
# rake task. The PNG pipeline was dropped in Wave B1 and the per-
# surface render swapped to inline text chips (Waves B2-B5). The
# helper now exists ONLY to expose the canonical-platform-slug
# computation that the chip ViewComponent consumes:
#
#   - `KNOWN_LOGOS` — the locked canonical slug set (ps, switch,
#     steam). Name retained for caller-stability across this wave;
#     a Wave F consolidation pass can rename it to `KNOWN_CHIPS`
#     and rename the file to `platform_chips_helper.rb` once every
#     consumer is on the chip surface.
#   - `PC_STORE_IGDB_IDS` — PC / Linux / Mac / DOS / Web IGDB ids
#     that collapse to "steam" for chip-display purposes.
#   - `game_index_tile_logo_slug(game)` — returns the single
#     owned-or-available slug for the tile-footer chip (one chip
#     per tile).
#   - `game_detail_logo_slugs(game)` — returns the full ordered
#     slug list for the detail-page chip row.
#   - `pc_store_slugs(game)` — public helper that injects "steam"
#     when the game is on a PC store (either via
#     `external_steam_app_id` or via IGDB platform id).
#
# TODO (Wave F consolidation): rename file +
# module to `platform_chips_helper.rb` / `PlatformChipsHelper`,
# rename `KNOWN_LOGOS` → `KNOWN_CHIPS`, rename
# `game_*_logo_slug(s)` → `game_*_chip_slug(s)`. Deferred so the
# in-flight chip swaps across `/games`, `/games/:id`, `/bundles`,
# and the tile partial don't churn while the rename lands.
module PlatformLogosHelper
  # Locked set of canonical platform slugs the chip surface renders.
  # Order matters — `game_index_tile_logo_slug` walks this list and
  # picks the FIRST applicable slug (so PS wins when a game is
  # owned on both PS and Steam).
  KNOWN_LOGOS = %w[ps switch steam].freeze

  # IGDB platform ids that represent PC desktop / web — all collapse
  # to "steam" for chip-display purposes. Rationale: the project's
  # canonical mapping treats Steam as the umbrella surface for PC
  # distribution (GoG / Epic were dropped per the 2026-05-17 store
  # collapse). When IGDB lists a game on PC (Windows / Mac / Linux /
  # classic Mac / Web), we render the Steam chip to communicate
  # "PC release" without needing a populated `external_steam_app_id`
  # column. The per-store external id remains the alternate
  # inference path (still honored in `pc_store_slugs`).
  #
  #   6  -> PC (Microsoft Windows)
  #   3  -> Linux
  #   14 -> Mac
  #   13 -> PC DOS / classic Mac (DOS family)
  #   92 -> SteamVR (Web umbrella in the IGDB sense)
  PC_STORE_IGDB_IDS = [ 6, 3, 14, 13, 92 ].freeze

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
  #      Steam game still shows the Steam chip on its tile.
  #   3. Nil — no chip segment renders.
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
  #   - `ps` / `switch` — the canonical Platform row is in
  #     `game.platforms_available` (matched by slug OR by
  #     `IGDB_ID_TO_CANONICAL_SLUG`).
  #   - `steam` — EITHER the `external_steam_app_id` column is
  #     present OR `platforms_available` carries an IGDB id in
  #     `PC_STORE_IGDB_IDS` (PC / Mac / Linux / DOS / Web). The
  #     project collapses every PC-desktop store into Steam for
  #     chip-display purposes.
  def game_detail_logo_slugs(game)
    set = canonical_logo_slugs(game.platforms_available) | pc_store_slugs(game)
    KNOWN_LOGOS.select { |slug| set.include?(slug) }
  end

  # PC-store inference. Steam is the sole PC-umbrella surface; GoG
  # and Epic collapsed into Steam per the 2026-05-17 PC store collapse
  # (the underlying `external_gog_id` / `external_epic_id` columns
  # were dropped from `games`).
  #
  # Two independent triggers add "steam" to the slug set:
  #
  #   1. `external_steam_app_id` is populated — direct evidence the
  #      game is on Steam.
  #   2. Any row in `platforms_available` has an IGDB id in
  #      `PC_STORE_IGDB_IDS` — IGDB lists the game on PC (Windows /
  #      Mac / Linux / DOS / Web), which the project collapses to a
  #      single Steam chip.
  #
  # Either trigger is sufficient. The Set wrapper guarantees de-dup
  # so a game with BOTH triggers (Pragmata-style — IGDB id 6 plus a
  # populated `external_steam_app_id`) only contributes one Steam
  # slug to the union.
  #
  # Public (not private) so callers outside the helper module — most
  # notably the chip ViewComponent — can compose the slug set
  # themselves when they need finer-grained control than
  # `game_detail_logo_slugs` / `game_index_tile_logo_slug` offer.
  def pc_store_slugs(game)
    slugs = Set.new
    slugs << "steam" if game.external_steam_app_id.present?
    slugs << "steam" if Array(game.platforms_available).any? { |p| PC_STORE_IGDB_IDS.include?(p.igdb_id) }
    slugs
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
end
