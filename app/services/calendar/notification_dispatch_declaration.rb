# Phase 15 §1 — Calendar Data Model.
#
# Read-only metadata Phase 16 will consume. Single source of truth for
# "calendar entry → notification kinds + offsets." Lives in this phase
# so the data tier carries the contract.
#
# This is metadata only. NO insert happens here. NO delivery happens
# here. Phase 16 owns the writer and the channel.
module Calendar
  module NotificationDispatchDeclaration
    module_function

    # Returns an array of `{ kind:, fires_at:, severity: }` hashes for a
    # given CalendarEntry. Phase 16's NotificationScheduler consumes
    # this to insert Notification rows.
    #
    # 2026-05-12 — the `game_release_upcoming` pre-release reminder
    # track (T-7 / T-1) was dropped per user direction. Only
    # `game_release_today` survives for game_release entries.
    def declarations_for(entry)
      case entry.entry_type
      when "game_release"
        game_release_declarations(entry)
      when "video_scheduled"
        video_scheduled_declarations(entry)
      when "milestone_auto"
        [ { kind: "milestone_reached",
            fires_at: entry.starts_at,
            severity: "success" } ]
      else
        []
      end
    end

    def game_release_declarations(entry)
      # Coarser-than-day precision suppresses the release reminder
      # entirely (per note 5: a quarter / year / TBA release isn't a
      # day to remind on).
      precision = entry.release_precision
      return [] if precision.present? && precision != "day"

      [ { kind: "game_release_today",
          fires_at: entry.starts_at,
          severity: "success" } ]
    end

    def video_scheduled_declarations(entry)
      [
        { kind: "video_scheduled_publishing_soon",
          fires_at: entry.starts_at - 1.hour,
          severity: "info" }
      ]
    end
  end
end
