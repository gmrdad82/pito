# frozen_string_literal: true

module Pito
  module Channel
    # The ONE channel item, rendered identically everywhere (centered column,
    # 120px circular avatar, handle / title / #id). Two surfaces share it and
    # differ ONLY by kwargs: `list channels` shows the [view] link and no score
    # bar; the recommended-channels grid hides [view] and shows a ScoreBar.
    #
    # kwargs:
    #   channel:      [Channel]      — the channel record to display.
    #   show_avatar:  [Boolean]      — render the cached avatar variant (default false).
    #   show_visit:   [Boolean]      — render a plain [view] link (default false).
    #                                  NOT VisitComponent (that auto-navigates).
    #   score:        [Integer, nil] — when present, render a ScoreBarComponent
    #                                  below the #id. nil omits the bar.
    #
    # Usage:
    #   # list channels — avatar + [view], no score bar:
    #   render(Pito::Channel::ItemComponent.new(channel:, show_avatar: true, show_visit: true))
    #
    #   # recommended channels — avatar + score bar, no [view]:
    #   render(Pito::Channel::ItemComponent.new(channel:, show_avatar: true, score: result.score))
    class ItemComponent < ViewComponent::Base
      def initialize(channel:, show_visit: false, score: nil, show_avatar: false)
        @channel     = channel
        @show_visit  = show_visit
        @score       = score
        @show_avatar = show_avatar
      end

      attr_reader :channel

      def show_visit?
        @show_visit
      end

      def show_avatar?
        @show_avatar
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
