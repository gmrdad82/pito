# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Single source of truth for extra columns that can be appended to the
      # video list table via the `list videos with <col>[, <col>…]` syntax.
      #
      # Each COLUMNS entry holds:
      #   aliases: [String] — lowercase tokens users may type
      #   heading: String   — column header for the table
      #   value:   Proc     — called with a Video instance, returns a String
      #
      # Public API:
      #   vocabulary               — alias → canonical Symbol map (for WithColumns.parse)
      #   headings(cols)           — Array of heading strings in cols order
      #   cells(video, cols)       — Array of { text:, class: } hashes in cols order
      module ListColumns
        module_function

        COLUMNS = {
          game:     {
            aliases: %w[game games],
            heading: "Game",
            value:   ->(v) { v.linked_games.map(&:title).join(", ") }
          },
          duration: {
            aliases: %w[duration],
            heading: "Duration",
            value:   ->(v) { Pito::Video::DurationFormat.call(v.duration_seconds) || "—" }
          },
          views:    {
            aliases: %w[views],
            heading: "Views",
            value:   ->(v) { count_text(v.view_count) }
          },
          likes:    {
            aliases: %w[likes],
            heading: "Likes",
            value:   ->(v) { count_text(v.like_count) }
          },
          comments: {
            aliases: %w[comments],
            heading: "Comments",
            value:   ->(v) { count_text(v.comment_count) }
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
        # @param video [::Video]
        # @param cols  [Array<Symbol>] ordered canonical column keys
        # @return [Array<{ text: String, class: String }>]
        def cells(video, cols)
          cols.map do |col|
            { text: COLUMNS.fetch(col)[:value].call(video), class: "text-fg-dim" }
          end
        end

        # Returns "—" for a nil count, or the stringified integer.
        def count_text(n)
          n.nil? ? "—" : n.to_s
        end
        private :count_text
      end
    end
  end
end
