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

        # Maps canonical column → sort specification.
        #   key:           Proc called with a Video instance, returns a sortable value.
        #   requires_with: true  → only valid when the column is present in selected_columns.
        #                  false → always visible (base column).
        SORT_SPECS = {
          id:       { key: ->(v) { v.id },                                              requires_with: false },
          title:    { key: ->(v) { v.title.to_s.downcase },                             requires_with: false },
          channel:    { key: ->(v) { v.channel.at_handle.to_s.downcase },               requires_with: true },
          visibility: { key: ->(v) { v.privacy_status.to_s },                           requires_with: true },
          game:     { key: ->(v) { v.linked_games.map(&:title).join(", ").downcase },   requires_with: true },
          duration: { key: ->(v) { v.duration_seconds.to_i },                           requires_with: true },
          views:    { key: ->(v) { v.view_count.to_i },                                 requires_with: true },
          likes:    { key: ->(v) { v.like_count.to_i },                                 requires_with: true },
          comments: { key: ->(v) { v.comment_count.to_i },                              requires_with: true }
        }.freeze

        # Maps every sort token (downcased) → canonical column Symbol.
        SORT_VOCAB = {
          "id"      => :id,
          "title"   => :title,
          "channel" => :channel,
          "handle"  => :channel,
          "@handle" => :channel,
          "visibility" => :visibility,
          "game"    => :game,
          "games"   => :game,
          "duration" => :duration,
          "views"   => :views,
          "likes"   => :likes,
          "comments" => :comments
        }.freeze

        COLUMNS = {
          channel:  {
            aliases:    %w[channel],
            heading:    "Channel",
            cell_class: "text-cyan pito-cell-channel",
            value:      ->(v) { v.channel.at_handle }
          },
          visibility: {
            aliases:     %w[visibility],
            heading_key: "pito.copy.videos.columns.visibility",
            value:       ->(v) { visibility_label(v) }
          },
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

        # Display tokens in COLUMNS order — the primary alias for each column.
        # Used by ListClauseGhost to build autocomplete candidates.
        def suggestion_tokens
          COLUMNS.keys.map { |canonical| DISPLAY_TOKEN_MAP[canonical] }
        end

        # Returns the display token String for a canonical Symbol.
        #   display_token(:duration) # => "duration"
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

        # Returns an Array of heading strings for the requested canonical columns.
        #
        # @param cols [Array<Symbol>] ordered canonical column keys
        # @return [Array<String>]
        def headings(cols)
          cols.map do |col|
            cfg = COLUMNS.fetch(col)
            cfg[:heading_key] ? Pito::Copy.render(cfg[:heading_key]) : cfg[:heading]
          end
        end

        # Returns an Array of cell hashes for the requested canonical columns.
        #
        # @param video [::Video]
        # @param cols  [Array<Symbol>] ordered canonical column keys
        # @return [Array<{ text: String, class: String }>]
        def cells(video, cols)
          cols.map do |col|
            cfg = COLUMNS.fetch(col)
            { text: cfg[:value].call(video), class: cfg[:cell_class] || "text-fg-dim" }
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

        # Returns "—" for a nil count, or the stringified integer.
        def count_text(n)
          n.nil? ? "—" : n.to_s
        end

        # Human label for a video's privacy_status (the "Visibility" column).
        def visibility_label(video)
          status = video.privacy_status
          return "" if status.blank?

          I18n.t("pito.video.detail.privacy_status.#{status}", default: status.to_s.capitalize)
        end
        private :count_text, :visibility_label
      end
    end
  end
end
