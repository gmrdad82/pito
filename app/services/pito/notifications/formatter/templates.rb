# Phase 16 §2 — Notification formatter.
#
# Registry of per-event-type templates. The three channel formatters
# (`Discord`, `Slack`, `InApp`) all dispatch through this registry,
# so adding a new event type is a one-line REGISTRY entry + a new
# `Templates::<Kind>` PORO.
module Pito
  module Notifications
    module Formatter
      module Templates
        REGISTRY = {
          "video_published"                => VideoPublished,
          "game_release_today"             => GameReleaseToday,
          "milestone_reached"              => MilestoneReached,
          "calendar_entry_firing"          => CalendarEntryFiring,
          "sync_error"                     => SyncError,
          "youtube_reauth_needed"          => YoutubeReauthNeeded,
          "video_diff_detected"            => VideoDiffDetected
        }.freeze
      end
    end
  end
end
