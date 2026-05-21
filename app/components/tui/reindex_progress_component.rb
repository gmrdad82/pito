module Tui
  # FB-125 / FB-171 / FB-172 (2026-05-21).
  #
  # Animated character indicator that replaces `[reindex]` while a
  # reindex job is in flight. Total width is locked to `TOTAL_WIDTH = 9`
  # characters (matches `[reindex]` width exactly) so the row never
  # jiggles when the action swaps in/out of the matching `[reindex]`
  # link. The frame is wrapped in literal `[` and `]` brackets; only
  # the inner 7 slots (`INNER_WIDTH`) animate — a single `=` cycles
  # left-to-right across the inner dashes.
  #
  # The first frame is server-rendered as `[=------]` (`[` + `=` +
  # six `-` + `]`); the Stimulus controller advances the `=` across
  # the seven inner slots at 120ms cadence, wrapping at the end.
  class ReindexProgressComponent < ViewComponent::Base
    INNER_WIDTH = 7 # number of inner slots (matches "reindex" letter count)
    TOTAL_WIDTH = INNER_WIDTH + 2 # brackets included

    def initialize(brand:, started_at: nil)
      @brand = brand
      @started_at = started_at
    end

    attr_reader :brand, :started_at

    # Returns the static initial frame (server-rendered).
    # The Stimulus controller animates client-side.
    def initial_frame
      "[" + "=" + ("-" * (INNER_WIDTH - 1)) + "]"
    end
  end
end
