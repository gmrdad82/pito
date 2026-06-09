# frozen_string_literal: true

module Pito
  module Chat
    # Parses the `sorted by` / `ordered by` clause shared by `list games` /
    # `list videos`.
    #
    #   SortClause.parse("list games sorted by year desc")
    #   # => { token: "year", direction: :desc }
    #
    #   SortClause.parse("list games with platform ordered by release date")
    #   # => { token: "release date", direction: :asc }
    #
    #   SortClause.parse("list games")
    #   # => nil
    #
    # Rules:
    #   * Matches `sorted by` or `ordered by` (case-insensitive).
    #   * Captures the column token (may be multi-word, e.g. "release date").
    #   * An optional trailing `asc` or `desc` sets the direction; default is :asc.
    #   * Token is stripped and downcased.
    module SortClause
      module_function

      # Captures: [1] column token, [2] optional asc/desc.
      SORT_RE = /(?:sorted|ordered)\s+by\s+(.+?)(?:\s+(asc|desc))?\s*\z/i

      # @param raw [String] the raw command text.
      # @return [Hash{ token: String, direction: Symbol }] or nil when no sort clause.
      def parse(raw)
        match = SORT_RE.match(raw.to_s)
        return nil unless match

        {
          token:     match[1].strip.downcase,
          direction: match[2]&.downcase == "desc" ? :desc : :asc
        }
      end
    end
  end
end
