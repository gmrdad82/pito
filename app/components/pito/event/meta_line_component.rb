# frozen_string_literal: true

module Pito
  module Event
    # Unified meta footer: [#handle ·] [@channel]. The leading timestamp now
    # rides inline on the message's first line via TimestampPrefixComponent; this
    # footer carries only the handle/channel and renders nothing when both absent.
    # handle:    String|nil — shown as "#handle" in purple; omitted when nil
    # channel:   String|nil — shown as "@channel" in cyan; omitted when nil
    class MetaLineComponent < ViewComponent::Base
      def initialize(handle: nil, channel: nil)
        @handle  = handle
        @channel = channel
      end

      def render?
        @handle.present? || @channel.present?
      end
    end
  end
end
