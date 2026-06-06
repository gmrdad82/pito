# frozen_string_literal: true

# Handler for the `list` chat verb → the game library.
#
# Emits a System message listing every game (title-sorted) with its **ID** as the
# key, so the follow-up affordances (`#<handle> show <id>` / `rm <id>`) key off
# the stable id, not the title. Stamped follow-up-able (`game_list`). Empty
# library returns a witty empty-state. All copy via `Pito::Copy`.
#
# NOTE: `game`/`games` are FILLER words in the grammar, so `list` and
# `list games` parse identically — both land here. (Noun disambiguation for
# `list videos`/`list channels` is future work.)
module Pito
  module Chat
    module Handlers
      class List < Pito::Chat::Handler
        self.verb = :list
        self.description_key = "pito.chat.list.descriptions.list"

        def call
          games = ::Game.order(:title)
          return empty_result if games.empty?

          payload = {
            body:       Pito::Copy.render("pito.copy.games.list_intro", { count: games.size }),
            table_rows: games.map { |game| { key: "##{game.id}", value: game.title } }
          }
          Pito::FollowUp.make_followupable!(payload, target: "game_list", conversation:)

          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: payload } ])
        end

        private

        def empty_result
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: { text: Pito::Copy.render("pito.copy.games.list_empty") } }
          ])
        end
      end
    end
  end
end
