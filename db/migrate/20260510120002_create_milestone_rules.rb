# Phase 15 §1 — Calendar Data Model.
#
# Declarative rule table. The MilestoneEvaluator reads enabled, never-fired
# rules and writes a `milestone_auto` calendar entry when the configured
# metric crosses the threshold. Idempotent firing via `fired_at IS NULL`.
#
# Schema note: spec calls for UUID primary keys per ADR 0003, but the rest
# of the existing `pito` schema uses bigint primary keys (channels, videos,
# games, users). For FK / referential consistency we use bigint here.
# Surfaced in the implementation log.
class CreateMilestoneRules < ActiveRecord::Migration[8.1]
  def change
    create_table :milestone_rules do |t|
      t.string  :name, null: false
      # Enum: install=0, channel=1, video=2.
      t.integer :scope_type, null: false
      # Plain bigint: discriminator-typed FK semantics, NOT polymorphic. The
      # model-layer validator enforces the (scope_type, scope_id) target.
      t.bigint  :scope_id
      t.string  :metric, null: false
      # Enum: lifetime=0, seven_day=1, twentyeight_day=2, ninety_day=3.
      t.integer :metric_window, null: false, default: 0
      t.decimal :threshold, precision: 20, scale: 4, null: false
      # Enum: cross_up=0, cross_down=1.
      t.integer :direction, null: false, default: 0
      t.datetime :fired_at
      t.boolean :enabled, null: false, default: true
      t.bigint  :created_by_user_id
      t.timestamps
    end

    add_index :milestone_rules, :scope_type
    add_index :milestone_rules, :scope_id, where: "scope_id IS NOT NULL"
    add_index :milestone_rules, :metric
    add_index :milestone_rules, :fired_at
    add_index :milestone_rules, :enabled
    add_index :milestone_rules, :created_by_user_id, where: "created_by_user_id IS NOT NULL"

    add_foreign_key :milestone_rules, :users,
                    column: :created_by_user_id,
                    on_delete: :nullify
  end
end
