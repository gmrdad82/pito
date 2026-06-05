# frozen_string_literal: true

module Pito
  module Event
    # Unified meta footer: [timestamp ·] [#handle ·] [@channel]
    # timestamp: DateTime|nil — formatted as "7:58 PM"; omitted when nil
    # handle:    String|nil     — shown as "#handle" in purple; omitted when nil
    # channel:   String|nil     — shown as "@channel" in cyan; omitted when nil
    class MetaLineComponent < ViewComponent::Base
      def initialize(timestamp: nil, handle: nil, channel: nil)
        @timestamp = timestamp
        @handle    = handle
        @channel   = channel
      end

      def formatted_timestamp
        @timestamp&.strftime("%-l:%M %p")
      end
    end
  end
end
