# frozen_string_literal: true

# Background job that fetches channel statistics from YouTube
# after a successful OAuth connection. Part of the multi-stage /connect flow.
#
# Flow:
#   1. OAuth callback links channels, emits "connected" system event
#   2. This job fetches fresh channel stats
#   3. Emits enhanced #1 with subscriber/view counts
#   4. Resolves thinking #1
#   5. Emits thinking #2
#   6. Enqueues ImportVideosJob for stage 2
class ChannelInfoJob < ApplicationJob
  queue_as :default

  def perform(connection_id, turn_id)
    connection = YoutubeConnection.find_by(id: connection_id)
    turn       = Turn.find_by(id: turn_id)

    return unless connection && turn
    return if turn.completed_at.present?

    conversation = turn.conversation
    broadcaster  = Pito::Stream::Broadcaster.new(conversation:)

    # Fetch stats for all channels under this connection
    channels = Channel.where(youtube_connection_id: connection.id)
    stats    = fetch_stats(connection, channels)

    # Emit enhanced #1 with channel stats
    if stats.any?
      broadcaster.emit(
        turn:,
        kind:    :enhanced,
        payload: {
          body: stats_text(stats),
          html: true
        }
      )
    end

    # Resolve thinking #1 (elapsed computed from the thinking's own started_at)
    broadcaster.resolve_thinking(turn:)

    if stats.any? && stats.all? { |s| s[:error] }
      # All channels failed — complete the turn, no point in stage 2
      broadcaster.complete_turn(turn:)
    else
      # Emit thinking #2 for video import stage
      broadcaster.emit_thinking(turn:, dictionary: :importing)

      # Enqueue stage 2: video import
      ImportVideosJob.perform_later(connection_id, turn_id)
    end
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

  def fetch_stats(connection, channels)
    client = Channel::Youtube::Client.new(connection)
    stats  = []

    channels.each do |channel|
      begin
        response = client.channels_list(
          ids: [ channel.youtube_channel_id ],
          parts: %i[snippet statistics brandingSettings contentDetails status]
        )

        item = response[:items]&.first
        next unless item

        normalized = normalize_channel_item(item)

        channel.update_columns(
          title:            normalized[:title],
          handle:           normalized[:handle],
          description:      normalized[:description],
          avatar_url:       normalized[:avatar_url],
          banner_url:       normalized[:banner_url],
          video_count:      normalized[:video_count],
          last_synced_at:   Time.current
        )
        Pito::Stats.set(channel, :subscribers, normalized[:subscriber_count])
        Pito::Stats.set(channel, :views, normalized[:view_count])

        stats << {
          title:         normalized[:title] || channel.title,
          handle:        normalized[:handle] || channel.handle,
          subscribers:   normalized[:subscriber_count],
          views:         normalized[:view_count],
          videos:        normalized[:video_count]
        }
      rescue Channel::Youtube::QuotaExhaustedError,
             Channel::Youtube::NeedsReauthError,
             Channel::Youtube::TransientError => e
        stats << {
          title:   channel.title,
          handle:  channel.handle,
          error:   e.message
        }
      end
    end

    stats
  end

  def normalize_channel_item(item)
    return {} if item.nil?

    snippet  = item[:snippet]            || {}
    stats    = item[:statistics]         || {}
    branding = item[:branding_settings]  || {}
    branding_image   = branding[:image]   || {}
    thumbnails = snippet[:thumbnails] || {}
    default_thumb = thumbnails[:default] || {}

    {
      title: snippet[:title],
      handle: snippet[:custom_url],
      description: snippet[:description],
      avatar_url: default_thumb[:url],
      banner_url: branding_image[:banner_external_url],
      subscriber_count: stats[:subscriber_count]&.to_i,
      view_count: stats[:view_count]&.to_i,
      video_count: stats[:video_count]&.to_i
    }
  end

  def stats_text(stats)
    parts = stats.map do |s|
      if s[:error]
        %(#{channel_label(s)} — <span class="text-fg-dim">#{s[:error]}</span>)
      else
        subs = format_number(s[:subscribers])
        views = format_number(s[:views])
        %(#{channel_label(s)}<br><span class="text-fg-dim">Subscribers:</span> <span class="text-cyan">#{subs}</span> · <span class="text-fg-dim">Views:</span> <span class="text-cyan">#{views}</span>)
      end
    end

    parts.join("<br><br>")
  end

  def channel_label(s)
    title = s[:title].to_s.presence || "Channel"
    handle = s[:handle].to_s.presence
    if handle
      %(#{channel_title_html(title)} — #{channel_handle_html(handle)})
    else
      channel_title_html(title)
    end
  end

  def channel_title_html(title)
    %(<span class="font-bold">"#{escape_html(title)}"</span>)
  end

  def channel_handle_html(handle)
    %(<span class="text-cyan">@#{escape_html(handle.delete_prefix("@"))}</span>)
  end

  def escape_html(text)
    CGI.escapeHTML(text)
  end

  def format_number(n)
    Pito::Formatter::CompactCount.call(n)
  end
end
