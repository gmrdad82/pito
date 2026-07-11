# frozen_string_literal: true

module Pito
  module Chat
    module Handlers
      # Handler for the `search` chat verb — relevance search over the library.
      #
      #   search games like <title>   → a list-style card headed by the seed game
      #                                 itself (its title IS the closest match),
      #                                 followed only by the RELEVANT games,
      #                                 reusing the game_list card so #id
      #                                 show/link/analyze, sort/with, and
      #                                 more/next paging all work.
      #
      # The seed title is everything after `like`; the noun (`games`) is decorative.
      # The full ranked result is stamped into the list_cursor as `ranked_ids` so
      # the game_list pager (Pito::FollowUp::Handlers::GameList#list_next_games)
      # pages the ranking instead of replaying a list query.
      class Search < Pito::Chat::Handler
        self.verb = :search
        self.description_key = "pito.chat.search.descriptions.search"

        # "search games like tekken 7" → captures "tekken 7".
        LIKE_CLAUSE = /\blike\b\s+(.+?)\s*\z/i

        # Blended-score gate for a seed with NO genres on record (see #relevant).
        NO_GENRE_FLOOR = 40

        def call
          seed_title = extract_seed
          return needs_seed if seed_title.blank?

          seed = ::Game.resolve_by_title(seed_title)
          return seed_not_found(seed_title) if seed.nil?

          ranked = Pito::Recommendation::GameSimilarity.call(seed, limit: nil)
          rows   = [ seed, *relevant(seed, ranked).map(&:game) ]

          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: build_payload(rows) } ])
        end

        private

        def extract_seed
          m = message.raw.to_s.match(LIKE_CLAUSE)
          m && m[1].strip
        end

        # Real relevance, not fill-up. The recommendation kernel ranks EVERY
        # candidate above its deliberately near-noise floor (it feeds the channel
        # directions, where weak-but-real matches still matter), so search applies
        # its own gate on top: a game is relevant when it shares at least one
        # genre with the seed (the `g` breakdown signal carries jaccard > 0) —
        # perspective/theme overlap alone (side-view platformers vs a fighting
        # game) is not relevance. A seed with no genres on record falls back to a
        # blended-score floor so an unsynced seed still returns its nearest
        # neighbors instead of the whole library.
        def relevant(seed, ranked)
          if seed.genres.any?
            ranked.select { |r| r.breakdown[:g].to_f > 0 }
          else
            ranked.select { |r| r.score >= NO_GENRE_FLOOR }
          end
        end

        def build_payload(games)
          page    = page_size
          rows    = games.first(page)
          payload = Pito::MessageBuilder::Game::List.call(rows, conversation:, columns: [])

          if games.size > page
            payload["list_cursor"] = {
              "ranked_ids"     => games.map(&:id),
              "offset"         => page,
              "raw"            => "",
              "channel"        => nil,
              "sort_token"     => nil,
              "sort_direction" => nil,
              "columns"        => []
            }
            more_text = Pito::Copy.render(
              "pito.copy.list_more",
              count: rows.size,
              total: games.size,
              rest:  games.size - rows.size,
              verb:  Pito::Dispatch::Config.pager(verb: :list)[:more_verb]
            )
            payload["list_footer"] = [ payload["list_footer"].presence, more_text ].compact.join(" ")
          end

          payload
        end

        def page_size
          Pito::Dispatch::Config.pager(verb: :list)[:page_size]
        end

        def needs_seed
          text("pito.chat.search.needs_seed")
        end

        def seed_not_found(title)
          text("pito.chat.search.seed_not_found", title: title)
        end

        def text(key, **args)
          Pito::Chat::Result::Ok.new(consume: false, events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call(key, **args) }
          ])
        end
      end
    end
  end
end
