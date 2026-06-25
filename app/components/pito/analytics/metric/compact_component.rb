# frozen_string_literal: true

module Pito
  module Analytics
    module Metric
      # One analytics metric rendered as a single key/value pair in the shared
      # kv-table style (label + value). The GENERIC "compact" cell reused for EVERY
      # analytics metric for now — the show vid/game `:enhanced` glance (real values)
      # AND the `analyze` `:system`/`:enhanced` messages (the `0`/`1` data-pulled
      # scaffold) render through it, until each metric earns its own bespoke
      # component (the "revisit": `Metric::ViewComponent`, `Metric::WatchedHoursComponent`, …).
      #
      # `value` is pre-rendered, html-safe content: a `TrendNumberComponent` render, a
      # split "+gained/-lost" / "👍/👎" value, or a plain "1"/"0" (1 = data pulled).
      class CompactComponent < ViewComponent::Base
        def initialize(label:, value:)
          @label = label
          @value = value
        end
      end
    end
  end
end
