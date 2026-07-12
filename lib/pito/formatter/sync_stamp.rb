# frozen_string_literal: true

# Pure function. Absolute "DD-MM-YYYY HH:MM" timestamp formatter — the one
# sync-stamp shape used across the detail cards, the linked-game card, and the
# schedule confirmations (the `strftime` recurred 7× app-wide before this).
#
# Input: a Time/DateTime/ActiveSupport::TimeWithZone or nil. The value is
# rendered in the app's local zone (`in_time_zone`).
# Output: "DD-MM-YYYY HH:MM", or `fallback` (default "—") when the input is
# blank — callers with bespoke never-synced copy pass it in.
#
# Examples:
#   call(Time.utc(2026, 7, 2, 14, 30))       => "02-07-2026 16:30"  (CEST)
#   call(nil)                                => "—"
#   call(nil, fallback: "never synced")      => "never synced"
module Pito
  module Formatter
    module SyncStamp
      FORMAT = "%d-%m-%Y %H:%M"

      module_function

      def call(time, fallback: "—")
        return fallback if time.blank?

        time.in_time_zone.strftime(FORMAT)
      end
    end
  end
end
