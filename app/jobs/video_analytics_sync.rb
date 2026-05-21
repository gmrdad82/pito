# Phase 13.2 — Analytics sync engine. Per-video job. Active videos
# (per `Channel::Youtube::ActiveVideoClassifier`) run V1, V2 (×4 windows), V3,
# V4 device + OS, V5, V6, V8 — eight API calls. Inactive videos run
# V1 only.
#
# Idempotent via the analytics tables' UNIQUE indexes — `upsert_all`
# resolves conflicts by overwriting.
class VideoAnalyticsSync
  include Sidekiq::Job
  sidekiq_options queue: "analytics", retry: 5

  REFRESH_DAYS = 3
  WINDOWS = Channel::Youtube::AnalyticsQueryBuilder::WINDOWS

  def perform(video_id)
    video = Video.find_by(id: video_id)
    return unless video

    channel = video.channel
    return if channel.nil?

    connection = channel.youtube_connection
    return if connection.nil? || connection.needs_reauth?

    client = Channel::Youtube::AnalyticsClient.new(connection: connection)
    today = client.today_pt
    from = today - REFRESH_DAYS
    to = today - 1
    active = Channel::Youtube::ActiveVideoClassifier.active?(video)

    sync_video_daily(client, video, from: from, to: to)
    return if connection.reload.needs_reauth?
    return unless active

    WINDOWS.each do |window|
      sync_video_window_summary(client, video, window: window, today: today)
      return if connection.reload.needs_reauth?
    end

    sync_video_by_country(client, video, from: from, to: to)
    return if connection.reload.needs_reauth?

    sync_video_by_device_type(client, video, from: from, to: to)
    return if connection.reload.needs_reauth?

    sync_video_by_operating_system(client, video, from: from, to: to)
    return if connection.reload.needs_reauth?

    sync_video_by_traffic_source(client, video, from: from, to: to)
    return if connection.reload.needs_reauth?

    sync_video_by_subscribed_status(client, video, from: from, to: to)
    return if connection.reload.needs_reauth?

    sync_video_demographics(client, video, from: from, to: to)
  rescue Channel::Youtube::AnalyticsClient::AuthError
    Rails.logger.warn(
      "[analytics-sync] video #{video_id} skipped — connection #{connection&.id} needs reauth"
    )
    nil
  end

  private

  def sync_video_daily(client, video, from:, to:)
    response = client.video_daily(video: video, from: from, to: to)
    rows = parse_daily_rows(response, video: video)
    return if rows.empty?

    VideoDaily.upsert_all(rows, unique_by: %i[video_id date])
  end

  def sync_video_window_summary(client, video, window:, today:)
    response = client.video_window_summary(video: video, window: window, today: today)
    rows = parse_window_summary_rows(response, video: video, window: window, today: today)
    return if rows.empty?

    VideoWindowSummary.upsert_all(rows, unique_by: %i[video_id window])
  end

  def sync_video_by_country(client, video, from:, to:)
    response = client.video_by_country(video: video, from: from, to: to)
    headers = header_names(response[:column_headers])
    rows = response[:rows].filter_map do |row|
      pairs = headers.zip(row).to_h
      country = pairs["country"].to_s
      next if country.blank?

      {
        video_id: video.id,
        date: from,
        country_code: country,
        views: int_or_zero(pairs["views"]),
        estimated_minutes_watched: int_or_zero(pairs["estimatedMinutesWatched"]),
        average_view_duration: dec_or_nil(pairs["averageViewDuration"]),
        average_view_percentage: dec_or_nil(pairs["averageViewPercentage"]),
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    return if rows.empty?

    VideoDailyByCountry.upsert_all(rows, unique_by: %i[video_id date country_code])
  end

  def sync_video_by_device_type(client, video, from:, to:)
    response = client.video_by_device_type(video: video, from: from, to: to)
    headers = header_names(response[:column_headers])
    rows = response[:rows].filter_map do |row|
      pairs = headers.zip(row).to_h
      device = pairs["deviceType"].to_s
      next if device.blank?

      {
        video_id: video.id,
        date: from,
        device_type: device,
        views: int_or_zero(pairs["views"]),
        estimated_minutes_watched: int_or_zero(pairs["estimatedMinutesWatched"]),
        average_view_duration: dec_or_nil(pairs["averageViewDuration"]),
        average_view_percentage: dec_or_nil(pairs["averageViewPercentage"]),
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    return if rows.empty?

    VideoDailyByDeviceType.upsert_all(rows, unique_by: %i[video_id date device_type])
  end

  def sync_video_by_operating_system(client, video, from:, to:)
    response = client.video_by_operating_system(video: video, from: from, to: to)
    headers = header_names(response[:column_headers])
    rows = response[:rows].filter_map do |row|
      pairs = headers.zip(row).to_h
      os = pairs["operatingSystem"].to_s
      next if os.blank?

      {
        video_id: video.id,
        date: from,
        operating_system: os,
        views: int_or_zero(pairs["views"]),
        estimated_minutes_watched: int_or_zero(pairs["estimatedMinutesWatched"]),
        average_view_duration: dec_or_nil(pairs["averageViewDuration"]),
        average_view_percentage: dec_or_nil(pairs["averageViewPercentage"]),
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    return if rows.empty?

    VideoDailyByOperatingSystem.upsert_all(rows, unique_by: %i[video_id date operating_system])
  end

  def sync_video_by_traffic_source(client, video, from:, to:)
    response = client.video_by_traffic_source(video: video, from: from, to: to)
    headers = header_names(response[:column_headers])
    rows = response[:rows].filter_map do |row|
      pairs = headers.zip(row).to_h
      source = pairs["insightTrafficSourceType"].to_s
      next if source.blank?

      {
        video_id: video.id,
        date: from,
        traffic_source_type: source,
        views: int_or_zero(pairs["views"]),
        estimated_minutes_watched: int_or_zero(pairs["estimatedMinutesWatched"]),
        video_thumbnail_impressions: int_or_zero(pairs["videoThumbnailImpressions"]),
        video_thumbnail_impressions_click_rate: dec_or_nil(pairs["videoThumbnailImpressionsClickRate"]),
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    return if rows.empty?

    VideoDailyByTrafficSource.upsert_all(rows, unique_by: %i[video_id date traffic_source_type])
  end

  def sync_video_by_subscribed_status(client, video, from:, to:)
    response = client.video_by_subscribed_status(video: video, from: from, to: to)
    headers = header_names(response[:column_headers])
    rows = response[:rows].filter_map do |row|
      pairs = headers.zip(row).to_h
      status = pairs["subscribedStatus"].to_s
      next if status.blank?

      {
        video_id: video.id,
        date: from,
        subscribed_status: status,
        views: int_or_zero(pairs["views"]),
        estimated_minutes_watched: int_or_zero(pairs["estimatedMinutesWatched"]),
        average_view_percentage: dec_or_nil(pairs["averageViewPercentage"]),
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    return if rows.empty?

    VideoDailyBySubscribedStatus.upsert_all(rows, unique_by: %i[video_id date subscribed_status])
  end

  def sync_video_demographics(client, video, from:, to:)
    response = client.video_demographics(video: video, from: from, to: to)
    headers = header_names(response[:column_headers])
    rows = response[:rows].filter_map do |row|
      pairs = headers.zip(row).to_h
      age = pairs["ageGroup"].to_s
      gender = pairs["gender"].to_s
      next if age.blank? || gender.blank?

      {
        video_id: video.id,
        date: from,
        age_group: age,
        gender: gender,
        viewer_percentage: dec_or_nil(pairs["viewerPercentage"]) || 0,
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    return if rows.empty?

    VideoDailyByAgeGroupGender.upsert_all(rows, unique_by: %i[video_id date age_group gender])
  end

  def parse_daily_rows(response, video:)
    headers = header_names(response[:column_headers])
    response[:rows].filter_map do |row|
      pairs = headers.zip(row).to_h
      next unless pairs["day"]

      base = {
        video_id: video.id,
        date: Date.parse(pairs["day"].to_s),
        created_at: Time.current,
        updated_at: Time.current
      }
      base.merge(metric_attributes(pairs))
    end
  end

  def parse_window_summary_rows(response, video:, window:, today:)
    return [] if response[:rows].empty?

    pairs = header_names(response[:column_headers]).zip(response[:rows].first).to_h
    from, to = Channel::Youtube::AnalyticsQueryBuilder.window_range(window, today)
    [
      {
        video_id: video.id,
        window: window,
        window_start: from,
        window_end: to,
        created_at: Time.current,
        updated_at: Time.current
      }.merge(metric_attributes(pairs)).merge(window_ratio_attributes(pairs))
    ]
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
