# Phase 15 §1 — Calendar Data Model.
#
# Adds `manual_date_override` to `games`. Phase 14 (Game/IGDB sync) carries
# this column too; Phase 15 lands it ahead of Phase 14 because the Game
# host derivation needs to read it to know whether IGDB sync may overwrite
# `calendar_entries.starts_at`. Idempotent: a no-op if Phase 14 ships first.
class AddManualDateOverrideToGames < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:games, :manual_date_override)

    add_column :games, :manual_date_override, :boolean, null: false, default: false
  end
end
