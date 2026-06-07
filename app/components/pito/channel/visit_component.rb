# frozen_string_literal: true

module Pito
  module Channel
    # Renders a visit-redirect message for a channel.
    #
    # Wraps a shimmer copy span and a hidden anchor.  The pito--auto-visit
    # Stimulus controller auto-clicks the anchor after a short delay, opening
    # the channel's YouTube page in a new tab, and removes the shimmer class.
    #
    # Usage:
    #   render(Pito::Channel::VisitComponent.new(channel: channel))
    class VisitComponent < ViewComponent::Base
      def initialize(channel:)
        @channel   = channel
        @unique_id = "channel-visit-#{channel.id}-#{SecureRandom.hex(4)}"
      end

      attr_reader :channel, :unique_id

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
        Pito::Copy.render("pito.copy.channels.visiting", handle: channel.at_handle)
      end
    end
  end
end
