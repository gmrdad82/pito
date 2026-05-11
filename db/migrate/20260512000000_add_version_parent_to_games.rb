# Phase 28 §01a — Multi-version game grouping.
#
# Self-referential parent / edition relationship on `Game`.
# `version_parent_id` points at the primary row; `version_title`
# names the edition ("Deluxe", "Standard", "Game of the Year",
# "Collector's", etc.).
#
# Both columns are nullable: every existing row stays a primary
# (`version_parent_id IS NULL`). `on_delete: :nullify` so destroying a
# parent leaves its editions in place as orphan primaries (detach
# is non-destructive — locked decision #7 in the umbrella plan).
class AddVersionParentToGames < ActiveRecord::Migration[8.1]
  def change
    add_reference :games, :version_parent,
                  foreign_key: { to_table: :games, on_delete: :nullify },
                  null: true,
                  index: true
    add_column :games, :version_title, :string, null: true
  end
end
