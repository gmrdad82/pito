# Phase 16 §1 — Notifications data model + delivery channels.
#
# Central `notifications` table. Single shared inbox (no per-user
# read-state join — see Q1 in
# `docs/plans/beta/16-notifications/specs/01-notification-data-model-and-delivery.md`).
#
# Schema note: spec calls for UUIDs per ADR 0003; the rest of the
# existing schema (calendar_entries, milestone_rules, users, ...)
# uses bigint primary keys. Bigint here too for FK referential
# consistency (matches Phase 15's drift note).
#
# Q9 lock: `scheduled_for` dropped from the v1 schema (master decision
# 2026-05-10) — YAGNI; if user-rescheduling lands later, the column
# gets added then.
class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      # Enum: video_published=0, video_pre_publish_check_missed=1,
      # game_release_upcoming=2, game_release_today=3,
      # milestone_reached=4, calendar_entry_firing=5, sync_error=6,
      # youtube_reauth_needed=7.
      t.integer  :kind, null: false
      t.string   :event_type, null: false
      # Enum: info=0, success=1, warn=2, urgent=3.
      t.integer  :severity, null: false, default: 0

      t.string :title, null: false
      t.text   :body
      t.string :url
      t.jsonb  :event_payload, null: false, default: {}

      # For non-calendar event sources. NULL for calendar-derived rows.
      t.string :dedup_key

      t.datetime :fires_at, null: false

      # Read state — single shared column per Q1.
      t.datetime :in_app_read_at

      # Per-channel delivery stamps. NULL = not delivered.
      t.datetime :discord_delivered_at
      t.datetime :slack_delivered_at

      # Single counter per row across all channels (Q11 + master decision
      # 2026-05-10 #3 — single retry_count for v1; per-channel counters
      # are a follow-up).
      t.integer :retry_count, null: false, default: 0
      t.text    :last_error

      # Source pointers. All optional — calendar-derived rows have a
      # `source_calendar_entry_id`; non-calendar rows have a
      # `dedup_key`.
      t.bigint :source_calendar_entry_id
      t.bigint :source_milestone_rule_id
      t.bigint :created_by_user_id

      t.timestamps
    end

    add_index :notifications, :kind
    add_index :notifications, :event_type
    add_index :notifications, :severity
    add_index :notifications, :fires_at
    add_index :notifications, :created_at
    add_index :notifications, :source_calendar_entry_id,
              where: "source_calendar_entry_id IS NOT NULL"
    add_index :notifications, :source_milestone_rule_id,
              where: "source_milestone_rule_id IS NOT NULL"
    add_index :notifications, :created_by_user_id,
              where: "created_by_user_id IS NOT NULL"

    # Inbox ordering — unread first, recent first (Q1).
    add_index :notifications, [ :in_app_read_at, :created_at ],
              name: "index_notifications_on_read_state_and_recency"

    # Partial index for the unread-fast-path used by `unread_count`.
    add_index :notifications, :in_app_read_at,
              where: "in_app_read_at IS NULL",
              name: "index_notifications_on_unread"

    # Idempotency for calendar-derived rows. (event_type,
    # source_calendar_entry_id, fires_at) is unique when the FK is set
    # so the scheduler's twice-per-minute walk never double-creates.
    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_notifications_unique_calendar_event
      ON notifications (event_type, source_calendar_entry_id, fires_at)
      WHERE source_calendar_entry_id IS NOT NULL
    SQL

    # Idempotency for non-calendar event sources. (event_type,
    # dedup_key) is unique when dedup_key is supplied.
    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_notifications_unique_dedup
      ON notifications (event_type, dedup_key)
      WHERE dedup_key IS NOT NULL
    SQL

    # Every row must be uniquely identifiable for idempotent
    # re-creation. Either a calendar entry FK or a dedup_key.
    execute <<~SQL.squish
      ALTER TABLE notifications
      ADD CONSTRAINT notifications_idempotency_keys_present
      CHECK (source_calendar_entry_id IS NOT NULL OR dedup_key IS NOT NULL)
    SQL

    add_foreign_key :notifications, :calendar_entries,
                    column: :source_calendar_entry_id,
                    on_delete: :nullify
    add_foreign_key :notifications, :milestone_rules,
                    column: :source_milestone_rule_id,
                    on_delete: :nullify
    add_foreign_key :notifications, :users,
                    column: :created_by_user_id,
                    on_delete: :nullify
  end
end
