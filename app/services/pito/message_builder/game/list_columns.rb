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

        # Maps canonical column → sort specification.
        #   key:           Proc called with a Game instance, returns a sortable value.
        #   requires_with: true  → only valid when the column is present in selected_columns.
        #                  false → always visible (base column).
        SORT_SPECS = {
          id:           { key: ->(g) { g.id },                                                  requires_with: false },
          title:        { key: ->(g) { g.title.to_s.downcase },                                 requires_with: false },
          platform:     { key: ->(g) { Pito::Game::PlatformTokens.labels(g.platforms).to_s.downcase }, requires_with: true },
          genre:        { key: ->(g) { g.genres.map(&:name).join(", ").downcase },              requires_with: true },
          developer:    { key: ->(g) { g.developer_companies.map(&:name).join(", ").downcase }, requires_with: true },
          publisher:    { key: ->(g) { g.publisher_companies.map(&:name).join(", ").downcase }, requires_with: true },
          # TBA (no date/year) sorts AFTER all known dates ascending (and first
          # descending) — treat unknown as the far future, not Date.new(0).
          release_date: { key: ->(g) { g.release_date || Date.new(9999, 12, 31) },              requires_with: true },
          year:         { key: ->(g) { g.release_year || 9999 },                                requires_with: true }
        }.freeze

        # Maps every sort token (downcased) → canonical column Symbol.
        SORT_VOCAB = {
          "id"           => :id,
          "#"            => :id,
          "title"        => :title,
          "game"         => :title,
          "platform"     => :platform,
          "platforms"    => :platform,
          "genre"        => :genre,
          "genres"       => :genre,
          "developer"    => :developer,
          "dev"          => :developer,
          "publisher"    => :publisher,
          "release date" => :release_date,
          "year"         => :year
        }.freeze

        COLUMNS = {
          platform:     {
            aliases: %w[platform platforms],
            heading: "Platform",
            html:    true,
            value:   ->(g) { Pito::Game::PlatformTokens.icons_html(g.platforms) }
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
            align:   :right,
            value:   ->(g) { Pito::Formatter::ReleaseDate.call(g).to_s }
          },
          year:         {
            aliases: %w[year],
            heading: "Year",
            align:   :right,
            value:   ->(g) { g.release_year&.to_s || "—" }
          }
        }.freeze

        # Display tokens in COLUMNS order — the primary alias for each column.
        # Used by ListClauseGhost to build autocomplete candidates.
        def suggestion_tokens
          COLUMNS.keys.map { |canonical| DISPLAY_TOKEN_MAP[canonical] }
        end

        # Returns the display token String for a canonical Symbol.
        #   display_token(:release_date) # => "release date"
        def display_token(canonical)
          DISPLAY_TOKEN_MAP[canonical]
        end

        # Base sort tokens — always-visible columns (requires_with: false).
        def base_sort_tokens
          %w[id title]
        end

        # Maps canonical Symbol → primary display token (first alias).
        DISPLAY_TOKEN_MAP = COLUMNS.each_with_object({}) do |(canonical, cfg), map|
          map[canonical] = cfg[:aliases].first
        end.freeze

        # Maps every alias (downcased) → its canonical column Symbol.
        # Memoised so the Hash is built once.
        def vocabulary
          @vocabulary ||= COLUMNS.each_with_object({}) do |(canonical, cfg), vocab|
            cfg[:aliases].each { |a| vocab[a] = canonical }
          end.freeze
        end

        # Returns +cols+ sorted by their order in COLUMNS.keys — so
        # release_date and year always trail the other with-columns.
        #
        # @param cols [Array<Symbol>] canonical column keys in any order
        # @return [Array<Symbol>]
        def canonical_order(cols)
          order = COLUMNS.keys
          cols.sort_by { |col| order.index(col) || order.size }
        end

        # Returns an Array of heading strings for the requested canonical columns.
        #
        # @param cols [Array<Symbol>] ordered canonical column keys
        # @return [Array<String>]
        def headings(cols)
          cols.map { |col| COLUMNS.fetch(col)[:heading] }
        end

        # Returns an Array of heading entries for the requested canonical columns.
        # Left-aligned columns return a plain String; right-aligned columns return
        # a Hash { "text" => heading, "class" => "text-right" } for SystemComponent
        # to merge into the heading cell class.
        #
        # @param cols [Array<Symbol>] ordered canonical column keys
        # @return [Array<String, Hash>]
        def heading_cells(cols)
          cols.map do |col|
            cfg = COLUMNS.fetch(col)
            if cfg[:align] == :right
              { "text" => cfg[:heading], "class" => "text-right" }
            else
              cfg[:heading]
            end
          end
        end

        # Returns an Array of cell hashes for the requested canonical columns.
        #
        # @param game [::Game]
        # @param cols [Array<Symbol>] ordered canonical column keys
        # @return [Array<{ text: String, class: String, html: Boolean }>]
        def cells(game, cols)
          cols.map do |col|
            cfg  = COLUMNS.fetch(col)
            text = cfg[:value].call(game)
            cell_class =
              case cfg[:align]
              when :right
                col == :year ? "text-fg-dim text-right tabular-nums" : "text-fg-dim text-right"
              else
                "text-fg-dim"
              end
            { text:, class: cell_class, html: cfg[:html] == true }
          end
        end

        # Returns the sort-key proc for +token+ if it resolves to a visible column
        # (a base column, or a with-column present in +selected_columns+); else nil.
        #
        # @param token            [String]        user-supplied sort token (raw, any case).
        # @param selected_columns [Array<Symbol>] columns chosen via the `with` clause.
        # @return [Proc, nil]
        def sort_key_for(token, selected_columns:)
          canonical = SORT_VOCAB[token.to_s.strip.downcase]
          return nil unless canonical

          spec = SORT_SPECS[canonical]
          return nil if spec[:requires_with] && !selected_columns.include?(canonical)

          spec[:key]
        end
      end
    end
  end
end
