# frozen_string_literal: true

module Pito
  module Chat
    # Parses the `with <col>[, <col>…]` clause shared by `list games` /
    # `list videos`. The clause names which extra kv-table columns to render.
    #
    #   WithColumns.parse("list games with platform, genre", vocabulary: GAMES_VOCAB)
    #   # => [:platform, :genre]
    #
    # Rules:
    #   * `with` is a magic word (case-insensitive, on a word boundary).
    #   * Columns are comma-separated — split on /\s*,\s*/ so both `,` and `, `
    #     work and any multi-word column token stays intact.
    #   * The clause ends at the sort clause (sort/sorted/order/ordered, with an
    #     optional `by`) or at end-of-input, so both `with platform sorted by price`
    #     and `with platform sort by price` yield just [:platform].
    #   * Each token is stripped + downcased, mapped through +vocabulary+
    #     (alias → canonical Symbol); unknown tokens are dropped; canonical
    #     values are de-duplicated preserving first-seen order.
    module WithColumns
      module_function

      # Captures the column list after `with`, up to the sort clause or EOL.
      WITH_RE = /\bwith\b\s+(.+?)(?=\s+(?:sort(?:ed)?|order(?:ed)?)(?:\s+by)?\b|\z)/i

      # @param raw        [String] the raw command text.
      # @param vocabulary [Hash{String=>Object}] token (alias) → canonical value.
      # @return [Array] ordered, de-duplicated canonical column values ([] when no clause).
      def parse(raw, vocabulary:)
        match = WITH_RE.match(raw.to_s)
        return [] unless match

        match[1]
          .split(/\s*,\s*/)
          .filter_map { |token| vocabulary[token.strip.downcase] }
          .uniq
      end

      # The `with` clause's raw tokens that #parse silently dropped (no entry
      # in +vocabulary+) — the caller-facing half of that silence. A caller
      # that must not let a filter-shaped word disappear noiselessly (F-2:
      # "list games with hard bosses" rendering an unfiltered full list)
      # checks this BEFORE trusting an empty/auto-filled column set.
      #
      # @param raw        [String] the raw command text.
      # @param vocabulary  [Hash{String=>Object}] token (alias) → canonical value.
      # @return [Array<String>] unrecognized tokens (stripped, downcased); []
      #   when there is no `with` clause or every token resolved.
      def unrecognized(raw, vocabulary:)
        match = WITH_RE.match(raw.to_s)
        return [] unless match

        match[1]
          .split(/\s*,\s*/)
          .map { |token| token.strip.downcase }
          .reject(&:empty?)
          .reject { |token| vocabulary.key?(token) }
      end
    end
  end
end
