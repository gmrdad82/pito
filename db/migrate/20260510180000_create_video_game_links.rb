# Phase 14 §3 — `video_game_links` join table.
#
# Polymorphic-ish join: a Video can be linked to a Game OR a Bundle
# (per row, exactly one). Powers the "linked games / bundles" surface
# on the video edit form and the "linked videos" surface on the game /
# bundle show pages, plus analytics attribution in Phase 13.
#
# - `link_type` enum (0 = game, 1 = bundle).
# - `game_id` and `bundle_id` are nullable; CHECK constraint enforces
#   exactly-one-non-null per row.
# - Composite-unique partial indexes prevent the same Video being
#   linked to the same Game / Bundle twice.
# - `is_primary` is a hint for analytics weighting (Phase 13). Multiple
#   primaries per Video are allowed (master-agent decision #2).
# - `created_by_user_id` audit column (master-agent decision #4) — set
#   from `Current.user` on create. Nullable so future cleanup or
#   bulk-import paths don't require a user.
class CreateVideoGameLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :video_game_links do |t|
      t.references :video, null: false, foreign_key: { on_delete: :cascade }
      t.integer :link_type, null: false
      t.references :game, null: true, foreign_key: { on_delete: :cascade }
      t.references :bundle, null: true, foreign_key: { on_delete: :cascade }
      t.boolean :is_primary, null: false, default: false
      t.references :created_by_user, null: true,
                                     foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps
    end

    add_index :video_game_links, :link_type
    add_index :video_game_links,
              [ :video_id, :game_id ],
              unique: true,
              where: "game_id IS NOT NULL",
              name: "idx_video_game_links_unique_game"
    add_index :video_game_links,
              [ :video_id, :bundle_id ],
              unique: true,
              where: "bundle_id IS NOT NULL",
              name: "idx_video_game_links_unique_bundle"
    add_index :video_game_links,
              :is_primary,
              where: "is_primary = true",
              name: "idx_video_game_links_primary"

    # Defense-in-depth: enforce exactly-one-target at the DB layer. The
    # ActiveRecord validator (`exactly_one_target`) gives nice error
    # messages; the CHECK constraint catches raw-SQL smuggle attempts.
    execute <<~SQL.squish
      ALTER TABLE video_game_links
      ADD CONSTRAINT video_game_links_exactly_one_target
      CHECK (
        (link_type = 0 AND game_id IS NOT NULL AND bundle_id IS NULL)
        OR (link_type = 1 AND bundle_id IS NOT NULL AND game_id IS NULL)
      )
    SQL
  end
end
