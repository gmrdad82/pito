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
          "comms"    => :comments,
          "comments" => :comments
        }.freeze

        COLUMNS = {
          channel:  {
            aliases:    %w[channel],
            heading:    "Channel",
            cell_class: "pito-cell-channel",
            value:      ->(v) { v.channel.at_handle }
          },
          visibility: {
            aliases:     %w[visibility status],
            heading_key: "pito.copy.videos.columns.visibility",
            cell_class:  "text-fg-dim pito-cell-visibility",
            value:       ->(v) { visibility_label(v) }
          },
          game:     {
            aliases:    %w[game games],
            heading:    "Game",
            html:       true,
            cell_class: "text-fg-dim pito-cell-game",
            value:      ->(v) { linked_games_html(v) }
          },
          duration: {
            aliases:    %w[length duration],
            heading:    "Length",
            align:      :right,
            cell_class: "text-fg-dim text-right tabular-nums pito-cell-duration",
            value:      ->(v) { Pito::Formatter::Duration.call(v.duration_seconds) || "—" }
          },
          views:    {
            aliases:    %w[views],
            heading:    "Views",
            align:      :right,
            cell_class: "text-fg-dim text-right tabular-nums",
            value:      ->(v) { count_text(v.view_count) }
          },
          likes:    {
            aliases:    %w[likes],
            heading:    "Likes",
            align:      :right,
            cell_class: "text-fg-dim text-right tabular-nums",
            value:      ->(v) { count_text(v.like_count) }
          },
          comments: {
            aliases:    %w[comms comments],
            heading:    "Comments",
            align:      :right,
            cell_class: "text-fg-dim text-right tabular-nums",
            value:      ->(v) { count_text(v.comment_count) }
          },
          # YouTube category (Gaming, People & Blogs, …). Last in canonical order, so
          # the viewport auto-fill only surfaces it on the widest viewports; also
          # addable/removable via `with category` / `without category`.
          category: {
            aliases:    %w[category categories],
            heading:    "Category",
            cell_class: "text-fg-dim pito-cell-category",
            value:      ->(v) { v.category_name.presence || "—" }
          }
        }.freeze

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
          cols.map { |col| heading_text(col) }
        end

        # Returns heading entries for the requested canonical columns. Left-aligned
        # columns return a plain String; right-aligned columns (align: :right)
        # return a Hash { "text" => heading, "class" => "text-right" } so
        # SystemComponent merges the alignment into the heading cell class.
        #
        # @param cols [Array<Symbol>] ordered canonical column keys
        # @return [Array<String, Hash>]
        def heading_cells(cols)
          cols.map do |col|
            cfg   = COLUMNS.fetch(col)
            klass = "pito-table-heading--added"
            klass += " text-right" if cfg[:align] == :right
            { "text" => heading_text(col), "class" => klass }
          end
        end

        # E7 options footer — per-surface column and sort summary.
        #
        # Derives the three OptionsFooter inputs from the currently-visible column
        # set and delegates rendering to Pito::Lists::OptionsFooter. Recomputes on
        # every List.call, so with/without follow-ups update it automatically.
        #
        # addable   — available columns not yet shown (COLUMNS.keys − cols)
        # removable — all currently-visible optional columns (cols; id+title are
        #             hardcoded and cannot be removed)
        # sort_keys — base sort tokens (id, title) + the primary sort token for
        #             each visible optional column. Columns absent from SORT_VOCAB
        #             (e.g. :category, which has no sort key) are excluded via
        #             compact.
        def options_footer(cols)
          addable   = (COLUMNS.keys - cols).map { |c| display_token(c) }
          removable = cols.map { |c| display_token(c) }
          sort_keys = base_sort_tokens + cols.map { |c| SORT_VOCAB.key(c) }.compact
          Pito::Lists::OptionsFooter.call(addable:, removable:, sort_keys:)
        end

        # Resolves a single column's heading String (copy-keyed or literal).
        def heading_text(col)
          cfg = COLUMNS.fetch(col)
          cfg[:heading_key] ? Pito::Copy.render(cfg[:heading_key]) : cfg[:heading]
        end

        # Returns an Array of cell hashes for the requested canonical columns.
        #
        # @param video [::Video]
        # @param cols  [Array<Symbol>] ordered canonical column keys
        # @return [Array<{ text: String, class: String }>]
        def cells(video, cols)
          cols.map do |col|
            cfg  = COLUMNS.fetch(col)
            text = cfg[:value].call(video)
            klass = if col == :channel
                      # Shimmer owns the colour; seed with video.id so repeated
                      # @handles down the list land in different offset buckets.
                      Pito::Shimmer::TokenComponent.css_class(text, extra: "pito-cell-channel", seed: video.id)
            else
                      cfg[:cell_class] || "text-fg-dim"
            end
            { text:, class: klass, html: cfg[:html] == true }
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

        # html_safe "#<id> <title>" per linked game, comma-joined. Each `#<id>` is
        # a cyan shimmer token (same component as the vid `#` id column) that, when
        # clicked, auto-submits `show game #<id>` — a show affordance, NOT a reply
        # (the :system list keeps its own video_list repliability). "—" when none.
        def linked_games_html(video)
          games = video.linked_games
          return "—" if games.empty?

          helpers = ActionController::Base.helpers
          helpers.safe_join(
            games.map do |game|
              id_text = "##{game.id}"
              token = helpers.tag.span(
                id_text,
                class: Pito::Shimmer::TokenComponent.css_class(id_text, extra: "tabular-nums whitespace-nowrap", seed: video.id, clickable: true),
                data:  Pito::Shimmer::TokenComponent.prefill_data("show game #{id_text}", submit: true)
              )
              helpers.safe_join([ token, " ", game.title ])
            end,
            ", "
          )
        end

        # Human label for a video's visibility column. A scheduled video (future
        # publish_at) shows "Scheduled"; otherwise the privacy_status label
        # (Public / Unlisted / Private).
        def visibility_label(video)
          if video.publish_at.present? && video.publish_at > Time.current
            return I18n.t("pito.video.detail.privacy_status.scheduled", default: "Scheduled")
          end

          status = video.privacy_status
          return "" if status.blank?

          I18n.t("pito.video.detail.privacy_status.#{status}", default: status.to_s.capitalize)
        end
        private :count_text, :visibility_label
      end
    end
  end
end
