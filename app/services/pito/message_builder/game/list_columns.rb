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
          platform:     { key: ->(g) { Pito::Games::PlatformTokens.labels(g.platforms).to_s.downcase }, requires_with: true },
          genre:        { key: ->(g) { g.genres.map(&:name).join(", ").downcase },              requires_with: true },
          developer:    { key: ->(g) { g.developer_companies.map(&:name).join(", ").downcase }, requires_with: true },
          publisher:    { key: ->(g) { g.publisher_companies.map(&:name).join(", ").downcase }, requires_with: true },
          channels:     { key: ->(g) { g.linked_videos.map { |v| v.channel&.handle }.compact.uniq.sort.join(",").downcase }, requires_with: true },
          footage:      { key: ->(g) { g.footage_hours },                                        requires_with: true },
          # Unpriced games sort before any priced game ascending (nil → -1).
          price:        { key: ->(g) { g.price || -1 },                                          requires_with: true }
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
          "channel"      => :channels,
          "channels"     => :channels,
          "footage"      => :footage,
          "price"        => :price,
          "prices"       => :price
        }.freeze

        COLUMNS = {
          platform:     {
            aliases: %w[platform platforms],
            heading: "Platform",
            html:    true,
            value:   ->(g) { Pito::Games::PlatformTokens.icons_html(g.platforms) }
          },
          genre:        {
            aliases:    %w[genre genres],
            heading:    "Genre",
            cell_class: "text-fg-dim pito-cell-genre",
            value:      ->(g) { g.genres.map(&:name).join(", ") }
          },
          developer:    {
            aliases:    %w[developer dev],
            heading:    "Developer",
            cell_class: "text-fg-dim pito-cell-developer",
            value:      ->(g) { g.developer_companies.map(&:name).join(", ") }
          },
          publisher:    {
            aliases:    %w[publisher],
            heading:    "Publisher",
            cell_class: "text-fg-dim pito-cell-publisher",
            value:      ->(g) { g.publisher_companies.map(&:name).join(", ") }
          },
          channels:     {
            aliases:    %w[channel channels],
            heading:    "Channels",
            cell_class: "pito-cell-channel",
            # One line: the first distinct channel, then "+N more" for the rest
            # (N = remaining). The cell truncates with an ellipsis if it still
            # overflows the widened column. "—" when the game has no linked videos.
            value:      ->(g) {
              handles = g.linked_videos.filter_map { |v| v.channel&.handle }.uniq
              case handles.size
              when 0 then "—"
              when 1 then handles.first
              else        "#{handles.first} +#{handles.size - 1} more"
              end
            }
          },
          footage:      {
            aliases:    %w[footage],
            heading:    "Footage",
            align:      :right,
            cell_class: "text-fg-dim text-right tabular-nums pito-cell-duration",
            value:      ->(g) { Pito::Formatter::FootageHours.call(g.footage_hours) }
          },
          price:        {
            aliases:    %w[price prices],
            heading:    "Price",
            align:      :right,
            html:       true,
            cell_class: "text-fg-dim text-right tabular-nums pito-cell-price",
            value:      ->(g) { Pito::Games::PriceGlyphs.html(g.price) }
          }
        }.freeze

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

        # Returns +cols+ sorted by their order in COLUMNS.keys — a stable
        # left-to-right column order regardless of the order the user typed them.
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
        # Added columns get the cyan `--added` heading class so they read as
        # distinct from the two faded fixed columns (id/title).
        def heading_cells(cols)
          cols.map do |col|
            cfg   = COLUMNS.fetch(col)
            klass = "pito-table-heading--added"
            klass += " text-right" if cfg[:align] == :right
            { "text" => cfg[:heading], "class" => klass }
          end
        end

        # E7 options footer — per-surface column and sort summary.
        #
        # Derives the three OptionsFooter inputs from the currently-visible column
        # set and delegates rendering to Pito::Lists::OptionsFooter. Recomputes on
        # every List.call, so with/without follow-ups update it automatically.
        #
        # addable   — available columns not yet shown (COLUMNS.keys − cols)
        # removable — all currently-visible optional columns (cols; id+title/game
        #             heading are hardcoded and cannot be removed)
        # sort_keys — base sort tokens (id, title) + the primary sort token for
        #             each visible optional column (all game columns are sortable,
        #             so compact is a no-op here but kept for safety).
        def options_footer(cols)
          addable   = (COLUMNS.keys - cols).map { |c| display_token(c) }
          removable = cols.map { |c| display_token(c) }
          sort_keys = base_sort_tokens + cols.map { |c| SORT_VOCAB.key(c) }.compact
          Pito::Lists::OptionsFooter.call(addable:, removable:, sort_keys:)
        end

        # Returns an Array of cell hashes for the requested canonical columns.
        #
        # @param game [::Game]
        # @param cols [Array<Symbol>] ordered canonical column keys
        # @return [Array<{ text: String, class: String, html: Boolean }>]
        # The table-max integer-part width across the priced games, so the price
        # column can pad shorter numbers and align on the decimal point. nil/unpriced
        # games are skipped; 0 (free) counts as one digit ("0.00"). Returns 0 when no
        # game is priced.
        def price_pad_int(games)
          games.filter_map { |g|
            next if Pito::Coin.unpriced?(g.price)

            Pito::Formatter::Price.call(g.price, symbol: false).split(".", 2).first.length
          }.max || 0
        end

        # @param price_pad_int [Integer, nil] table-max integer width for the price
        #   column (see .price_pad_int); aligns the price numbers when present.
        def cells(game, cols, price_pad_int: nil)
          cols.map do |col|
            cfg  = COLUMNS.fetch(col)
            text =
              if col == :price && price_pad_int
                Pito::Games::PriceGlyphs.html(game.price, pad_int: price_pad_int)
              else
                cfg[:value].call(game)
              end
            cell_class =
              if col == :channels
                # Shimmer owns the colour; seed with game.id so repeated
                # @handles down the list land in different offset buckets.
                Pito::Shimmer::TokenComponent.css_class(text, extra: "pito-cell-channel", seed: game.id)
              else
                cfg[:cell_class] ||
                case cfg[:align]
                when :right
                  "text-fg-dim text-right"
                else
                  "text-fg-dim"
                end
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
