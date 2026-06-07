# frozen_string_literal: true

module Pito
  module Channel
    # Renders a single channel item: handle, title, #id, and optionally a
    # [view] link (show_visit: true) and/or a ScoreBarComponent below the id.
    #
    # kwargs:
    #   channel:      [Channel]           — the channel record to display.
    #   show_visit:   [Boolean]           — when true, renders a plain [view]
    #                                       link to the channel's YouTube page.
    #                                       Defaults to false. (NOT VisitComponent,
    #                                       which auto-navigates on render.)
    #   score:        [Integer, nil]      — when present (non-nil), renders a
    #                                       Pito::ScoreBarComponent with that score
    #                                       below the #id.  nil omits the bar.
    #
    # Usage examples:
    #   # In list channels — with visit link, no score bar:
    #   render(Pito::Channel::ItemComponent.new(channel: channel, show_visit: true))
    #
    #   # In enhanced channel grid — no visit link, with score bar:
    #   render(Pito::Channel::ItemComponent.new(channel: result.channel, score: result.score))
    class ItemComponent < ViewComponent::Base
      def initialize(channel:, show_visit: false, score: nil)
        @channel    = channel
        @show_visit = show_visit
        @score      = score
      end

      attr_reader :channel

      def show_visit?
        @show_visit
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
