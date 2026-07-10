# frozen_string_literal: true

# The owner dropped Arcade in v1.4.0 (it is not filterable, displayable, or
# searchable anywhere), and as of v1.6.0 the IGDB mapper no longer stores it.
# Scrub rows imported before that so "Arcade" stops existing in the data at
# all (re-sync can't heal them: owner-set platform lists are preserved).
class StripArcadeFromGamePlatforms < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE games
      SET platforms = array_remove(platforms, 'Arcade')
      WHERE 'Arcade' = ANY(platforms)
    SQL
  end

  def down
    # Data-only scrub of a deliberately unwanted value; the names are
    # re-derivable from IGDB if ever needed — nothing to restore.
  end
end
