# frozen_string_literal: true

# P14 — Turn-less nightly video import for a single channel.
#
# `ImportVideosJob` is turn-coupled (connection_id + turn_id) and broadcasts
# chat stream events — NOT suitable for a cron run. This thin job extracts
# the pure data path: fetch the channel's upload playlist → batch-upsert
# videos → enqueue `VideoVoyageIndexJob` per created/changed video →
# enqueue `GameStatsRefreshJob` for linked games.
#
# No broadcaster, no turn. Errors for one channel are rescued + logged so a
# single API failure never aborts the nightly fan-out.
#
# Enqueued by: `NightlySyncJob` (one per connected channel).
class NightlyVideoSyncJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 50

  # Fields that change the embed text; mirrors `ImportVideosJob::EMBED_FIELDS`.
  EMBED_FIELDS = %w[title description tags category_id].freeze

  def perform(channel_id)
    channel = ::Channel.find_by(id: channel_id)
    return unless channel
    return if channel.youtube_connection_id.nil?

    connection = channel.youtube_connection
    return if connection.needs_reauth?

    client = ::Channel::Youtube::Client.new(connection)

    playlist_id = fetch_uploads_playlist_id(client, channel)
    return unless playlist_id

    video_ids = fetch_playlist_video_ids(client, playlist_id)
    return if video_ids.empty?

    video_ids.each_slice(BATCH_SIZE) do |batch|
      videos = fetch_video_details(client, batch)
      videos.each { |attrs| upsert_video(attrs, channel) }
    end

    channel.touch(:last_synced_at)

    enqueue_game_stats_refreshes(channel)
  rescue StandardError => e
    Rails.logger.error(
      "NightlyVideoSyncJob: failed for channel=#{channel_id}: " \
      "#{e.class}: #{e.message}"
    )
  end

  private

  def enqueue_game_stats_refreshes(channel)
    game_ids = ::VideoGameLink
      .joins(:video)
      .where(videos: { channel_id: channel.id })
      .distinct
      .pluck(:game_id)

    game_ids.each { |id| ::GameStatsRefreshJob.perform_later(id) }
  end

  def upsert_video(attrs, channel)
    return if attrs[:youtube_video_id].blank?

    views    = attrs.delete(:view_count)
    likes    = attrs.delete(:like_count)
    comments = attrs.delete(:comment_count)
    # Thumbnails are cached as OUR ActiveStorage copy (not a column).
    thumb_url = attrs.delete(:thumbnail_url)

    video = ::Video.find_or_initialize_by(youtube_video_id: attrs[:youtube_video_id])
    video.channel = channel
    video.assign_attributes(attrs)
    video.last_synced_at = Time.current
    video.save!

    ::Pito::Stats.set(video, :views, views)
    ::Pito::Stats.set(video, :likes, likes)
    ::Pito::Stats.set(video, :comments, comments)
    ::VideoThumbnailJob.perform_later(video.id, thumb_url) if thumb_url.present?

    if video.previously_new_record? || video.saved_changes.keys.intersect?(EMBED_FIELDS)
      ::VideoVoyageIndexJob.perform_later(video.id)
    end
  rescue StandardError => e
    Rails.logger.error(
      "NightlyVideoSyncJob: failed to upsert video " \
      "#{attrs[:youtube_video_id]} for channel=#{channel.id}: #{e.class}: #{e.message}"
    )
  end

  def fetch_uploads_playlist_id(client, channel)
    response = client.channels_list(
      ids: [ channel.youtube_channel_id ],
      parts: %i[contentDetails]
    )
    item = response[:items]&.first
    return nil unless item

    content_details = item[:content_details] || {}
    related = content_details[:related_playlists] || {}
    related[:uploads]
  rescue StandardError
    nil
  end

  def fetch_playlist_video_ids(client, playlist_id)
    ids = []
    page_token = nil

    loop do
      response = client.playlist_items_list(
        playlist_id: playlist_id,
        parts: %i[snippet],
        max_results: 50,
        page_token: page_token
      )

      items = Array(response[:items])
      items.each do |item|
        snippet = item[:snippet] || {}
        video_id = snippet[:resource_id]&.dig(:video_id) || snippet[:video_id]
        ids << video_id if video_id.present?
      end

      page_token = response[:next_page_token]
      break if page_token.blank?
    end

    ids
  rescue StandardError
    []
  end

  def fetch_video_details(client, ids)
    return [] if ids.empty?

    response = client.videos_list(
      ids: ids,
      parts: %i[snippet statistics contentDetails status]
    )

    Array(response[:items]).map { |item| normalize_video(item) }
  rescue StandardError
    []
  end

  def normalize_video(item)
    snippet = item[:snippet] || {}
    stats   = item[:statistics] || {}
    details = item[:content_details] || {}
    status  = item[:status] || {}
    thumbs  = snippet[:thumbnails] || {}
    high    = thumbs[:high] || thumbs[:default] || {}

    {
      youtube_video_id: item[:id],
      title:            snippet[:title],
      description:      snippet[:description],
      published_at:     parse_time(snippet[:published_at]),
      privacy_status:   map_privacy(status[:privacy_status]),
      publish_at:       parse_time(status[:publish_at]),
      duration_seconds: parse_duration(details[:duration]),
      view_count:       stats[:view_count]&.to_i || 0,
      like_count:       stats[:like_count]&.to_i || 0,
      comment_count:    stats[:comment_count]&.to_i || 0,
      thumbnail_url:    high[:url],
      tags:             Array(snippet[:tags]),
      category_id:      snippet[:category_id]
    }
  end

  def map_privacy(status)
    case status.to_s.downcase
    when "public"   then :public
    when "unlisted" then :unlisted
    else :private
    end
  end

  def parse_time(value)
    return nil if value.blank?
    return value.to_time if value.respond_to?(:to_time)
    Time.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def parse_duration(iso8601)
    return nil if iso8601.blank?

    match = iso8601.to_s.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/)
    return nil unless match

    hours = match[1].to_i
    mins  = match[2].to_i
    secs  = match[3].to_i
    (hours * 3600) + (mins * 60) + secs
  rescue StandardError
    nil
  end
end
