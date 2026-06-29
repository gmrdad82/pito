# frozen_string_literal: true

# Chat-initiated YouTube sync for a single video.
#
# Fetches the video's YouTube fields (`snippet statistics contentDetails status`)
# via `Channel::Youtube::Client#videos_list`, updates changed columns, refreshes
# `Pito::Stats` (views/likes/comments), runs a digest-gated Voyage reindex, then
# broadcasts ONE Standard summary message to the conversation.
#
# YouTube read path: `Channel::Youtube::Client#videos_list` with
# parts: snippet + statistics + contentDetails + status — exactly what
# `NightlyVideoSyncJob#fetch_video_details` uses. We reuse the same normalization
# logic inline (no duplication of API code).
class SyncVideoJob < ApplicationJob
  queue_as :default

  EMBED_FIELDS = %w[title description tags category_id].freeze

  def perform(video_id, conversation_id: nil)
    video = ::Video.find_by(id: video_id)
    return unless video

    connection = video.channel&.youtube_connection
    return unless connection
    return if connection.needs_reauth?

    broadcaster = nil
    turn        = nil

    if conversation_id.present?
      conversation = ::Conversation.find_by(id: conversation_id)
      if conversation
        broadcaster = Pito::Stream::Broadcaster.new(conversation:)
        turn = conversation.turns.create!(
          position:   Turn.next_position_for(conversation),
          input_kind: :slash,
          input_text: "/sync video #{video.title}".strip
        )
        broadcaster.emit_thinking(turn:, dictionary: :syncing)
      end
    end

    client = ::Channel::Youtube::Client.new(connection)
    items  = fetch_video_details(client, [ video.youtube_video_id ])
    if items.any?
      attrs = items.first
      upsert_video(attrs, video)
    end

    return unless turn

    video.reload
    intro = Pito::Copy.render_html(
      "pito.copy.sync.intro",
      { subject: video.title },
      shimmer: [ :subject ]
    )
    broadcaster.emit(turn:, kind: :system, payload: { "body" => intro, "html" => true })
    broadcaster.resolve_thinking(turn:)
    broadcaster.complete_turn(turn:)
  rescue StandardError => e
    Rails.logger.error("[SyncVideoJob] failed for video=#{video_id}: #{e.class}: #{e.message}")
    if turn && broadcaster
      broadcaster.resolve_thinking(turn:)
      broadcaster.complete_turn(turn:)
    end
  end

  private

  def fetch_video_details(client, ids)
    return [] if ids.empty?

    response = client.videos_list(
      ids:   ids,
      parts: %i[snippet statistics contentDetails status]
    )
    Array(response[:items]).map { |item| normalize_video(item) }
  rescue StandardError
    []
  end

  def upsert_video(attrs, video)
    views    = attrs.delete(:view_count)
    likes    = attrs.delete(:like_count)
    comments = attrs.delete(:comment_count)
    attrs.delete(:thumbnail_url) # thumbnails managed by VideoThumbnailJob

    video.assign_attributes(attrs.except(:youtube_video_id))
    video.last_synced_at = Time.current
    video.save!

    ::Pito::Stats.set(video, :views,    views)
    ::Pito::Stats.set(video, :likes,    likes)
    ::Pito::Stats.set(video, :comments, comments)

    if video.saved_changes.keys.intersect?(EMBED_FIELDS)
      ::VideoVoyageIndexJob.perform_later(video.id)
    end
  rescue StandardError => e
    Rails.logger.error("[SyncVideoJob] upsert failed for video=#{video.id}: #{e.class}: #{e.message}")
  end

  def normalize_video(item)
    snippet = item[:snippet] || {}
    stats   = item[:statistics] || {}
    details = item[:content_details] || {}
    status  = item[:status] || {}

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
      thumbnail_url:    nil, # not used by this path
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
    (match[1].to_i * 3600) + (match[2].to_i * 60) + match[3].to_i
  rescue StandardError
    nil
  end
end
