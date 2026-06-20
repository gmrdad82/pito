# frozen_string_literal: true

module Pito
  module Achievements
    # Resolves singular and plural title-case badge label words for each metric
    # via Pito::Copy so every surface (video detail, game detail, badge rendering,
    # notifications) stays consistent and the strings live in the i18n copy layer.
    #
    # @example
    #   Pito::Achievements::Label.for("views")              #=> "Views"   (plural default)
    #   Pito::Achievements::Label.for("views", count: 1)    #=> "View"    (singular)
    #   Pito::Achievements::Label.for("views", count: 2)    #=> "Views"   (plural)
    #   Pito::Achievements::Label.for(:watched_hours)        #=> "Clocks"
    module Label
      METRICS = %w[subs subs_gained views watched_hours likes comments].freeze

      module_function

      # @param metric [String, Symbol]
      # @param count  [Integer, nil] — pass the threshold/count to get the right
      #   form; nil (default) returns the plural, keeping callers that only want
      #   a header word backward-compatible.
      # @return [String] title-case badge label
      # @raise [KeyError] when metric is not in the known set
      def for(metric, count: nil)
        key = metric.to_s
        raise KeyError, "unknown achievement metric: #{key.inspect}" unless METRICS.include?(key)

        form = count == 1 ? "one" : "other"
        Pito::Copy.render("pito.copy.shinies.labels.#{key}.#{form}")
      end
    end
  end
end
