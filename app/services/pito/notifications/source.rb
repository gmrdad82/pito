# Namespace for notification sources. Each concrete source exposes `report!(...)` → builds an HTML/plain message string and calls `Notification.create!(message:)`.
module Pito
  module Notifications
    module Source
    end
  end
end
