# frozen_string_literal: true

module Pito
  module Channel
    # Renders a horizontal, wrapping strip of channel cards for `list channels`.
    #
    # Each card shows: avatar image (with placeholder when blank), title,
    # @handle + [view] link to the channel's YouTube page, and the channel id.
    #
    # Usage:
    #   render(Pito::Channel::ListComponent.new(channels: Channel.order(:title)))
    class ListComponent < ViewComponent::Base
      def initialize(channels:)
        @channels = channels
      end

      def channels
        @channels
      end

      # Returns the YouTube page URL for a channel.
      # If handle is present: https://www.youtube.com/@<handle without leading @>
      # Otherwise: https://www.youtube.com/channel/<youtube_channel_id>
      def youtube_url_for(channel)
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
