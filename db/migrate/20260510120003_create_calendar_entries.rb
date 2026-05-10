# Phase 15 §1 — Calendar Data Model.
#
# The unified calendar entry table. Eight `entry_type` values, three
# `source` values, four `state` values. Type-specific fields live in
# `metadata` (jsonb) plus typed FK columns for cross-references
# (`video_id`, `game_id`, `channel_id`, `project_id`, `parent_entry_id`,
# `milestone_rule_id`). NOT polymorphic — typed FKs per Q2.
#
# Schema note: spec calls for UUIDs per ADR 0003; the rest of the
# existing schema (channels / videos / games / users / projects) uses
# bigint primary keys. Bigint here too for FK referential consistency.
# Surfaced in the implementation log.
#
# DST notes: timestamps are `timestamptz` (UTC at rest). The `timezone`
# column stores the IANA tz the entry was authored in. DST forward (spring)
# in the local tz: 02:30 has no canonical mapping; Rails' default
# `Time.zone.parse` resolves to the post-shift instant (03:30 local). DST
# backward (fall) in the local tz: 02:30 is ambiguous; Rails resolves to
# the post-shift moment by default. The model layer round-trips correctly
# in both cases for unambiguous local times.
class CreateCalendarEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :calendar_entries do |t|
      # Enum: channel_published=0, video_published=1, video_scheduled=2,
      # game_release=3, purchase_planned=4, milestone_manual=5,
      # milestone_auto=6, custom=7.
      t.integer  :entry_type, null: false
      # Enum: manual=0, derived=1, auto=2.
      t.integer  :source, null: false, default: 0
      # Enum: scheduled=0, occurred=1, cancelled=2, superseded=3.
      t.integer  :state, null: false, default: 0
      t.string   :title, null: false
      t.text     :description
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.boolean  :all_day, null: false, default: false
      t.string   :timezone, null: false, default: "UTC"
      t.jsonb    :metadata, null: false, default: {}
      t.jsonb    :source_ref
      t.bigint   :video_id
      t.bigint   :game_id
      t.bigint   :channel_id
      t.bigint   :project_id
      t.bigint   :parent_entry_id
      t.bigint   :milestone_rule_id
      t.boolean  :manual_date_override, null: false, default: false
      # Enum: day=0, month=1, quarter=2, year=3, tba=4.
      t.integer  :release_precision
      t.boolean  :tba_remind_monthly, null: false, default: false
      t.boolean  :notify_anyway, null: false, default: false
      t.bigint   :created_by_user_id
      t.timestamps
    end

    # Scalar / btree indexes
    add_index :calendar_entries, :entry_type
    add_index :calendar_entries, :source
    add_index :calendar_entries, :state
    add_index :calendar_entries, :starts_at
    add_index :calendar_entries, :ends_at, where: "ends_at IS NOT NULL"
    add_index :calendar_entries, :video_id, where: "video_id IS NOT NULL"
    add_index :calendar_entries, :game_id, where: "game_id IS NOT NULL"
    add_index :calendar_entries, :channel_id, where: "channel_id IS NOT NULL"
    add_index :calendar_entries, :project_id, where: "project_id IS NOT NULL"
    add_index :calendar_entries, :parent_entry_id, where: "parent_entry_id IS NOT NULL"
    add_index :calendar_entries, :milestone_rule_id, where: "milestone_rule_id IS NOT NULL"
    add_index :calendar_entries, :created_by_user_id, where: "created_by_user_id IS NOT NULL"

    # Composite indexes for the month grid range query and the schedule
    # view's "upcoming" queries plus the occurred-flipper job.
    add_index :calendar_entries, [ :entry_type, :starts_at ]
    add_index :calendar_entries, [ :state, :starts_at ]

    # GIN on jsonb columns for source_ref upsert lookup + metadata search.
    add_index :calendar_entries, :metadata, using: :gin
    add_index :calendar_entries, :source_ref, using: :gin,
              where: "source_ref IS NOT NULL"

    # Q17 race-condition guard — three partial unique expression indexes
    # so the Derivation upsert is safe under concurrent host updates.
    # `entry_type` integer values per the enum: video_published=1,
    # video_scheduled=2 share the same source_ref.video_id namespace
    # but DIFFERENT entry_type values, so the unique key is
    # (entry_type, video_id-extracted-from-jsonb).
    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_calendar_entries_unique_video_source_ref
      ON calendar_entries (entry_type, ((source_ref->>'video_id')))
      WHERE entry_type IN (1, 2) AND source_ref IS NOT NULL
    SQL
    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_calendar_entries_unique_channel_source_ref
      ON calendar_entries (entry_type, ((source_ref->>'channel_id')))
      WHERE entry_type = 0 AND source_ref IS NOT NULL
    SQL
    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_calendar_entries_unique_game_source_ref
      ON calendar_entries (entry_type, ((source_ref->>'game_id')))
      WHERE entry_type = 3 AND source_ref IS NOT NULL
    SQL

    # Check constraint — span sanity.
    execute <<~SQL.squish
      ALTER TABLE calendar_entries
      ADD CONSTRAINT calendar_entries_ends_at_after_starts_at
      CHECK (ends_at IS NULL OR ends_at >= starts_at)
    SQL

    # Foreign keys per Q2.
    add_foreign_key :calendar_entries, :videos,
                    column: :video_id, on_delete: :cascade
    add_foreign_key :calendar_entries, :games,
                    column: :game_id, on_delete: :cascade
    add_foreign_key :calendar_entries, :channels,
                    column: :channel_id, on_delete: :cascade
    add_foreign_key :calendar_entries, :projects,
                    column: :project_id, on_delete: :nullify
    add_foreign_key :calendar_entries, :calendar_entries,
                    column: :parent_entry_id, on_delete: :nullify
    add_foreign_key :calendar_entries, :milestone_rules,
                    column: :milestone_rule_id, on_delete: :nullify
    add_foreign_key :calendar_entries, :users,
                    column: :created_by_user_id, on_delete: :nullify
  end
end
