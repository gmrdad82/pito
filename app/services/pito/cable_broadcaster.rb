module Pito
  module CableBroadcaster
    module_function

    def broadcast_status_bar(payload)
      ActionCable.server.broadcast("pito:status_bar", payload)
    end
  end
end
