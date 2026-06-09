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
    #     work and multi-word columns like "release date" stay intact.
    #   * The clause ends at the sort clause (`sorted by` / `ordered by`) or at
    #     end-of-input, so `with platform sorted by year` yields just [:platform].
    #   * Each token is stripped + downcased, mapped through +vocabulary+
    #     (alias → canonical Symbol); unknown tokens are dropped; canonical
    #     values are de-duplicated preserving first-seen order.
    module WithColumns
      module_function

      # Captures the column list after `with`, up to the sort clause or EOL.
      WITH_RE = /\bwith\b\s+(.+?)(?=\s+(?:sorted|ordered)\s+by\b|\z)/i

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
    end
  end
end
