# Phase 27 v2 spec 06 (2026-05-17 contract collapse) — GoG + Epic
# collapse into Steam.
#
# User-stated contract:
#
#   "Steam, GoG, Epic = collectively 'PC' = display via Steam logo."
#
#   - If IGDB says a game is on Steam AND GoG → track Steam only.
#   - If IGDB says a game is on GoG only → ALSO track Steam.
#   - If IGDB says a game is on Epic only → ALSO track Steam.
#
# Data preservation contract (dispatch directive):
#
#   - For any `game_platform_ownerships` row whose Platform is the
#     `gog` / `epic` seed, ensure the same game has a Steam
#     `game_platform_ownerships` row (find-or-create), then delete
#     the GoG / Epic ownership row.
#   - Drop the `gog` and `epic` Platform seed rows.
#   - Drop the `external_gog_id` and `external_epic_id` columns from
#     `games`.
#
# Out of scope (deliberately):
#
#   - The legacy `external_gog_id` / `external_epic_id` string values
#     are NOT backfilled into `external_steam_app_id` — they are
#     different ID namespaces (GoG product IDs and Epic catalog IDs are
#     not Steam app IDs). Dropping the columns is the data loss the
#     contract change accepts.
#   - The `xbox` Platform row stays. Xbox is a console, not a PC store;
#     the dispatch only collapsed the three PC stores into Steam. The
#     chip + logo were already absent for Xbox before this migration.
#
# Idempotence:
#
#   - `find_by(slug: ...)` returns nil when the seed row was already
#     pruned by a prior run; the per-row backfill loop short-circuits.
#   - `remove_column` is wrapped in `if column_exists?` so a partial
#     prior run (column already dropped) does not raise.
#
# `down`:
#
#   - Re-adds the two columns with the same shape (nullable string,
#     no index — matches the original BetaMigration3 definition).
#   - Re-creates the `gog` + `epic` Platform seed rows by `slug`.
#   - Does NOT attempt to reconstruct the GoG / Epic ownership rows
#     that were collapsed into Steam — that information is gone.
class CollapsePcPlatformsIntoSteam < ActiveRecord::Migration[8.1]
  PC_STORE_SLUGS = %w[gog epic].freeze
  STEAM_SLUG = "steam"

  def up
    backfill_pc_store_ownerships_into_steam
    drop_pc_store_platforms
    drop_pc_store_external_columns
  end

  def down
    re_add_pc_store_external_columns
    re_seed_pc_store_platforms
  end

  private

  # Step 1 — Per (game, pc-store) ownership row: ensure Steam
  # ownership exists, then delete the pc-store row.
  #
  # Uses raw SQL via the connection so the migration does not depend
  # on application models being loadable (Rails best practice — app
  # models are free to drop the `gog` / `epic` references the next
  # boot).
  def backfill_pc_store_ownerships_into_steam
    steam_row = ActiveRecord::Base.connection
                                  .exec_query(
                                    "SELECT id FROM platforms WHERE slug = $1 LIMIT 1",
                                    "platform-by-slug-fetch",
                                    [ STEAM_SLUG ]
                                  ).first
    steam_id = steam_row && steam_row["id"]

    PC_STORE_SLUGS.each do |slug|
      pc_row = ActiveRecord::Base.connection
                                 .exec_query(
                                   "SELECT id FROM platforms WHERE slug = $1 LIMIT 1",
                                   "platform-by-slug-fetch",
                                   [ slug ]
                                 ).first
      pc_id = pc_row && pc_row["id"]
      next if pc_id.nil?

      if steam_id.present?
        # Find every game owned on this PC store; ensure it has a
        # Steam ownership row. Equivalent to a `find_or_create` per
        # game, expressed as a single INSERT…SELECT…WHERE NOT EXISTS
        # so the migration stays O(1) round-trips per PC store.
        execute(<<~SQL)
          INSERT INTO game_platform_ownerships (game_id, platform_id, created_at, updated_at)
          SELECT DISTINCT gpo.game_id, #{steam_id.to_i}, NOW(), NOW()
            FROM game_platform_ownerships gpo
           WHERE gpo.platform_id = #{pc_id.to_i}
             AND NOT EXISTS (
                   SELECT 1
                     FROM game_platform_ownerships existing
                    WHERE existing.game_id = gpo.game_id
                      AND existing.platform_id = #{steam_id.to_i}
                 )
        SQL
      end

      # Remove the PC-store ownership rows now that any Steam mirror
      # exists. If `steam_id` was nil (no Steam seed in this install
      # — unusual but possible), the rows are dropped without a
      # mirror; the user can re-attach Steam manually post-migration.
      execute("DELETE FROM game_platform_ownerships WHERE platform_id = #{pc_id.to_i}")
    end
  end

  # Step 2 — Drop the `gog` + `epic` Platform seed rows themselves.
  # The `Platform` model uses `dependent: :restrict_with_error` on
  # `game_platform_ownerships`; by this point step 1 has already
  # cleared every ownership row pointing at these platforms, so the
  # raw DELETE is safe.
  def drop_pc_store_platforms
    PC_STORE_SLUGS.each do |slug|
      execute("DELETE FROM platforms WHERE slug = '#{slug}'")
    end
  end

  # Step 3 — Drop the two columns the IGDB external-games mapper
  # used to populate.
  def drop_pc_store_external_columns
    if column_exists?(:games, :external_gog_id)
      remove_column :games, :external_gog_id
    end
    if column_exists?(:games, :external_epic_id)
      remove_column :games, :external_epic_id
    end
  end

  def re_add_pc_store_external_columns
    unless column_exists?(:games, :external_gog_id)
      add_column :games, :external_gog_id, :string
    end
    unless column_exists?(:games, :external_epic_id)
      add_column :games, :external_epic_id, :string
    end
  end

  def re_seed_pc_store_platforms
    {
      "gog"  => { name: "GOG",              abbreviation: "GOG"  },
      "epic" => { name: "Epic Games Store", abbreviation: "Epic" }
    }.each do |slug, attrs|
      exists = ActiveRecord::Base.connection
                                 .exec_query(
                                   "SELECT id FROM platforms WHERE slug = $1 LIMIT 1",
                                   "platform-by-slug-fetch",
                                   [ slug ]
                                 ).first
      next if exists

      now = ActiveRecord::Base.connection.quote(Time.current)
      execute(
        "INSERT INTO platforms (name, slug, abbreviation, created_at, updated_at) " \
        "VALUES (#{ActiveRecord::Base.connection.quote(attrs[:name])}, " \
        "#{ActiveRecord::Base.connection.quote(slug)}, " \
        "#{ActiveRecord::Base.connection.quote(attrs[:abbreviation])}, " \
        "#{now}, #{now})"
      )
    end
  end
end
