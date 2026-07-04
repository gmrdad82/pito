# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Channel
      # Column metadata for the `list channels` kv-table — the channels sibling
      # of Video::ListColumns / Game::ListColumns.
      #
      # The base table (Avatar · Handle · Title · Subs · Views · Vids) stays
      # fixed and always visible; on top of it, ADDABLE columns join via
      # `with <col>` / leave via `without <col>` (owner G26.2 — channels joined
      # the with/without mechanism for their audience counters).
      #
      # Sortable: every fixed column except Avatar — handle, title, subs, views,
      # vids (canonical nouns `subs`/`vids`; `subscribers`/`videos` aliased) —
      # plus any addable column while it is visible.
      module ListColumns
        # Fixed-column token → sort key lambda (Channel → comparable).
        SORT_KEYS = {
          "handle" => ->(c) { c.at_handle.to_s.downcase },
          "title"  => ->(c) { c.title.to_s.downcase },
          "subs"   => ->(c) { c.subscriber_count.to_i },
          "views"  => ->(c) { c.view_count.to_i },
          "vids"   => ->(c) { c.videos.count }
        }.freeze

        # Addable columns — `with`/`without`-able, sortable only while shown.
        COLUMNS = {
          likes: {
            aliases: %w[likes],
            heading: "Likes",
            value:   ->(c) { c.like_count },
            sort:    ->(c) { c.like_count.to_i }
          }
        }.freeze

        # Accepted aliases → canonical column token.
        ALIASES = {
          "subscribers" => "subs",
          "sub"         => "subs",
          "videos"      => "vids",
          "vid"         => "vids",
          "name"        => "title",
          "channel"     => "handle"
        }.freeze

        module_function

        # Maps every addable-column alias (downcased) → canonical Symbol —
        # the vocabulary WithColumns.parse and the column_list resolver expect.
        def vocabulary
          @vocabulary ||= COLUMNS.each_with_object({}) do |(canonical, cfg), vocab|
            cfg[:aliases].each { |a| vocab[a] = canonical }
          end.freeze
        end

        # Resolve a user sort token to its key lambda, or nil when unknown.
        # Fixed columns always sort; an addable column sorts only while it is
        # in +selected_columns+ (mirrors Video::ListColumns' requires_with).
        #
        # @param token            [String]
        # @param selected_columns [Array<Symbol>]
        # @return [Proc, nil]
        def sort_key_for(token, selected_columns: [])
          canonical = token.to_s.strip.downcase
          canonical = ALIASES.fetch(canonical, canonical)
          return SORT_KEYS[canonical] if SORT_KEYS.key?(canonical)

          sym = canonical.to_sym
          return nil unless selected_columns.map(&:to_sym).include?(sym)

          COLUMNS.dig(sym, :sort)
        end

        # The sortable tokens for help/error copy + the options footer:
        # every fixed column, plus the currently-visible addable ones.
        def sortable_tokens(selected_columns: [])
          SORT_KEYS.keys + selected_columns.map(&:to_s)
        end
      end
    end
  end
end
