# frozen_string_literal: true

# Imports all videos from a YouTube channel into the local Video table.
# Part of the multi-stage /connect flow (stage 2).
#
# Flow:
#   1. Get channel's uploads playlist ID
#   2. Page through playlistItems.list to collect video IDs
#   3. Batch videos.list (50 at a time) to get full details
#   4. Upsert into DB
#   5. Emit enhanced #2 with video breakdown KV-table
#   6. Resolve thinking #2
#   7. Complete turn (broadcasts pito:done — dots hide)
class ImportVideosJob < ApplicationJob
  queue_as :default

  # Max videos.list batch size per YouTube API
  BATCH_SIZE = 50

  def perform(connection_id, turn_id)
    connection = YoutubeConnection.find_by(id: connection_id)
    turn       = Turn.find_by(id: turn_id)

    return unless connection && turn
    return if turn.completed_at.present?

    conversation = turn.conversation
    broadcaster  = Pito::Stream::Broadcaster.new(conversation:)

    channels = Channel.where(youtube_connection_id: connection.id)
    total_imported = 0

    channels.each do |channel|
      imported = import_channel_videos(channel)
      total_imported += imported
    end

    # P4 — linked videos' view counts may have changed; refresh the
    # materialized `views` stat on every affected game.
    enqueue_game_stats_refreshes(channels)

    # Emit enhanced #2 with video breakdown
    broadcaster.emit(
      turn:,
      kind:    :enhanced,
      payload: {
        body: breakdown_text(channels),
        html: true
      }
    )

    # Resolve thinking #2
    broadcaster.resolve_thinking(turn:)

    # Complete turn — dots hide on pito:done
    broadcaster.complete_turn(turn:)
  rescue StandardError => e
    handle_error(turn, e)
    raise
  end

  private

  def handle_error(turn, error)
    return unless turn

    conversation = turn.conversation
    broadcaster = Pito::Stream::Broadcaster.new(conversation:)
    broadcaster.emit(
      turn:,
      kind:    :error,
      payload: {
        text:   Pito::Copy.render("pito.copy.errors.dispatch_failed"),
        detail: error.message
      }
    )
    broadcaster.resolve_thinking(turn:)
    broadcaster.complete_turn(turn:)
  end

  def enqueue_game_stats_refreshes(channels)
    game_ids = VideoGameLink
      .joins(:video)
      .where(videos: { channel_id: channels.pluck(:id) })
      .distinct
      .pluck(:game_id)

    game_ids.each { |id| GameStatsRefreshJob.perform_later(id) }
  end

  def import_channel_videos(channel)
    connection = channel.youtube_connection
    return 0 unless connection

    client = Channel::Youtube::Client.new(connection)

    playlist_id = fetch_uploads_playlist_id(client, channel)
    return 0 unless playlist_id

    video_ids = fetch_playlist_video_ids(client, playlist_id)
    return 0 if video_ids.empty?

    imported = 0
    video_ids.each_slice(BATCH_SIZE) do |batch|
      videos = fetch_video_details(client, batch)
      videos.each { |v| upsert_video(v, channel) }
      imported += videos.count
    end

    channel.touch(:last_synced_at)
    imported
  end

  def breakdown_text(channels)
    # Aggregate counts across all channels for this connection
    videos = Video.where(channel_id: channels.pluck(:id))

    total     = videos.count
    published = videos.where(privacy_status: :public).count
    unlisted  = videos.where(privacy_status: :unlisted).count
    scheduled = videos.where(privacy_status: :private).where("publish_at > ?", Time.current).count
    drafts    = total - published - unlisted - scheduled

    # Build KV rows
    rows = [
      { key: I18n.t("pito.jobs.import_videos.breakdown.videos_total"), bold: true,  value: total.to_s },
      { key: I18n.t("pito.jobs.import_videos.breakdown.published"),    bold: false, value: published.to_s },
      { key: I18n.t("pito.jobs.import_videos.breakdown.scheduled"),    bold: false, value: scheduled.to_s },
      { key: I18n.t("pito.jobs.import_videos.breakdown.unlisted"),     bold: false, value: unlisted.to_s },
      { key: I18n.t("pito.jobs.import_videos.breakdown.drafts"),       bold: false, value: drafts.to_s }
    ]

    # Render as compact key/value lines
    lines = rows.map do |row|
      key_class = row[:bold] ? "text-fg font-bold" : "text-cyan"
      %(<div class="flex gap-2"><span class="#{key_class} w-32">#{row[:key]}</span><span class="text-fg">#{row[:value]}</span></div>)
    end

    lines.join
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
  end

  def fetch_video_details(client, ids)
    return [] if ids.empty?

    response = client.videos_list(
      ids: ids,
      parts: %i[snippet statistics contentDetails status]
    )

    Array(response[:items]).map { |item| normalize_video(item) }
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
      category_id:      snippet[:category_id],
      etag:             item[:etag]
    }
  end

  def upsert_video(attrs, channel)
    return if attrs[:youtube_video_id].blank?

    # P4 — view_count moved off the videos column onto the polymorphic
    # `stats` table; pull it out of the AR attrs and persist via the facade.
    views = attrs.delete(:view_count)
    # Thumbnails are cached as OUR ActiveStorage copy (not a column) — pull the
    # source URL out of the AR attrs and ingest it off the import path.
    thumb_url = attrs.delete(:thumbnail_url)

    video = Video.find_or_initialize_by(youtube_video_id: attrs[:youtube_video_id])
    video.channel = channel
    video.assign_attributes(attrs)
    video.last_synced_at = Time.current
    video.save!

    Pito::Stats.set(video, :views, views)
    VideoThumbnailJob.perform_later(video.id, thumb_url) if thumb_url.present?

    # P9.5 — (re)embed the video when it's new or an embedded field changed.
    # `Video::VoyageIndexer` is digest-gated, and `VideoVoyageIndexJob` only
    # refreshes the channel centroid when the video actually re-embeds, so an
    # unchanged re-import enqueues nothing wasteful here.
    if video.previously_new_record? || video.saved_changes.keys.intersect?(EMBED_FIELDS)
      VideoVoyageIndexJob.perform_later(video.id)
    end
  end

  # Video fields that feed `Video::EmbedText` — a change to any of these is the
  # only reason to re-embed (and thus recompute the channel centroid).
  EMBED_FIELDS = %w[title description tags category_id].freeze

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
