# frozen_string_literal: true

module Pito
  module Shell
    module Chatbox
      class PeriodComponent < ViewComponent::Base
        def initialize(period:)
          @period = period
        end
      end
    end
  end
end
