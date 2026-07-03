# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Channel
      # Column metadata for the `list channels` kv-table — the channels sibling
      # of Video::ListColumns / Game::ListColumns, reduced to what the surface
      # supports: `list channels` has NO `with`/`without` (every column is
      # always shown), so this module only resolves SORT tokens.
      #
      # Sortable columns (owner 2026-07-02): every table column except Avatar —
      # handle, title, subs, views, vids. Canonical nouns are `subs`/`vids`
      # (`subscribers`/`videos` accepted as aliases, per the app-wide noun rule).
      module ListColumns
        # column token → sort key lambda (Channel → comparable).
        SORT_KEYS = {
          "handle" => ->(c) { c.at_handle.to_s.downcase },
          "title"  => ->(c) { c.title.to_s.downcase },
          "subs"   => ->(c) { c.subscriber_count.to_i },
          "views"  => ->(c) { c.view_count.to_i },
          "vids"   => ->(c) { c.videos.count }
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

        # Resolve a user sort token to its key lambda, or nil when unknown.
        # (No `selected_columns:` — channels columns are fixed, all visible.)
        #
        # @param token [String]
        # @return [Proc, nil]
        def sort_key_for(token)
          canonical = token.to_s.strip.downcase
          canonical = ALIASES.fetch(canonical, canonical)
          SORT_KEYS[canonical]
        end

        # The sortable tokens, for help/error copy.
        def sortable_tokens
          SORT_KEYS.keys
        end
      end
    end
  end
end
