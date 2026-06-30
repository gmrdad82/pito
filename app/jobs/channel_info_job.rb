# frozen_string_literal: true

# Background job that fetches channel statistics from YouTube
# after a successful OAuth connection. Part of the multi-stage /connect flow.
#
# Flow:
#   1. OAuth callback links channels, emits "connected" system event
#   2. This job fetches fresh channel stats
#   3. Emits enhanced #1 with subscriber/view counts
#   4. Resolves thinking #1
#   5a. When import_videos: true  — emits thinking #2, enqueues ImportVideosJob
#   5b. When import_videos: false — completes the turn (re-auth, no new channels)
class ChannelInfoJob < ApplicationJob
  queue_as :default

  def perform(connection_id, turn_id, import_videos: true)
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
    elsif import_videos
      # Emit thinking #2 for video import stage
      broadcaster.emit_thinking(turn:, dictionary: :importing)

      # Enqueue stage 2: video import
      ImportVideosJob.perform_later(connection_id, turn_id)
    else
      # Re-auth path: no new channels were added, so skip the import
      # and close the turn here instead of leaving it open.
      broadcaster.complete_turn(turn:)
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
          video_count:      normalized[:video_count],
          last_synced_at:   Time.current
        )
        Pito::Stats.set(channel, :subscribers, normalized[:subscriber_count])
        Pito::Stats.set(channel, :views, normalized[:view_count])

        # Cache OUR copy of the avatar (ActiveStorage) off the sync path so we
        # never hotlink the YouTube CDN (429). Skipped when no source URL.
        if normalized[:avatar_url].present?
          ChannelAvatarJob.perform_later(channel.id, normalized[:avatar_url])
        end

        # Same for the channel banner (our own 374x210 copy from brandingSettings).
        if normalized[:banner_url].present?
          ChannelBannerJob.perform_later(channel.id, normalized[:banner_url])
        end

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

    snippet  = item[:snippet]   || {}
    stats    = item[:statistics] || {}
    thumbnails = snippet[:thumbnails] || {}
    # Prefer the highest-res avatar available (high=800, medium=240, default=88)
    # — we normalize down to 240, so a larger source keeps it crisp.
    avatar_thumb = thumbnails[:high] || thumbnails[:medium] || thumbnails[:default] || {}
    # Channel banner from brandingSettings (we cache + serve our own 374x210 copy).
    branding_image = (item[:branding_settings] || {})[:image] || {}

    {
      title: snippet[:title],
      handle: snippet[:custom_url],
      description: snippet[:description],
      avatar_url: avatar_thumb[:url],
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
        %(#{channel_label(s)}<br><span class="text-fg-dim">#{I18n.t("pito.jobs.channel_info.stats.subscribers")}</span> <span class="text-cyan">#{subs}</span> · <span class="text-fg-dim">#{I18n.t("pito.jobs.channel_info.stats.views")}</span> <span class="text-cyan">#{views}</span>)
      end
    end

    parts.join("<br><br>")
  end

  def channel_label(s)
    title = s[:title].to_s.presence || I18n.t("pito.jobs.channel_info.channel_fallback")
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
