# frozen_string_literal: true

# Creates the achievements and achievement_metrics tables.
#
# achievements      — one row per (achievable, metric, threshold) unlock.
#                     Polymorphic on achievable (Channel / Video / Game).
# achievement_metrics — the system's own latest lifetime value per
#                       (achievable, metric), used by the Evaluate service.
class CreateAchievements < ActiveRecord::Migration[8.1]
  def change
    create_table :achievements do |t|
      t.string  :achievable_type, null: false
      t.bigint  :achievable_id,   null: false
      t.string  :metric,          null: false
      t.bigint  :threshold,       null: false
      t.datetime :unlocked_at,    null: false
      t.timestamps
    end

    add_index :achievements,
              [ :achievable_type, :achievable_id, :metric, :threshold ],
              unique: true,
              name: "index_achievements_unique"

    add_index :achievements,
              [ :achievable_type, :achievable_id ],
              name: "index_achievements_on_achievable"

    create_table :achievement_metrics do |t|
      t.string  :achievable_type, null: false
      t.bigint  :achievable_id,   null: false
      t.string  :metric,          null: false
      t.bigint  :value,           null: false, default: 0
      t.datetime :synced_at
      t.timestamps
    end

    add_index :achievement_metrics,
              [ :achievable_type, :achievable_id, :metric ],
              unique: true,
              name: "index_achievement_metrics_unique"
  end
end
