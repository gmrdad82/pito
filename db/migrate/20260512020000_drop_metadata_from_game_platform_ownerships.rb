# 2026-05-12 — Drop unused per-platform ownership metadata.
#
# The per-platform ownership editor (Phase 27 §01f) initially carried
# three optional metadata fields — `acquired_at`, `store`, `notes`. The
# editor revamp simplifies the surface to a single bracketed-checkbox
# row per platform (the "ownership" heading on the dedicated editor
# page), dropping the three inputs entirely. Per user direction we drop
# the columns rather than hide them, since nothing else in the app
# reads or writes them (no JSON renderer, no MCP tool, no analytics).
#
# Reversible: down re-adds the three columns nullable (matching the
# original shape from `20260511160001_create_game_platform_ownerships`).
class DropMetadataFromGamePlatformOwnerships < ActiveRecord::Migration[8.1]
  def up
    remove_column :game_platform_ownerships, :acquired_at
    remove_column :game_platform_ownerships, :store
    remove_column :game_platform_ownerships, :notes
  end

  def down
    add_column :game_platform_ownerships, :acquired_at, :datetime
    add_column :game_platform_ownerships, :store, :string
    add_column :game_platform_ownerships, :notes, :text
  end
end
