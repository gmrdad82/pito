# Phase 13.2 — Analytics sync engine. Per-channel job. Runs C1, C2
# (×4 windows), C3 (×4 windows). C4 / C5 are deferred (NotImplemented
# stubs in `Channel::Youtube::AnalyticsClient`).
#
# Idempotent via the analytics tables' UNIQUE (composite-key) indexes
# — `upsert_all` resolves conflicts by overwriting the existing row.
#
# Auth failure: when the connection's `needs_reauth` flips during the
# job (or was already flipped by a sibling job for the same
# connection), the job exits cleanly. Other channels' jobs run
# independently.
class ChannelAnalyticsSync < ApplicationJob
  queue_as :analytics

  REFRESH_DAYS = 3
  WINDOWS = Channel::Youtube::AnalyticsQueryBuilder::WINDOWS

  def perform(channel_id)
    channel = Channel.find_by(id: channel_id)
    return unless channel

    connection = channel.youtube_connection
    return if connection.nil? || connection.needs_reauth?

    client = Channel::Youtube::AnalyticsClient.new(connection: connection)
    today = client.today_pt
    from = today - REFRESH_DAYS
    to = today - 1

    sync_channel_daily(client, channel, from: from, to: to)
    return if connection.reload.needs_reauth?

    WINDOWS.each do |window|
      sync_channel_window_summary(client, channel, window: window, today: today)
      return if connection.reload.needs_reauth?

      sync_top_videos(client, channel, window: window, today: today)
      return if connection.reload.needs_reauth?
    end
  rescue Channel::Youtube::AnalyticsClient::AuthError
    # Audit row already written; connection.needs_reauth flipped.
    Rails.logger.warn(
      "[analytics-sync] channel #{channel_id} skipped — connection #{connection&.id} needs reauth"
    )
    nil
  end

  private

  def sync_channel_daily(client, channel, from:, to:)
    response = client.channel_daily(channel: channel, from: from, to: to)
    rows = parse_daily_rows(response, channel: channel)
    return if rows.empty?

    ChannelDaily.upsert_all(rows, unique_by: %i[channel_id date])
  end

  def sync_channel_window_summary(client, channel, window:, today:)
    response = client.channel_window_summary(channel: channel, window: window, today: today)
    rows = parse_window_summary_rows(response, channel: channel, window: window, today: today)
    return if rows.empty?

    ChannelWindowSummary.upsert_all(rows, unique_by: %i[channel_id window])
  end

  def sync_top_videos(client, channel, window:, today:)
    response = client.top_videos(channel: channel, window: window, today: today)
    rows = parse_top_videos_rows(response, channel: channel, window: window)

    if rows.empty?
      TopVideosWindow.where(channel_id: channel.id, window: window).delete_all
      return
    end

    TopVideosWindow.transaction do
      TopVideosWindow.where(channel_id: channel.id, window: window).delete_all
      TopVideosWindow.upsert_all(rows, unique_by: %i[channel_id window video_id])
    end
  end

  def parse_daily_rows(response, channel:)
    headers = header_names(response[:column_headers])
    response[:rows].filter_map do |row|
      pairs = headers.zip(row).to_h
      next unless pairs["day"]

      base = {
        channel_id: channel.id,
        date: Date.parse(pairs["day"].to_s),
        created_at: Time.current,
        updated_at: Time.current
      }
      base.merge(metric_attributes(pairs))
    end
  end

  def parse_window_summary_rows(response, channel:, window:, today:)
    return [] if response[:rows].empty?

    pairs = header_names(response[:column_headers]).zip(response[:rows].first).to_h
    from, to = Channel::Youtube::AnalyticsQueryBuilder.window_range(window, today)
    [
      {
        channel_id: channel.id,
        window: window,
        window_start: from,
        window_end: to,
        created_at: Time.current,
        updated_at: Time.current
      }.merge(metric_attributes(pairs)).merge(window_ratio_attributes(pairs))
    ]
  end

  def parse_top_videos_rows(response, channel:, window:)
    headers = header_names(response[:column_headers])

    response[:rows].each_with_index.filter_map do |row, idx|
      pairs = headers.zip(row).to_h
      youtube_video_id = pairs["video"].to_s
      next if youtube_video_id.blank?

      video = Video.find_by(youtube_video_id: youtube_video_id, channel_id: channel.id)
      next unless video

      {
        channel_id: channel.id,
        video_id: video.id,
        window: window,
        rank: idx + 1,
        views: int_or_zero(pairs["views"]),
        estimated_minutes_watched: int_or_zero(pairs["estimatedMinutesWatched"]),
        average_view_duration: dec_or_nil(pairs["averageViewDuration"]),
        average_view_percentage: dec_or_nil(pairs["averageViewPercentage"]),
        subscribers_gained: int_or_zero(pairs["subscribersGained"]),
        likes: int_or_zero(pairs["likes"]),
        comments: int_or_zero(pairs["comments"]),
        created_at: Time.current,
        updated_at: Time.current
      }
    end
  end

  def metric_attributes(pairs)
    {
      views: int_or_zero(pairs["views"]),
      estimated_minutes_watched: int_or_zero(pairs["estimatedMinutesWatched"]),
      estimated_red_minutes_watched: int_or_zero(pairs["estimatedRedMinutesWatched"]),
      average_view_duration: dec_or_nil(pairs["averageViewDuration"]),
      likes: int_or_zero(pairs["likes"]),
      dislikes: int_or_zero(pairs["dislikes"]),
      comments: int_or_zero(pairs["comments"]),
      shares: int_or_zero(pairs["shares"]),
      subscribers_gained: int_or_zero(pairs["subscribersGained"]),
      subscribers_lost: int_or_zero(pairs["subscribersLost"]),
      videos_added_to_playlists: int_or_zero(pairs["videosAddedToPlaylists"]),
      videos_removed_from_playlists: int_or_zero(pairs["videosRemovedFromPlaylists"]),
      video_thumbnail_impressions: int_or_zero(pairs["videoThumbnailImpressions"]),
      card_impressions: int_or_zero(pairs["cardImpressions"]),
      card_clicks: int_or_zero(pairs["cardClicks"]),
      card_teaser_impressions: int_or_zero(pairs["cardTeaserImpressions"]),
      card_teaser_clicks: int_or_zero(pairs["cardTeaserClicks"]),
      engaged_views: int_or_zero(pairs["engagedViews"]),
      red_views: int_or_zero(pairs["redViews"]),
      estimated_revenue: dec_or_nil(pairs["estimatedRevenue"]),
      estimated_ad_revenue: dec_or_nil(pairs["estimatedAdRevenue"]),
      estimated_red_partner_revenue: dec_or_nil(pairs["estimatedRedPartnerRevenue"]),
      gross_revenue: dec_or_nil(pairs["grossRevenue"]),
      ad_impressions: int_or_nil(pairs["adImpressions"]),
      monetized_playbacks: int_or_nil(pairs["monetizedPlaybacks"])
    }
  end

  def window_ratio_attributes(pairs)
    {
      average_view_percentage: dec_or_nil(pairs["averageViewPercentage"]),
      video_thumbnail_impressions_click_rate: dec_or_nil(pairs["videoThumbnailImpressionsClickRate"]),
      card_click_rate: dec_or_nil(pairs["cardClickRate"]),
      card_teaser_click_rate: dec_or_nil(pairs["cardTeaserClickRate"]),
      cpm: dec_or_nil(pairs["cpm"]),
      playback_based_cpm: dec_or_nil(pairs["playbackBasedCpm"])
    }
  end

  def header_names(headers)
    Array(headers).map { |h| h.is_a?(Hash) ? h[:name].to_s : h.to_s }
  end

  def int_or_zero(value)
    value.nil? ? 0 : value.to_i
  end

  def int_or_nil(value)
    value.nil? ? nil : value.to_i
  end

  def dec_or_nil(value)
    value.nil? ? nil : BigDecimal(value.to_s)
  end
end
