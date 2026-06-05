# frozen_string_literal: true

module Pito
  module Shell
    module Chatbox
      class ChannelComponent < ViewComponent::Base
        def initialize(channel:)
          @channel = channel
        end
      end
    end
  end
end
