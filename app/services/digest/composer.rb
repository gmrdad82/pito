# Daily digest composer.
#
# Provider-agnostic aggregator for the last 24h of pito activity.
# Returns a `Result` struct with one entry per section. Renderers
# (`Digest::SlackRenderer`, `Digest::DiscordRenderer`) read this struct
# and shape it for their wire format.
#
# Window: `now - 24.hours` ≤ activity < `now`. Stored timestamps are
# UTC; rendering is the renderer's job (the renderer knows the user's
# tz via the user passed alongside).
#
# Sections (locked decisions, Mobile note):
#
#   - `channels_synced` — Channels whose `last_synced_at` falls inside
#     the window. Capped at 10 for payload sanity; total count carried
#     in `channels_synced_total`.
#   - `videos_imported` — Videos created (`created_at` inside window).
#     Capped at 10.
#   - `videos_updated` — Videos whose `last_synced_at` falls inside
#     the window AND that were created BEFORE the window (so we don't
#     double-count brand-new imports). Capped at 10.
#   - `notifications_open` — Unread Notifications older than 1 hour
#     (excluding rows newer than 1h to avoid flapping). Capped at 10.
#
# The `login_attempts` section is gone with
# the LoginAttempt table.
#
# "All quiet" fallback: if every section is empty, the renderer
# substitutes a single-line "no activity in the last 24 hours" payload.
# `Result#any_activity?` exposes the flag.
module Digest
  class Composer
    WINDOW = 24.hours
    SECTION_LIMIT = 10

    Section = Struct.new(:label, :total, :items, keyword_init: true) do
      def empty?
        total.to_i.zero?
      end
    end

    Result = Struct.new(
      :user,
      :window_started_at,
      :window_ended_at,
      :channels_synced,
      :videos_imported,
      :videos_updated,
      :notifications_open,
      keyword_init: true
    ) do
      def sections
        [
          channels_synced,
          videos_imported,
          videos_updated,
          notifications_open
        ].compact
      end

      def any_activity?
        sections.any? { |s| !s.empty? }
      end
    end

    def initialize(user, now: Time.current)
      @user = user
      @now = now
      @window_start = now - WINDOW
    end

    def call
      Result.new(
        user: @user,
        window_started_at: @window_start,
        window_ended_at: @now,
        channels_synced: channels_synced_section,
        videos_imported: videos_imported_section,
        videos_updated: videos_updated_section,
        notifications_open: notifications_open_section
      )
    end

    private

    def channels_synced_section
      scope = Channel
                .where(last_synced_at: @window_start...@now)
                .order(last_synced_at: :desc)
      Section.new(
        label: "channels synced",
        total: scope.count,
        items: scope.limit(SECTION_LIMIT).map { |c| channel_label(c) }
      )
    end

    def videos_imported_section
      scope = Video
                .where(created_at: @window_start...@now)
                .order(created_at: :desc)
      Section.new(
        label: "videos imported",
        total: scope.count,
        items: scope.limit(SECTION_LIMIT).map { |v| video_label(v) }
      )
    end

    def videos_updated_section
      # Updated = synced inside the window but created before the
      # window. Distinguishes a fresh import from a re-sync.
      scope = Video
                .where(last_synced_at: @window_start...@now)
                .where("created_at < ?", @window_start)
                .order(last_synced_at: :desc)
      Section.new(
        label: "videos updated",
        total: scope.count,
        items: scope.limit(SECTION_LIMIT).map { |v| video_label(v) }
      )
    end

    def notifications_open_section
      # Unread notifications older than 1 hour. Younger ones are still
      # "fresh" — we don't want every digest to surface a notification
      # the user is actively reading.
      scope = Notification
                .unread
                .where("created_at < ?", @now - 1.hour)
                .order(created_at: :desc)
      Section.new(
        label: "open notifications",
        total: scope.count,
        items: scope.limit(SECTION_LIMIT).map { |n| notification_label(n) }
      )
    end

    def channel_label(channel)
      channel.title.presence || channel.handle.presence || channel.channel_url.to_s
    end

    def video_label(video)
      video.title.presence || video.youtube_video_id.to_s
    end

    def notification_label(notification)
      notification.title.to_s
    end
  end
end
