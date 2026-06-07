# frozen_string_literal: true

class Game
  module Igdb
    # Resolves an IGDB game (by `igdb_id`) into the local Library and triggers a
    # sync. Existing game → **resync** (no duplicate); unknown game → create a
    # stub then sync. Either way `GameIgdbSync` fetches the full record.
    #
    #   Game::Igdb::Importer.call(igdb_id: 1020, title: "Lies of P")
    #   # => { game: #<Game…>, action: :import | :resync }
    module Importer
      module_function

      def call(igdb_id:, title: nil)
        id = Integer(igdb_id)
        game = ::Game.find_by(igdb_id: id)
        action = game ? :resync : :import
        game ||= ::Game.create!(igdb_id: id, **stub_attrs(title))

        GameIgdbSync.perform_later(game.id)
        { game: game, action: action }
      end

      def stub_attrs(title)
        title.to_s.strip.present? ? { title: title.to_s.strip } : {}
      end
    end
  end
end
