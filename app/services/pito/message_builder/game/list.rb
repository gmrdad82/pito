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
        # @return [Hash] string-keyed payload with body, table_rows, and follow-up fields.
        def call(games, conversation:, columns: [])
          cols    = ListColumns.canonical_order(columns)
          payload = {
            "body"          => Pito::Copy.render(
              "pito.copy.games.list_intro",
              count: games.size,
              noun:  games.size == 1 ? "game" : "games"
            ),
            "table_heading" => [
              { "text" => "#", "class" => "text-right" },
              "Game",
              *ListColumns.heading_cells(cols)
            ],
            "fixed_trailing" => (cols & %i[release_date year]).size,
            "table_rows"    => games.map { |game|
              {
                cells: [
                  { text: "##{game.id}", class: "text-cyan tabular-nums text-right whitespace-nowrap" },
                  { text: game.title,    class: "text-fg" },
                  *ListColumns.cells(game, cols)
                ]
              }
            },
            # Stamped for add/remove column mutations: allows the handler to
            # reload the same games and rebuild with an updated column set.
            "game_ids"      => games.map(&:id),
            "list_columns"  => cols.map(&:to_s)
          }
          Pito::FollowUp.make_followupable!(payload, target: "game_list", conversation: conversation)
          payload
        end
      end
    end
  end
end
