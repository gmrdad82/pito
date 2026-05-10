# Phase 16 §1 follow-up — security audit F4.
#
# The original `create_notifications` migration paired
# `ON DELETE: :nullify` on `source_calendar_entry_id` with a CHECK
# constraint requiring `source_calendar_entry_id IS NOT NULL OR
# dedup_key IS NOT NULL`. Deleting a calendar entry that owned a
# notification with no `dedup_key` would NULL the FK and immediately
# violate CHECK — the delete would raise.
#
# Resolution (master decision 2026-05-10, F4): notifications derived
# from a calendar entry die with their source. `:cascade` is the
# cleanest interpretation of the lifecycle — the notification has no
# meaning without the calendar entry that produced it.
#
# History is not rewritten; the original migration stays, this one
# adjusts the FK in place.
class FixNotificationsCalendarEntryCascade < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :notifications, column: :source_calendar_entry_id
    add_foreign_key :notifications, :calendar_entries,
                    column: :source_calendar_entry_id,
                    on_delete: :cascade
  end

  def down
    remove_foreign_key :notifications, column: :source_calendar_entry_id
    add_foreign_key :notifications, :calendar_entries,
                    column: :source_calendar_entry_id,
                    on_delete: :nullify
  end
end
