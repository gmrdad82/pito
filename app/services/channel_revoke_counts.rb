# Phase 24 — cascade-count service for the per-channel `[revoke]` modal.
#
# Given a `Channel`, returns a `Counts` value object describing the
# number of dependent rows that will be deleted when the channel is
# revoked. The modal renders these counts so the user can see the full
# footprint before confirming.
#
# One `COUNT(*)` per logical category. All counts run under indexed
# foreign keys (or partial indexes); on a channel with thousands of
# videos and millions of analytics rows the full sweep runs in tens of
# milliseconds. Counts are computed at modal-render time — no caching
# (the user is reading consequences in real time; a stale total would
# be worse than a fresh one).
#
# Categories mirror the umbrella spec's locked modal copy:
#
#   - videos            count of `videos.channel_id = channel.id`
#   - analytics         sum across channel_* and video_* analytics tables
#   - diffs             channel_diffs + video_diffs across the channel's videos
#   - change_logs       channel_change_logs + video_change_logs
#   - links             video_game_links across the channel's videos
#   - rejected_imports  rejected_video_imports
#   - calendar_entries  channel-level + video-level
module ChannelRevokeCounts
  Counts = Struct.new(
    :videos,
    :analytics,
    :diffs,
    :change_logs,
    :links,
    :rejected_imports,
    :calendar_entries,
    keyword_init: true
  ) do
    def to_h
      members.index_with { |key| self[key] }
    end
  end

  # Tables indexed by their FK columns. Each entry maps the analytics
  # category to the AR model + the FK column it references on the
  # parent (channel or video). Enumerated explicitly so a new analytics
  # table forgotten in the count sweep fails an audit rather than
  # silently zeroing.
  CHANNEL_ANALYTICS_MODELS = [
    ChannelDaily,
    ChannelWindowSummary,
    TopVideosWindow
  ].freeze

  VIDEO_ANALYTICS_MODELS = [
    VideoDaily,
    VideoDailyByCountry,
    VideoDailyByDeviceType,
    VideoDailyByOperatingSystem,
    VideoDailyByTrafficSource,
    VideoDailyBySubscribedStatus,
    VideoDailyByAgeGroupGender,
    VideoWindowSummary,
    VideoRetention
  ].freeze

  module_function

  def for(channel)
    channel_id = channel.id
    video_ids = Video.where(channel_id: channel_id).pluck(:id)
    videos_count = video_ids.length

    analytics_count = 0
    CHANNEL_ANALYTICS_MODELS.each do |klass|
      analytics_count += klass.where(channel_id: channel_id).count
    end
    if video_ids.any?
      VIDEO_ANALYTICS_MODELS.each do |klass|
        analytics_count += klass.where(video_id: video_ids).count
      end
    end

    diffs_count = ChannelDiff.where(channel_id: channel_id).count
    diffs_count += VideoDiff.where(video_id: video_ids).count if video_ids.any?

    change_logs_count = ChannelChangeLog.where(channel_id: channel_id).count
    change_logs_count += VideoChangeLog.where(video_id: video_ids).count if video_ids.any?

    links_count = video_ids.any? ? VideoGameLink.where(video_id: video_ids).count : 0

    rejected_imports_count = RejectedVideoImport.where(channel_id: channel_id).count

    calendar_entries_count = CalendarEntry.where(channel_id: channel_id).count
    if video_ids.any?
      calendar_entries_count += CalendarEntry.where(video_id: video_ids).count
    end

    Counts.new(
      videos: videos_count,
      analytics: analytics_count,
      diffs: diffs_count,
      change_logs: change_logs_count,
      links: links_count,
      rejected_imports: rejected_imports_count,
      calendar_entries: calendar_entries_count
    )
  end

  # Aggregate counts across N channels. Sums every category. Useful for
  # the bulk-revoke modal on /channels — the user sees one summed total
  # per category, not per-channel rows.
  def for_many(channels)
    blank = Counts.new(
      videos: 0, analytics: 0, diffs: 0, change_logs: 0, links: 0,
      rejected_imports: 0, calendar_entries: 0
    )

    channels.reduce(blank) do |acc, channel|
      counts = self.for(channel)
      Counts.new(
        videos: acc.videos + counts.videos,
        analytics: acc.analytics + counts.analytics,
        diffs: acc.diffs + counts.diffs,
        change_logs: acc.change_logs + counts.change_logs,
        links: acc.links + counts.links,
        rejected_imports: acc.rejected_imports + counts.rejected_imports,
        calendar_entries: acc.calendar_entries + counts.calendar_entries
      )
    end
  end
end
