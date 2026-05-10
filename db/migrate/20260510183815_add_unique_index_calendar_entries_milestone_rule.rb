# Phase 15 security audit F2 — race-condition guard for milestone-rule
# firing.
#
# `MilestoneRule#fire!` already gates on `fired_at IS NULL` and writes
# the calendar entry inside a single transaction. The model-level guard
# is correct for the single-process case, but two concurrent
# `MilestoneEvaluator` runs (e.g., a manual invocation overlapping the
# Sidekiq cron job) can both pass the `fired_at IS NULL` check before
# either commits, producing two `milestone_auto` entries for the same
# rule.
#
# This partial unique index gives the database the final word: only one
# `milestone_auto` (entry_type=6) auto-sourced (source=2) entry per
# `milestone_rule_id`. The application catches the resulting
# `ActiveRecord::RecordNotUnique` and treats it as the no-op it is.
class AddUniqueIndexCalendarEntriesMilestoneRule < ActiveRecord::Migration[8.1]
  def change
    add_index :calendar_entries, :milestone_rule_id,
              unique: true,
              where: "entry_type = 6 AND source = 2",
              name: "index_calendar_entries_unique_milestone_rule"
  end
end
