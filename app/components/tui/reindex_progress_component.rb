module Tui
  class ReindexProgressComponent < ViewComponent::Base
    LABEL_WIDTH = 7 # "reindex" is 7 chars; pattern fills 7 dashes with 1 moving `=`

    def initialize(brand:, started_at: nil)
      @brand = brand
      @started_at = started_at
    end

    attr_reader :brand, :started_at

    # Returns the static initial frame (server-rendered).
    # The Stimulus controller animates client-side.
    def initial_frame
      "[=#{'-' * (LABEL_WIDTH - 1)}]"
    end
  end
end
