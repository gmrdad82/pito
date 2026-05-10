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
    DEFAULT_GAME_RELEASE_OFFSETS = [
      # [offset, severity, default_on]
      [ 30.days, "info",    false ],
      [  7.days, "info",    true  ],
      [  1.day,  "warn",    true  ],
      [  0.days, "success", true  ]
    ].freeze

    module_function

    # Returns an array of `{ kind:, fires_at:, severity: }` hashes for a
    # given CalendarEntry. Phase 16's NotificationScheduler consumes
    # this to insert Notification rows.
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
      # Coarser-than-day precision suppresses pre-release reminders
      # entirely (per note 5: a quarter / year / TBA release isn't a
      # day to remind on).
      precision = entry.release_precision
      return [] if precision.present? && precision != "day"

      suppress_pre_release = pre_release_suppressed?(entry)

      pre_release = DEFAULT_GAME_RELEASE_OFFSETS.flat_map do |offset, severity, default_on|
        next [] unless default_on
        next [] if offset.zero?
        next [] if suppress_pre_release
        [
          { kind: "game_release_upcoming",
            fires_at: entry.starts_at - offset,
            severity: severity }
        ]
      end

      day_of = [ { kind: "game_release_today",
                   fires_at: entry.starts_at,
                   severity: "success" } ]

      pre_release + day_of
    end

    def video_scheduled_declarations(entry)
      [
        { kind: "video_scheduled_publishing_soon",
          fires_at: entry.starts_at - 1.hour,
          severity: "info" }
      ]
    end

    # A `purchase_planned` child with `notify_anyway = false` suppresses
    # pre-release reminders on the parent `game_release`. The day-of
    # reminder always fires.
    def pre_release_suppressed?(entry)
      entry.child_entries
           .where(entry_type: :purchase_planned)
           .where(notify_anyway: false)
           .exists?
    end
  end
end
