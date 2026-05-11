# Phase 27 §1a — drop the legacy single-valued ownership pointer.
#
# Phase 14 §1 added `games.platform_owned_id` as a nullable FK so the
# user could mark "the copy I own is on platform X". Phase 27 replaces
# that with the multi-valued `game_platform_ownerships` join table
# (created in the preceding migration). The column, its FK, and its
# supporting index all come out here.
#
# Backfill plan: this is a NEW surface — the column has no production
# users yet (we are pre-launch), so the migration drops rather than
# migrates. If a backfill becomes necessary later, the recipe is:
#
#   Game.where.not(platform_owned_id: nil).find_each do |g|
#     g.game_platform_ownerships.find_or_create_by!(
#       platform_id: g.platform_owned_id
#     )
#   end
#
# That recipe lives in this file's comments rather than the migration
# body so the migration stays mechanical (drop FK, drop index, drop
# column) and the data-shape decision stays explicit in code review.
class DropPlatformOwnedIdFromGames < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :games, column: :platform_owned_id
    remove_index :games, :platform_owned_id
    remove_column :games, :platform_owned_id, :bigint
  end
end
