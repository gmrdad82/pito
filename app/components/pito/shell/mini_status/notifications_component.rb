# frozen_string_literal: true

module Pito
  module Shell
    module MiniStatus
      class NotificationsComponent < ViewComponent::Base
        def initialize(count:)
          @count = count
        end
      end
    end
  end
end
