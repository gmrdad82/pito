# frozen_string_literal: true

module Pito
  module Stats
    # Single source of truth for stat-metric glyphs + legend labels, shared by
    # CountersComponent and LegendComponent so the abbreviations never drift:
    # S subs · D vids · V views · L likes · C comms.
    module Metrics
      ABBR = { subs: "S", vids: "D", views: "V", likes: "L", comms: "C" }.freeze

      module_function

      def abbr(key)
        ABBR.fetch(key.to_sym)
      end

      # User-facing legend word for a metric (via Pito::Copy).
      def label(key)
        Pito::Copy.render("pito.copy.stats.legend.#{key}")
      end
    end
  end
end
