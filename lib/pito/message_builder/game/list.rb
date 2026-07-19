# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the payload for the game library list message.
      #
      # Returns a table_rows payload listing every game (sorted by title) with
      # its ID as the key. Stamped follow-up-able (reply_target: "game_list") so
      # the user can reply `#<handle> show <id>` / `#<handle> rm <id>`.
      module List
        module_function

        # @param games        [ActiveRecord::Relation | Array<::Game>] pre-fetched, sorted games.
        # @param conversation [Conversation] used to generate the reply handle.
        # @param columns      [Array<Symbol>] extra canonical column keys (from ListColumns).
        # @param intro        [String, nil] pre-rendered html_safe body overriding the
        #   default count intro (e.g. the upcoming soon/later horizon intros).
        # @param scores       [Hash{Integer => Integer}, nil] optional game_id => 0..100 score
        #   map (search's `like` path). When present, a trailing Match column is appended to
        #   the heading and every row via the `{ score: }` data-grid cell contract (renders a
        #   score bar — see Pito::Event::SystemComponent#normalized_cell). nil (every other
        #   caller: `list games`, `search games for`, follow-up pagers) → no Match column,
        #   output identical to before this param existed.
        # @param channels [Array<String>] distinct @handles for the FULL (un-paginated) result
        #   set — decided once by the chat handler, never per-page. Appended to the intro body
        #   as a reference clause via Pito::Lists::ChannelReference: one handle names itself,
        #   several enumerate with a cap. Ignored when `intro:` is given (a caller supplying
        #   its own pre-rendered body owns the whole thing). [] (every other caller) → no
        #   clause, output identical to before this param existed.
        # @param suppressed_columns [Array<Symbol>] columns withheld for THIS list only (e.g.
        #   :channels when `channels` collapses to a single handle) — excluded from the options
        #   footer's addable set and stamped so with/without follow-ups can reject them too.
        # @return [Hash] string-keyed payload with body, table_rows, and follow-up fields.
        def call(games, conversation:, columns: [], intro: nil, scores: nil, channels: [], suppressed_columns: [])
          cols       = ListColumns.canonical_order(columns)
          suppressed = Array(suppressed_columns).map(&:to_sym)
          # When the price column is shown, align its numbers on the decimal by
          # padding each integer part to the table-max width (figure-spaces).
          price_pad = cols.include?(:price) ? ListColumns.price_pad_int(games) : nil
          payload = {
            "body"          => intro || Pito::Lists::ChannelReference.append(
              Pito::Copy.render_html(
                "pito.copy.games.list_intro",
                { count: games.size, noun: games.size == 1 ? "game" : "games" },
                shimmer: [ :count, :noun ]
              ),
              channels
            ),
            "html"          => true,
            "table_heading" => [
              { "text" => "#", "class" => "text-right" },
              "Game",
              *ListColumns.heading_cells(cols),
              # Search's `like` path only (scores present) — a literal structural
              # label, same as the plain-string "Game" heading above. Deliberately
              # "Match", not "Score"/"Similarity": a game like-score is a 10-signal
              # blend (Pito::Recommendation::GameSimilarity — embedding is only
              # ONE small weighted input), not a raw embedding similarity, so it
              # earns a label distinct from the vid/conversation `like` paths'
              # "Similarity" heading (100% raw cosine, rescaled — see
              # Pito::Recommendation::DisplayScore).
              *(scores ? [ "Match" ] : [])
            ],
            "shimmer_heading" => true,
            "fixed_leading"  => (cols & %i[platform]).size,
            "fixed_trailing" => (cols & %i[footage]).size,
            "table_rows"    => games.map { |game|
              id_text = "##{game.id}"
              {
                cells: [
                  {
                    text:  id_text,
                    class: Pito::Shimmer::TokenComponent.css_class(id_text, extra: "tabular-nums text-right whitespace-nowrap", clickable: true),
                    # Click-to-open: clicking the cell auto-submits `show game
                    # #<id>` via the chat-prefill seam (J6). Clickable ⇒ yellow.
                    data:  Pito::Shimmer::TokenComponent.prefill_data("show game #{id_text}", submit: true)
                  },
                  { text: game.title, class: "text-fg pito-cell-title" },
                  *ListColumns.cells(game, cols, price_pad_int: price_pad),
                  # { score: } cell contract (SystemComponent#normalized_cell) —
                  # renders a ScoreBarComponent instead of plain text.
                  *(scores ? [ { score: scores[game.id] } ] : [])
                ]
              }
            },
            # Stamped for with/without column mutations: allows the handler to
            # reload the same games and rebuild with an updated column set.
            "game_ids"      => games.map(&:id),
            "list_columns"  => cols.map(&:to_s),
            # Stamped so with/without follow-ups (and later pages) can keep
            # rejecting a per-list-suppressed column instead of silently
            # re-adding it — see Pito::FollowUp::Handlers::GameList#mutate_columns.
            "suppressed_columns" => suppressed.map(&:to_s),
            "list_footer"   => ListColumns.options_footer(cols, suppressed:)
          }
          Pito::FollowUp.make_followupable!(payload, target: "game_list", conversation: conversation)
          payload
        end
      end
    end
  end
end
