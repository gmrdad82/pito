module Tui
  class HintComponent < ViewComponent::Base
    def initialize(text:)
      @text = text
    end

    attr_reader :text
  end
end
