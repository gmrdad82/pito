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
      STATES       = %i[visiting visited].freeze
      DESTINATIONS = %i[channel studio].freeze

      def initialize(channel:, state: :visiting, destination: :channel)
        @channel     = channel
        @state       = STATES.include?(state.to_sym) ? state.to_sym : :visiting
        @destination = DESTINATIONS.include?(destination.to_sym) ? destination.to_sym : :channel
        @unique_id   = "channel-visit-#{channel.id}-#{SecureRandom.hex(4)}"
      end

      attr_reader :channel, :state, :destination, :unique_id

      def visited?
        state == :visited
      end

      def studio?
        destination == :studio
      end

      # Returns the URL to open based on the destination:
      #   :channel → channel's YouTube page (handle-based or /channel/<id>)
      #   :studio  → YouTube Studio for the channel
      def target_url
        studio? ? channel.youtube_studio_url : channel.youtube_channel_url
      end

      def copy_text
        if studio?
          key = visited? ? "pito.copy.channels.visited_studio" : "pito.copy.channels.visiting_studio"
        else
          key = visited? ? "pito.copy.channels.visited" : "pito.copy.channels.visiting"
        end
        Pito::Copy.render(key, handle: channel.at_handle)
      end
    end
  end
end
