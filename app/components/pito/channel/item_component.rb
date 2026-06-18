# frozen_string_literal: true

module Pito
  module Channel
    # The ONE channel item, rendered identically everywhere (centered column,
    # 120px circular avatar, handle / title). Two surfaces share it and differ
    # ONLY by kwargs: `list channels` renders the @handle as a yellow YouTube
    # link plus a one-line stats row; the recommended-channels grid renders a
    # plain @handle and a ScoreBar.
    #
    # kwargs:
    #   channel:      [Channel]      — the channel record to display.
    #   show_avatar:  [Boolean]      — render the cached avatar variant (default false).
    #   show_visit:   [Boolean]      — make the @handle a yellow YouTube link that
    #                                  opens the channel in a new tab (default false →
    #                                  plain cyan handle). Used on `list channels`.
    #                                  NOT VisitComponent (that auto-navigates).
    #   score:        [Integer, nil] — when present, render a ScoreBarComponent.
    #                                  nil omits the bar.
    #   show_stats:   [Boolean]      — render a one-line "subs · videos · views" stats
    #                                  row (default false). Used on `list channels` only;
    #                                  NOT in the Game Enhanced (recommended-channels) message.
    #   show_video_count: [Boolean]  — include the video count in the stats row (default
    #                                  false), between the subscriber and view counts.
    #                                  Opt-in for `list channels` only; the Game Enhanced
    #                                  surface leaves it off.
    #
    # Usage:
    #   # list channels — avatar + linked @handle + one-line stats, no score bar:
    #   render(Pito::Channel::ItemComponent.new(channel:, show_avatar: true, show_visit: true, show_stats: true, show_video_count: true))
    #
    #   # recommended channels — avatar + score bar, plain handle, no stats:
    #   render(Pito::Channel::ItemComponent.new(channel:, show_avatar: true, score: result.score))
    class ItemComponent < ViewComponent::Base
      def initialize(channel:, show_visit: false, score: nil, show_avatar: false, show_stats: false, show_video_count: false)
        @channel          = channel
        @show_visit       = show_visit
        @score            = score
        @show_avatar      = show_avatar
        @show_stats       = show_stats
        @show_video_count = show_video_count
      end

      attr_reader :channel

      def show_visit?
        @show_visit
      end

      def show_avatar?
        @show_avatar
      end

      def show_stats?
        @show_stats
      end

      def show_video_count?
        @show_video_count
      end

      # Our locally-cached avatar variant (never the YouTube CDN). nil → placeholder.
      def avatar_url
        channel.avatar_variant_url
      end

      def score?
        !@score.nil?
      end

      def score
        @score
      end

      # Rendered label for the subscriber count row, e.g. "1 sub" / "10 subs".
      # Nil stats treated as zero (matches the disconnect_confirmation.rb precedent).
      def subscribers_label
        Pito::Copy.render("pito.copy.channels.subscribers_count_plural",
                          count: Pito::Formatter::CompactCount.call(channel.subscriber_count.to_i))
      end

      # Local Video row count for this channel (no API call), compact-formatted.
      def videos_count_label
        Pito::Copy.render("pito.copy.channels.videos_count_plural",
                          count: Pito::Formatter::CompactCount.call(channel.videos.count))
      end

      def views_label
        Pito::Copy.render("pito.copy.channels.views_count_plural",
                          count: Pito::Formatter::CompactCount.call(channel.view_count.to_i))
      end

      # YouTube page URL for the [view] link.
      # Handle present: https://www.youtube.com/@<handle without leading @>
      # Otherwise:      https://www.youtube.com/channel/<youtube_channel_id>
      def youtube_url
        if channel.handle.present?
          handle = channel.handle.to_s.sub(/\A@+/, "")
          "https://www.youtube.com/@#{handle}"
        else
          "https://www.youtube.com/channel/#{channel.youtube_channel_id}"
        end
      end
    end
  end
end
