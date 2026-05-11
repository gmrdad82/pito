# Phase 16 §2 — Notification formatter.
#
# Registry of per-event-type templates. The four channel formatters
# (`Discord`, `Slack`, `InApp`, `Mcp`) all dispatch through this
# registry, so adding a new event type is a one-line REGISTRY entry +
# a new `Templates::<Kind>` PORO.
module NotificationFormatter
  module Templates
    REGISTRY = {
      "video_published"                => VideoPublished,
      "video_pre_publish_check_missed" => VideoPrePublishCheckMissed,
      "game_release_upcoming"          => GameReleaseUpcoming,
      "game_release_today"             => GameReleaseToday,
      "milestone_reached"              => MilestoneReached,
      "calendar_entry_firing"          => CalendarEntryFiring,
      "sync_error"                     => SyncError,
      "youtube_reauth_needed"          => YoutubeReauthNeeded,
      "video_diff_detected"            => VideoDiffDetected,
      "channel_diff_detected"          => ChannelDiffDetected
    }.freeze
  end
end
