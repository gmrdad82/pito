# frozen_string_literal: true

module Pito
  module Chat
    module Handlers
      # Handler for the `search` chat verb (#8) — similarity search.
      #
      #   search games like <title>   → a list-style card of games most similar to
      #                                 <title> (semantic similarity via
      #                                 Recommendation::GameSimilarity), reusing the
      #                                 game_list card so #id show/link/analyze,
      #                                 sort/with, and more/next paging all work.
      #
      # The seed title is everything after `like`; the noun (`games`) is decorative.
      # The full ranked result is stamped into the list_cursor as `ranked_ids` so
      # the game_list pager (Pito::FollowUp::Handlers::GameList#list_next_games)
      # pages the similarity ranking instead of replaying a list query.
      class Search < Pito::Chat::Handler
        self.verb = :search
        self.description_key = "pito.chat.search.descriptions.search"

        # "search games like tekken 7" → captures "tekken 7".
        LIKE_CLAUSE = /\blike\b\s+(.+?)\s*\z/i

        def call
          seed_title = extract_seed
          return needs_seed if seed_title.blank?

          seed = ::Game.resolve_by_title(seed_title)
          return seed_not_found(seed_title) if seed.nil?

          ranked = Pito::Recommendation::GameSimilarity.call(seed, limit: nil).map(&:game)
          return no_matches(seed) if ranked.empty?

          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: build_payload(ranked) } ])
        end

        private

        def extract_seed
          m = message.raw.to_s.match(LIKE_CLAUSE)
          m && m[1].strip
        end

        def build_payload(ranked)
          page    = page_size
          rows    = ranked.first(page)
          payload = Pito::MessageBuilder::Game::List.call(rows, conversation:, columns: [])

          if ranked.size > page
            payload["list_cursor"] = {
              "ranked_ids"     => ranked.map(&:id),
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
              total: ranked.size,
              rest:  ranked.size - rows.size,
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

        def no_matches(seed)
          text("pito.chat.search.no_matches", title: seed.title)
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
