# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Single source of truth for extra columns that can be appended to the
      # game list table via the `list games with <col>[, <col>…]` syntax.
      #
      # Each COLUMNS entry holds:
      #   aliases: [String] — lowercase tokens users may type
      #   heading: String   — column header for the table
      #   value:   Proc     — called with a Game instance, returns a String
      #
      # Public API:
      #   vocabulary               — alias → canonical Symbol map (for WithColumns.parse)
      #   headings(cols)           — Array of heading strings in cols order
      #   cells(game, cols)        — Array of { text:, class: } hashes in cols order
      module ListColumns
        module_function

        COLUMNS = {
          platform:     {
            aliases: %w[platform platforms],
            heading: "Platform",
            value:   ->(g) { Array(g.platforms).join(", ") }
          },
          genre:        {
            aliases: %w[genre genres],
            heading: "Genre",
            value:   ->(g) { g.genres.map(&:name).join(", ") }
          },
          developer:    {
            aliases: %w[developer dev],
            heading: "Developer",
            value:   ->(g) { g.developer_companies.map(&:name).join(", ") }
          },
          publisher:    {
            aliases: %w[publisher],
            heading: "Publisher",
            value:   ->(g) { g.publisher_companies.map(&:name).join(", ") }
          },
          release_date: {
            aliases: [ "release date" ],
            heading: "Release",
            value:   ->(g) { g.release_label.to_s }
          },
          year:         {
            aliases: %w[year],
            heading: "Year",
            value:   ->(g) { g.release_year&.to_s || "—" }
          }
        }.freeze

        # Maps every alias (downcased) → its canonical column Symbol.
        # Memoised so the Hash is built once.
        def vocabulary
          @vocabulary ||= COLUMNS.each_with_object({}) do |(canonical, cfg), vocab|
            cfg[:aliases].each { |a| vocab[a] = canonical }
          end.freeze
        end

        # Returns an Array of heading strings for the requested canonical columns.
        #
        # @param cols [Array<Symbol>] ordered canonical column keys
        # @return [Array<String>]
        def headings(cols)
          cols.map { |col| COLUMNS.fetch(col)[:heading] }
        end

        # Returns an Array of cell hashes for the requested canonical columns.
        #
        # @param game [::Game]
        # @param cols [Array<Symbol>] ordered canonical column keys
        # @return [Array<{ text: String, class: String }>]
        def cells(game, cols)
          cols.map do |col|
            { text: COLUMNS.fetch(col)[:value].call(game), class: "text-fg-dim" }
          end
        end
      end
    end
  end
end
