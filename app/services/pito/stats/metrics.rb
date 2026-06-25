# frozen_string_literal: true

module Pito
  module Stats
    # Single source of truth for stat-counter labels + icons, used by
    # CountersComponent so every surface renders the same words / glyphs.
    #
    # subs / vids / views render as full words; likes / comments render as a count
    # followed by an inline Lucide icon (👍 thumbs-up, 💬 message-square). The
    # word labels come from Pito::Copy; the icons double as the accessible label
    # for the icon-only metrics.
    module Metrics
      # Metrics that render as `<count>` + inline icon instead of a word.
      ICONS = { likes: "thumbs-up", comments: "message-square" }.freeze

      module_function

      # Full-word, title-case label for a metric (via Pito::Copy).
      def label(key)
        Pito::Copy.render("pito.copy.stats.labels.#{key}")
      end

      # Lucide icon name for an icon-rendered metric, or nil for word metrics.
      def icon(key)
        ICONS[key.to_sym]
      end

      # True when the metric renders as `<count>` + icon rather than a word.
      def icon?(key)
        ICONS.key?(key.to_sym)
      end
    end
  end
end
