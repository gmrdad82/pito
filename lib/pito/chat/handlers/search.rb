# frozen_string_literal: true

module Pito
  module Chat
    module Handlers
      # Handler for the `search` chat tool — relevance search over the library.
      #
      #   search games like <title>  → UNCHANGED: the GameSimilarity ranking with
      #                                the genre-gate, a list-style card headed by
      #                                the seed game itself (its title IS the
      #                                closest match), followed only by the
      #                                RELEVANT games.
      #   search games for <title>   → lexical matching: a case-insensitive
      #                                substring match over every owner-visible
      #                                detail field `show game` renders — title,
      #                                summary, alternative_names, platforms,
      #                                themes, player_perspectives, genre names,
      #                                and developer/publisher company names.
      #                                "tekken" still returns the games actually
      #                                TITLED Tekken-something; "capcom" or
      #                                "beat 'em up" now finds a game via its
      #                                detail card even when neither word is in
      #                                the title (that broader recall is what
      #                                distinguishes `for` from a straight title
      #                                lookup; ranked similarity is `like`'s job).
      #                                Title-ordered, deterministic.
      #   search games <title>       → bare = `for` semantics (#owner 2026-07-15:
      #                                bare means EXACT, not similar, under the
      #                                3.0.0 like/for grammar split).
      #   search vids like <title>   → seed-based: resolve the seed vid, then
      #                                its nearest embedding neighbors
      #                                (Video::EMBEDDING_COLUMN, cosine),
      #                                scored via Pito::Recommendation::
      #                                DisplayScore (raw cosine similarity
      #                                rescaled from the measured VID_FLOOR —
      #                                NOT games' blended `like` formula) —
      #                                the seed leads at 100.
      #   search vids for <text>     → lexical multi-field match over title,
      #                                description, and tags (mirrors games'
      #                                `for` EXISTS-query style, one
      #                                parameterized `:q`).
      #
      # Both the games AND the vids paths render through their own SAME
      # list card/payload shape (build_payload / build_video_payload) so #id
      # and sort behave identically regardless of which path produced the
      # rows. Paging does NOT: games stamp a `list_cursor` and a "more
      # results" footer (the game_list follow-up handler reads it back to
      # page the ranking); vids show a single page with no `next`/`more`
      # affordance at all, because the vid follow-up handler doesn't carry
      # that cursor (see build_video_payload).
      #
      # The noun (games/conversations/vids — Pito::Grammar::Registry's
      # :search_nouns vocabulary, config/pito/tools.yml) defaults to games
      # when absent. `search conversations …` has no handler of its own yet
      # — a parallel 3.0.0 task adds Pito::Chat::Handlers::SearchConversations;
      # until it's defined this falls back to the same "search for what?"
      # copy a blank query gets, rather than inventing new user-facing text
      # for a feature that isn't built.
      #
      # The `like` path's full ranked result is stamped into the list_cursor as
      # `ranked_ids` so the game_list pager (Pito::FollowUp::Handlers::GameList
      # #list_next_games) pages the ranking instead of replaying a list query.
      # The `for` path reuses the exact same cursor mechanism to page its
      # title-ordered id list — "ranked_ids" just means "the full ordered id
      # list from page 1", not necessarily a similarity ranking.
      class Search < Pito::Chat::Handler
        self.tool = :search
        self.description_key = "pito.chat.search.descriptions.search"

        # "search games like tekken 7" → captures "tekken 7". FOR_CLAUSE mirrors
        # it byte-for-byte — same clause shape, different keyword — so a bare
        # query (neither keyword present) can fall through to `for` semantics.
        LIKE_CLAUSE = /\blike\b\s+(.+?)\s*\z/i
        FOR_CLAUSE  = /\bfor\b\s+(.+?)\s*\z/i

        # The noun, when typed, always immediately follows the tool word per the
        # slot order config declares (noun before the free query) — stripping
        # only that leading pair isolates a bare (keyword-less) query.
        NOUN_PREFIX = /\A(?:games?|conversations?|vids?|videos?)\b\s*/i

        # Blended-score gate for a seed with NO genres on record (see #relevant).
        NO_GENRE_FLOOR = 40

        def call
          return delegate_conversations if noun == "conversations"

          mode, term = extract_query
          return needs_seed if term.blank?

          if noun == "vids"
            mode == :like ? search_like_vid(term) : search_for_vid(term)
          else
            mode == :like ? search_like(term) : search_for(term)
          end
        end

        private

        # ── noun routing ─────────────────────────────────────────────────────

        # "games", "conversations", or "vids" (search_nouns' members), defaulting
        # to "games" — today's behavior — when the second token isn't a noun at
        # all (it's a `like`/`for` keyword, or the start of a titled/bare query).
        def noun
          @noun ||= begin
            vocab = Pito::Grammar::Registry.vocabulary(:search_nouns)
            token = message.raw.to_s.strip.split(/\s+/)[1]
            vocab.resolve(token.to_s) || "games"
          end
        end

        # `search conversations …` — delegate through the same uniform
        # call(kwargs:, context:) contract every dispatch tool answers, once
        # SearchConversations exists. Until then, no conversation search exists
        # at all, so this reuses `needs_seed` rather than invent new copy for an
        # unbuilt feature.
        def delegate_conversations
          return needs_seed unless defined?(Pito::Chat::Handlers::SearchConversations)

          Pito::Chat::Handlers::SearchConversations.call(
            kwargs:,
            context: Pito::Dispatch::Context.new(
              message:, conversation:, channel:, period:, follow_up:, viewport_width:
            )
          )
        end

        # ── query parsing ────────────────────────────────────────────────────

        # [:like, term] | [:for, term]. `like` wins when both keywords somehow
        # appear (pre-3.0.0 precedence — `like` was the only keyword). No
        # keyword at all → :for on the whole remainder (bare = exact).
        def extract_query
          raw = message.raw.to_s
          if (m = raw.match(LIKE_CLAUSE))
            [ :like, m[1].strip ]
          elsif (m = raw.match(FOR_CLAUSE))
            [ :for, m[1].strip ]
          else
            [ :for, bare_query(raw) ]
          end
        end

        # Strips the tool word and an immediately-following noun token, leaving
        # whatever's left as the bare (keyword-less) query.
        def bare_query(raw)
          raw.strip.sub(/\Asearch\b\s*/i, "").sub(NOUN_PREFIX, "").strip
        end

        # ── `like` path (unchanged ranking) ─────────────────────────────────

        def search_like(title)
          seed = ::Game.resolve_by_title(title)
          return seed_not_found(title) if seed.nil?

          ranked            = Pito::Recommendation::GameSimilarity.call(seed, limit: nil)
          relevant_results  = relevant(seed, ranked)
          rows              = [ seed, *relevant_results.map(&:game) ]
          # The seed IS the query, not a ranked candidate — it never comes back
          # from GameSimilarity, so it has no natural score. It leads row 0 as
          # the exact/identical match, so 100 (the top of the same 0..100 scale
          # every other score bar uses) is the sensible stand-in.
          scores = { seed.id => 100, **relevant_results.to_h { |r| [ r.game.id, r.score ] } }

          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: build_payload(rows, scores: scores) } ])
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

        # ── `for` path (exact-name matching) ────────────────────────────────

        def search_for(term)
          games = matching_games(term)
          return no_matches if games.empty?

          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: build_payload(games) } ])
        end

        # Case-insensitive substring over every owner-visible text/detail surface
        # `show game` renders: the plain columns (title, summary), the text[]
        # array columns (alternative_names, platforms, themes,
        # player_perspectives — matched via the same `unnest` EXISTS pattern
        # GameListFilter's platform filter uses), and the joined genre /
        # developer / publisher names (matched via the analogous
        # `EXISTS (SELECT 1 FROM <join table> JOIN <table> …)` subquery so
        # nothing outer-joins `games` and fans a row out twice). There is no
        # `games.description` column on the schema (only `summary`), so it's
        # not part of the WHERE. Every clause reuses the single `:q` bind — one
        # parameterized query, never string interpolation. Because every
        # additional clause is an EXISTS subquery (not a JOIN), `games` itself
        # is never joined to a multi-row child table, so a game matching in
        # several fields still surfaces as exactly one row — no `.distinct`
        # needed (and `.distinct` would conflict with the `LOWER(title)`
        # ORDER BY expression below: Postgres requires SELECT DISTINCT's ORDER
        # BY expressions to appear in the select list). Title-ASC + id
        # tiebreak keeps ordering deterministic across pages (mirrors
        # Game.picker_page's LOWER(title)/id ordering).
        def matching_games(term)
          like = "%#{term}%"
          ::Game
            .where(
              "games.title ILIKE :q " \
              "OR games.summary ILIKE :q " \
              "OR EXISTS (SELECT 1 FROM unnest(games.alternative_names) AS alt WHERE alt ILIKE :q) " \
              "OR EXISTS (SELECT 1 FROM unnest(games.platforms) AS platform WHERE platform ILIKE :q) " \
              "OR EXISTS (SELECT 1 FROM unnest(games.themes) AS theme WHERE theme ILIKE :q) " \
              "OR EXISTS (SELECT 1 FROM unnest(games.player_perspectives) AS perspective WHERE perspective ILIKE :q) " \
              "OR EXISTS (" \
              "  SELECT 1 FROM game_genres " \
              "  JOIN genres ON genres.id = game_genres.genre_id " \
              "  WHERE game_genres.game_id = games.id AND genres.name ILIKE :q" \
              ") " \
              "OR EXISTS (" \
              "  SELECT 1 FROM game_developers " \
              "  JOIN companies ON companies.id = game_developers.company_id " \
              "  WHERE game_developers.game_id = games.id AND companies.name ILIKE :q" \
              ") " \
              "OR EXISTS (" \
              "  SELECT 1 FROM game_publishers " \
              "  JOIN companies ON companies.id = game_publishers.company_id " \
              "  WHERE game_publishers.game_id = games.id AND companies.name ILIKE :q" \
              ")",
              q: like
            )
            .order(Arel.sql("LOWER(games.title) ASC, games.id ASC"))
            .to_a
        end

        # ── vids `like` path (embedding-neighbor ranking) ───────────────────

        # Seed-based, mirroring search_like's shape: resolve the seed vid,
        # rank its nearest embedding neighbors, lead with the seed at a 100
        # score. Unlike games (which blends genre/facet signals even without
        # an embedding), a vid has no facet fallback — an unembedded seed
        # degrades to the same empty-state reply a `for` miss gets rather
        # than erroring on a nil vector.
        def search_like_vid(title)
          seed = ::Video.resolve_by_title(title)
          return seed_not_found_vid(title) if seed.nil?
          return no_matches if seed.embedding_vector.blank?

          similar = seed.nearest_neighbors(::Video::EMBEDDING_COLUMN, distance: "cosine").limit(page_size)
          # Same 100 stand-in as games' seed score (see search_like) — the
          # seed IS the query, not a ranked neighbor, so it never comes back
          # from nearest_neighbors with a distance of its own.
          scores = { seed.id => 100, **similar.to_h { |v| [ v.id, vid_score(v.neighbor_distance) ] } }

          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: build_video_payload([ seed, *similar ], scores: scores) } ])
        end

        # A vid's `like` score is 100% raw cosine similarity — no blend to
        # dilute it, unlike games' 10-signal score (Pito::Recommendation::
        # Signals.embedding, untouched, feeds THAT blend only). Measured prod
        # data (2026-07-16) showed the vid embedding space is tight enough
        # that two random unrelated vids already score ~88/100 under the old
        # raw-cosine-×100 formula — so this rescales from
        # Pito::Recommendation::DisplayScore::VID_FLOOR (the measured
        # random-pair baseline) instead, so the bar actually discriminates.
        def vid_score(distance)
          Pito::Recommendation::DisplayScore.display_score(
            1.0 - distance.to_f, floor: Pito::Recommendation::DisplayScore::VID_FLOOR
          ).round
        end

        # ── vids `for` path (lexical multi-field matching) ──────────────────

        def search_for_vid(term)
          videos = matching_videos(term)
          return no_matches if videos.empty?

          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: build_video_payload(videos) } ])
        end

        # Case-insensitive substring over title, description, and the tags
        # text[] array (matched via the same `unnest` EXISTS pattern
        # matching_games uses for its own array columns) — mirrors
        # matching_games' single-parameterized-`:q`, EXISTS-not-JOIN shape,
        # so no `.distinct` is needed here either. Title-ASC + id tiebreak
        # keeps ordering deterministic across pages.
        def matching_videos(term)
          like = "%#{term}%"
          ::Video
            .where(
              "videos.title ILIKE :q " \
              "OR videos.description ILIKE :q " \
              "OR EXISTS (SELECT 1 FROM unnest(videos.tags) AS tag WHERE tag ILIKE :q)",
              q: like
            )
            .order(Arel.sql("LOWER(videos.title) ASC, videos.id ASC"))
            .to_a
        end

        # ── shared payload/pager ─────────────────────────────────────────────

        # @param scores [Hash{Integer => Integer}, nil] game_id => 0..100 score map from
        #   search_like; nil for search_for — Game::List only renders a Score column when
        #   this is present, so the `for` path (and every other Game::List caller) is
        #   untouched.
        def build_payload(games, scores: nil)
          page    = page_size
          rows    = games.first(page)
          payload = Pito::MessageBuilder::Game::List.call(rows, conversation:, columns: [], scores:)
          # scores present == like (semantic) mode; nil == for (lexical) mode
          # — same mapping build_video_payload uses below.
          payload["list_footer"] = Pito::Copy.render(scores ? "pito.copy.search.footer_like" : "pito.copy.search.footer_for")

          if games.size > page
            payload["list_cursor"] = {
              "ranked_ids"     => games.map(&:id),
              "offset"         => page,
              "raw"            => "",
              "channel"        => nil,
              "sort_token"     => nil,
              "sort_direction" => nil,
              "columns"        => [],
              # Owning tool, read by GameList#cursor_tool so `next`/`more` pages
              # at search's page size (20), not :list's (50).
              "tool"           => "search"
            }
            more_text = Pito::Copy.render(
              "pito.copy.list_more",
              count: rows.size,
              total: games.size,
              rest:  games.size - rows.size,
              tool:  pager[:more_tool]
            )
            payload["list_footer"] = [ payload["list_footer"].presence, more_text ].compact.join(" ")
          end

          payload
        end

        # @param scores [Hash{Integer => Integer}, nil] video_id => 0..100 score map from
        #   search_like_vid; nil for search_for_vid — Video::List only renders a Score column
        #   when this is present, matching build_payload's games contract.
        #
        # Deliberately single-page: unlike game_list's follow-up handler
        # (Pito::FollowUp::Handlers::GameList#list_next_games), video_list's
        # (Pito::FollowUp::Handlers::VideoList#list_next_videos) does not read a
        # stamped `ranked_ids`/`tool` cursor at all — it always replays a fresh,
        # unranked `list videos` query, which would silently drop the original
        # ranking/query on any later page. So no `list_cursor` is stamped and no
        # "more results" pager text is appended here; a `search vids …` result
        # always shows just its first page (already capped at search's page
        # size), with no `next`/`more` affordance offered. Video::List's own
        # with/without-columns footer is untouched. Revisit once video_list's
        # follow-up handler gains cursor-aware replay (SUX5b) — then the pager
        # can return.
        def build_video_payload(videos, scores: nil)
          rows    = videos.first(page_size)
          payload = Pito::MessageBuilder::Video::List.call(rows, conversation:, columns: [], scores:)
          # scores present == like (semantic) mode; nil == for (lexical) mode
          # — overwrites Video::List's default columns footer with the
          # generic search footer (vids don't paginate, so nothing else is
          # appended after it, unlike build_payload's games pager above).
          payload["list_footer"] = Pito::Copy.render(scores ? "pito.copy.search.footer_like" : "pito.copy.search.footer_for")
          # Re-stamp the generic video_list target: search-vids is single-page
          # (see the comment above), so it uses its own video_search reply
          # target — no pager/sort replies, which don't apply here.
          payload["reply_target"] = "video_search"
          payload
        end

        def page_size
          pager[:page_size]
        end

        # THIS tool's pager (page_size 20, config/pito/tools.yml concerns.pager)
        # — not :list's 50. Search is its own paged surface with its own
        # page-size contract.
        def pager
          @pager ||= Pito::Dispatch::Config.pager(tool: :search)
        end

        # ── replies ──────────────────────────────────────────────────────────

        def needs_seed
          text("pito.chat.search.needs_seed")
        end

        def seed_not_found(title)
          text("pito.chat.search.seed_not_found", title: title)
        end

        # Vids' seed-not-found reuses the same copy `show vid <ref>` renders on
        # an unresolved ref (Pito::Chat::Handlers::Show#video_not_found) rather
        # than inventing a vids-specific variant of seed_not_found's game copy.
        def seed_not_found_vid(title)
          text("pito.copy.videos.not_found", ref: title)
        end

        # Zero exact matches for a `for`/bare query — a real, filtered miss (not
        # "the library is empty"), so it reuses the same copy `list games` uses
        # for an empty-after-filtering result. Also reused for vids' `for` miss
        # and vids' `like` no-embedding degrade (search_conversations.rb
        # already establishes this key as the cross-noun "search yielded
        # nothing" copy, not a games-only one — see its own no_matches).
        def no_matches
          text("pito.copy.games.list_filter_empty")
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
