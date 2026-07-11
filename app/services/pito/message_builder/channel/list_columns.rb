# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Channel
      # Column metadata for the `list channels` kv-table — the channels sibling
      # of Video::ListColumns / Game::ListColumns.
      #
      # Only IDENTITY stays fixed (Avatar · Handle · Title). Every counter
      # — subs, views, vids, likes — is a `with`/`without`-able column;
      # DEFAULT_COLUMNS ships subs/views/vids visible so a bare `list channels`
      # looks exactly like it always did, but `without views` finally works
      # (the old base table was immovable: "Removable: nothing").
      #
      # Sortable: handle + title always; a counter column while it is visible.
      module ListColumns
        # Fixed-column token → sort key lambda (Channel → comparable).
        SORT_KEYS = {
          "handle" => ->(c) { c.at_handle.to_s.downcase },
          "title"  => ->(c) { c.title.to_s.downcase }
        }.freeze

        # The with/without-able columns, in canonical display order.
        COLUMNS = {
          subs: {
            aliases: %w[subs sub subscribers],
            heading: "Subs",
            value:   ->(c) { c.subscriber_count },
            sort:    ->(c) { c.subscriber_count.to_i }
          },
          views: {
            aliases: %w[views view],
            heading: "Views",
            value:   ->(c) { c.view_count },
            sort:    ->(c) { c.view_count.to_i }
          },
          vids: {
            aliases: %w[vids vid videos video],
            heading: "Vids",
            value:   ->(c) { c.videos.count },
            sort:    ->(c) { c.videos.count }
          },
          likes: {
            aliases: %w[likes],
            heading: "Likes",
            value:   ->(c) { c.like_count },
            sort:    ->(c) { c.like_count.to_i }
          }
        }.freeze

        # Visible without any `with` clause — the classic channels table.
        DEFAULT_COLUMNS = %i[subs views vids].freeze

        # Accepted aliases → canonical column token (sort-token resolution for
        # the FIXED columns; counter aliases resolve through +vocabulary+).
        ALIASES = {
          "name"    => "title",
          "channel" => "handle"
        }.freeze

        module_function

        # Maps every column alias (downcased) → canonical Symbol —
        # the vocabulary WithColumns.parse and the column_list resolver expect.
        def vocabulary
          @vocabulary ||= COLUMNS.each_with_object({}) do |(canonical, cfg), vocab|
            cfg[:aliases].each { |a| vocab[a] = canonical }
          end.freeze
        end

        # Normalize a selection to canonical display order (COLUMNS order),
        # dropping unknowns — both entry paths (typed verb + reply mutation)
        # funnel through this so "with likes without views" can never scramble
        # the table.
        def normalize(columns)
          COLUMNS.keys & Array(columns).map(&:to_sym)
        end

        # Resolve a user sort token to its key lambda, or nil when unknown.
        # Fixed columns always sort; a counter column sorts only while it is
        # in +selected_columns+ (mirrors Video::ListColumns' requires_with).
        #
        # @param token            [String]
        # @param selected_columns [Array<Symbol>]
        # @return [Proc, nil]
        def sort_key_for(token, selected_columns: [])
          canonical = token.to_s.strip.downcase
          canonical = ALIASES.fetch(canonical, canonical)
          return SORT_KEYS[canonical] if SORT_KEYS.key?(canonical)

          sym = vocabulary[canonical] || canonical.to_sym
          return nil unless selected_columns.map(&:to_sym).include?(sym)

          COLUMNS.dig(sym, :sort)
        end

        # The sortable tokens for help/error copy + the options footer:
        # every fixed column, plus the currently-visible counter ones.
        def sortable_tokens(selected_columns: [])
          SORT_KEYS.keys + normalize(selected_columns).map(&:to_s)
        end
      end
    end
  end
end
