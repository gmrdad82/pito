# frozen_string_literal: true

module Pito
  module Channel
    # Renders a visit-redirect message for a channel, in one of two states:
    #
    #   :visiting (default) — a shimmer copy span ("Visiting @handle…") + a hidden
    #     anchor. The pito--auto-visit Stimulus controller auto-clicks the anchor
    #     ONCE after a short delay (opening the channel's YouTube page in a new
    #     tab), removes the shimmer, then POSTs to the consume endpoint so the
    #     event is persisted in its :visited state. It never auto-clicks again.
    #
    #   :visited — the consumed, follow-up state: a plain past-tense line
    #     ("Visited @handle.") + a manual [view] link to re-open. No shimmer, no
    #     controller, no auto-click. This is what renders on every page refresh
    #     after the first visit, so the link is never re-clicked automatically.
    #
    # Usage:
    #   render(Pito::Channel::VisitComponent.new(channel: channel))
    #   render(Pito::Channel::VisitComponent.new(channel: channel, state: :visited))
    class VisitComponent < ViewComponent::Base
      STATES = %i[visiting visited].freeze

      def initialize(channel:, state: :visiting)
        @channel   = channel
        @state     = STATES.include?(state.to_sym) ? state.to_sym : :visiting
        @unique_id = "channel-visit-#{channel.id}-#{SecureRandom.hex(4)}"
      end

      attr_reader :channel, :state, :unique_id

      def visited?
        state == :visited
      end

      # Returns the YouTube page URL for the channel.
      # If handle is present: https://www.youtube.com/@<handle without leading @>
      # Otherwise: https://www.youtube.com/channel/<youtube_channel_id>
      def youtube_url
        if channel.handle.present?
          handle = channel.handle.to_s.sub(/\A@+/, "")
          "https://www.youtube.com/@#{handle}"
        else
          "https://www.youtube.com/channel/#{channel.youtube_channel_id}"
        end
      end

      def copy_text
        key = visited? ? "pito.copy.channels.visited" : "pito.copy.channels.visiting"
        Pito::Copy.render(key, handle: channel.at_handle)
      end
    end
  end
end
