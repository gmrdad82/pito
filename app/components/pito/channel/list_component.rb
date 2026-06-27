# frozen_string_literal: true

module Pito
  module Channel
    # Renders a horizontal, wrapping strip of channel cards for `list channels`.
    #
    # Each card shows: avatar image (with placeholder when blank), title,
    # @handle prefill token (auto-runs `show channel @handle`), and stats.
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
    end
  end
end
