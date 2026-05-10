# Phase 15 §1 — Calendar Data Model.
#
# Hourly Sidekiq cron job auxiliary: flips ripe `:scheduled` entries to
# `:occurred`. Cancelled / superseded entries are left alone.
module Calendar
  class OccurredFlipper
    def self.flip_ripe!
      CalendarEntry
        .where(state: :scheduled)
        .where("starts_at <= ?", Time.current)
        .update_all(
          state: CalendarEntry.states[:occurred],
          updated_at: Time.current
        )
    end
  end
end
