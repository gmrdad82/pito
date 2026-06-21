# frozen_string_literal: true

module Pito
  module Shell
    module MiniStatus
      class NotificationsComponent < ViewComponent::Base
        def initialize(count:)
          @count = count
        end

        # Highest notification id — a monotonic "newest notification" marker. The
        # count controller plays the chime only when this RISES (a genuinely new
        # notification), never on a read/unread toggle (which moves the unread
        # count but not the max id). 0 when there are none.
        def latest_id
          ::Notification.maximum(:id).to_i
        end
      end
    end
  end
end
