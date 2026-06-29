# frozen_string_literal: true

module Pito
  module Shell
    # ContextMeterComponent — a thin gradient bar sitting on the top edge of the
    # chatbox. Fills left→right from 0 to 100% as messages accumulate; pegs at
    # 100% when event_count ≥ THRESHOLD. A muted "0-100%" counter sits at the
    # right edge outside the box.
    #
    # The bar uses a 5-stop green→red gradient (theme accent tokens) with a
    # pito-blue shimmer sweep (the same @property --pito-bar-sweep technique as
    # ScoreBarComponent / TimeToBeatComponent). Shimmer duration = 4.4s
    # (between the score/ttb 3.4s and the analytics chart 5.5s).
    #
    # Rendered with a stable DOM id `pito-context-meter` so Turbo Stream replace
    # can refresh it after each turn without a full chatbox re-render.
    class ContextMeterComponent < ViewComponent::Base
      THRESHOLD = 100

      def initialize(event_count:)
        @event_count = event_count.to_i
      end

      # Fill percentage, 0–100, clamped.
      def fill_pct
        [ (@event_count * 100.0 / THRESHOLD).round(1), 100.0 ].min
      end

      # Display string for the counter.
      def counter_text
        "#{fill_pct.to_i}%"
      end

      # True when the bar is pegged at 100%.
      def full?
        @event_count >= THRESHOLD
      end
    end
  end
end
