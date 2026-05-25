# Drop all platform and ownership tables + related columns from games.
#
# Removed surfaces:
#   - game_platform_ownerships — per-platform ownership join table (Phase 27 §1a)
#   - game_platforms           — IGDB-sourced game↔platform availability join
#   - platforms                — platform lookup table
#   - games.played_platform_id — FK pointer to the user's single played-on platform
#   - games.platforms          — legacy jsonb column (Phase 4 legacy, Phase 14 retired)
#
# The `platforms` jsonb column on `games` is a Phase 4 legacy artefact that
# has been retired since Phase 14 §1. The column's data is stale; dropping it
# is safe. The `played_platform_id` FK must go before the `platforms` table
# (FK constraint) even though `platforms` is dropped in the same migration;
# Rails executes statements in order so removing the FK column first avoids
# a constraint violation.
class DropPlatformsAndOwnerships < ActiveRecord::Migration[8.0]
  def up
    # 1. Remove the FK column on games first (constraint references platforms)
    remove_column :games, :played_platform_id
    remove_column :games, :platforms

    # 2. Drop the join tables (FKs already referencing platforms cascade or restrict)
    drop_table :game_platform_ownerships
    drop_table :game_platforms

    # 3. Finally drop the lookup table itself
    drop_table :platforms
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Platform + ownership tables have been intentionally removed. " \
          "Restore from a pre-migration snapshot if needed."
  end
end
