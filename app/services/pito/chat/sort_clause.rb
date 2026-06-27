# frozen_string_literal: true

module Pito
  module Chat
    # Parses the `sort`/`order` clause shared by `list games` / `list videos`.
    # The verb may be `sort`, `sorted`, `order`, or `ordered`, and the `by`
    # particle is optional — so all of these are equivalent:
    #   `sort by views` · `sorted by views` · `sort views` · `order by views`
    #
    #   SortClause.parse("list games sorted by year desc")
    #   # => { token: "year", direction: :desc }
    #
    #   SortClause.parse("list games with platform order by release date")
    #   # => { token: "release date", direction: :asc }
    #
    #   SortClause.parse("list games")          # => nil  (no sort verb)
    #   SortClause.parse("list games sort")     # => nil  (no column)
    #
    # Rules:
    #   * Matches sort/sorted/order/ordered (case-insensitive), `\b`-bounded so it
    #     never trips on "resort"/"disorder"/"developer"/"sports".
    #   * The `by` particle is optional.
    #   * Captures the column token (may be multi-word, e.g. "release date").
    #   * Optional trailing asc/ascending/desc/descending; default is :asc.
    #   * Token is stripped and downcased; a blank token (bare `sort`) → nil.
    module SortClause
      module_function

      # Captures: [1] column token, [2] optional direction word.
      SORT_RE = /\b(?:sort(?:ed)?|order(?:ed)?)\s+(?:by\s+)?(.+?)(?:\s+(asc|ascending|desc|descending))?\s*\z/i

      # @param raw [String] the raw command text.
      # @return [Hash{ token: String, direction: Symbol }] or nil when no sort clause.
      def parse(raw)
        match = SORT_RE.match(raw.to_s)
        return nil unless match
        return nil if match[1].strip.empty?

        {
          token:     match[1].strip.downcase,
          direction: %w[desc descending].include?(match[2]&.downcase) ? :desc : :asc
        }
      end
    end
  end
end
