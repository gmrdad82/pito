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
    #   Pito::Achievements::Label.for(:watched_hours)        #=> "Watched hours"
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

      # @param metric [String, Symbol]
      # @param count  [Integer, nil] — pass the threshold/count to get the right
      #   form; count == 1 returns the singular badge face (`badge_one`), anything
      #   else (incl. nil, the default) returns the plural face — keeping callers
      #   that only want the plural face backward-compatible.
      # @return [String] full title-case word displayed on the badge face
      #   (distinct from the plural label — watched_hours badge is "Watched", not
      #   "Watched hours"; its singular face is also "Watched").
      # @raise [KeyError] when metric is not in the known set
      def badge(metric, count: nil)
        key = metric.to_s
        raise KeyError, "unknown achievement metric: #{key.inspect}" unless METRICS.include?(key)

        form = count == 1 ? "badge_one" : "badge"
        Pito::Copy.render("pito.copy.shinies.labels.#{key}.#{form}")
      end

      # @param metric [String, Symbol]
      # @return [String] single-letter abbreviation used on the badge face
      # @raise [KeyError] when metric is not in the known set
      def abbr(metric)
        key = metric.to_s
        raise KeyError, "unknown achievement metric: #{key.inspect}" unless METRICS.include?(key)

        Pito::Copy.render("pito.copy.shinies.labels.#{key}.abbr")
      end
    end
  end
end
