# frozen_string_literal: true

module Pito
  module Chat
    module Handlers
      # Handler for the `search` chat tool — relevance search over the library.
      #
      #   search games like <title>  → the GameSimilarity ranking with the
      #                                genre-gate (3.1.1: now ALSO floor-gated,
      #                                see #relevant), a list-style card headed
      #                                by the seed game itself (its title IS
      #                                the closest match), followed only by the
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
      #   search games <text>        → bare = `about` semantics (#owner
      #                                2026-07-18: "either pass like, for or
      #                                about — or write whatever and pass them
      #                                to the vectors"; the catch-all. This
      #                                SUPERSEDES the 2026-07-15 bare-means-
      #                                EXACT ruling — `for` is now the one
      #                                explicitly-literal path).
      #   search games about <text>  → free-text, qualitative search: no seed,
      #                                no title — just a vibe ("about brutal
      #                                but worth every second"). Embeds <text>
      #                                and ranks by cosine similarity via the
      #                                shared Pito::Search::Semantic seam
      #                                (games.summary_embedding), honest about
      #                                a miss (nothing genuinely close returns
      #                                nothing, never a padded page) and about
      #                                the embedder being unreachable (a real
      #                                error, not a soft miss).
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
      #   search vids about <text>   → mirrors games' `about` path, scoped to
      #                                Video (videos.summary_embedding).
      #
      # Both the games AND the vids paths render through their own SAME
      # list card/payload shape (build_payload / build_video_payload) so #id
      # and sort behave identically regardless of which path produced the
      # rows. Paging is symmetric too: both stamp a `list_cursor` and a
      # "more results" footer when the source list exceeds a page — games'
      # cursor is read back by the game_list follow-up handler, vids' by
      # video_search's (Pito::FollowUp::Handlers::VideoSearch, which pages it
      # via the inherited VideoList#list_next_videos) — so a `search vids …`
      # result with more than a page of matches offers the exact same
      # `next`/`more` affordance a `search games …` result does.
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
      # list from page 1", not necessarily a similarity ranking. The vids
      # paths (like/for/about) stamp the identical cursor shape, paged by
      # video_search's follow-up handler (Pito::FollowUp::Handlers::
      # VideoList#list_next_videos, inherited by VideoSearch) — one
      # mechanism, one contract, both nouns.
      class Search < Pito::Chat::Handler
        self.tool = :search
        self.description_key = "pito.chat.search.descriptions.search"

        # "search games like tekken 7" → captures "tekken 7". FOR_CLAUSE and
        # ABOUT_CLAUSE mirror it byte-for-byte — same clause shape, different
        # keyword — so a bare query (no keyword present) can fall through to
        # `about` semantics (the vectors catch-all).
        LIKE_CLAUSE  = /\blike\b\s+(.+?)\s*\z/i
        FOR_CLAUSE   = /\bfor\b\s+(.+?)\s*\z/i
        ABOUT_CLAUSE = /\babout\b\s+(.+?)\s*\z/i

        # The noun, when typed, always immediately follows the tool word per the
        # slot order config declares (noun before the free query) — stripping
        # only that leading pair isolates a bare (keyword-less) query.
        NOUN_PREFIX = /\A(?:games?|conversations?|vids?|videos?)\b\s*/i

        # Blended-score relevance gate — see #relevant. Universal since 3.1.1:
        # every candidate `like` surfaces has to clear it, genre-sharing or not.
        RELEVANCE_FLOOR = 40

        def call
          return delegate_conversations if noun == "conversations"

          mode, term = extract_query
          return needs_seed if term.blank?

          if noun == "vids"
            case mode
            when :about then search_about_vid(term)
            when :like  then search_like_vid(term)
            else             search_for_vid(term)
            end
          else
            case mode
            when :about then search_about(term)
            when :like  then search_like(term)
            else             search_for(term)
            end
          end
        end

        private

        # ── noun routing ─────────────────────────────────────────────────────

        # "games", "conversations", or "vids" (search_nouns' members), defaulting
        # to "games" — today's behavior — when the second token isn't a noun at
        # all (it's an `about`/`like`/`for` keyword, or the start of a bare
        # catch-all query).
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

        # [:about, term] | [:like, term] | [:for, term]. Precedence (3.1.1):
        # POSITIONAL — the keyword the owner typed EARLIEST wins, so an
        # explicit `for the clip about dragons` stays a lexical search for
        # "the clip about dragons" (the trailing "about" is part of the term)
        # and `about something like dark souls` stays a vibe search for
        # "something like dark souls". Fixed-order precedence would hijack
        # both directions, because all three keywords are ordinary English
        # words that appear mid-query constantly. No keyword at all → :about
        # on the whole remainder — the catch-all (#owner 2026-07-18, see the
        # class header): "search games forcing skillful play" needs no
        # connector vocabulary, it just goes to the vectors. Typos ride free
        # (the embedder shrugs at "requireing"; a substring match never
        # would). `for` is the explicit literal path when exactness matters.
        def extract_query
          raw     = message.raw.to_s
          matches = { about: raw.match(ABOUT_CLAUSE), like: raw.match(LIKE_CLAUSE), for: raw.match(FOR_CLAUSE) }
          mode, m = matches.compact.min_by { |_mode, match| match.begin(0) }
          return [ mode, m[1].strip ] if m

          [ :about, bare_query(raw) ]
        end

        # Strips the tool word and an immediately-following noun token, leaving
        # whatever's left as the bare (keyword-less) query. A remainder that IS
        # a lone dangling keyword ("search games about") is an empty query, not
        # a lexical search for the literal word — blanking it routes the caller
        # to #needs_seed's ask-for-more copy instead.
        def bare_query(raw)
          rest = raw.strip.sub(/\Asearch\b\s*/i, "").sub(NOUN_PREFIX, "").strip
          rest.match?(/\A(?:about|like|for)\z/i) ? "" : rest
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
        # game) is not relevance — AND the blended score clears RELEVANCE_FLOOR
        # (3.1.1: genre overlap alone stopped being sufficient once the
        # trait-infused embeddings started carrying most of the real semantic
        # weight — two games can share a genre and still blend down near noise,
        # and that's no longer a real match). A seed with no genres on record
        # falls back to the SAME floor alone, so an unsynced seed still returns
        # its nearest neighbors instead of the whole library.
        def relevant(seed, ranked)
          if seed.genres.any?
            ranked.select { |r| r.breakdown[:g].to_f > 0 && r.score >= RELEVANCE_FLOOR }
          else
            ranked.select { |r| r.score >= RELEVANCE_FLOOR }
          end
        end

        # ── `about` path (free-text semantic search) ─────────────────────────

        # Shared deep-fetch bound for every ranked search path that pages
        # beyond a single page (SQL-bounded so pgvector's HNSW / embedding
        # neighbor lookups stay cheap): games' `about`, and vids' `like` /
        # `about` (see search_like_vid / search_about_vid). Every one of
        # those rankings pages through the SAME list_cursor/ranked_ids
        # mechanism `like` (games) established — parity, not a special case.
        # 50 is deliberately far beyond any single page (20): the relevance
        # floor usually cuts the tail well before the cap matters. Games'
        # `like` path stays unbounded (`limit: nil`, see search_like) — its
        # candidate pool is the whole library scored once, not a per-query
        # neighbor lookup, so there's no cost benefit to capping it; `for`
        # paths (games and vids) are already unbounded lexical matches with
        # no cap of their own.
        SEARCH_MAX_RESULTS = 50

        # No seed, no title — a free-text, qualitative description ranked by
        # meaning via the shared Pito::Search::Semantic seam (the same pgvector
        # cosine search `like`'s neighbor lookups draw from).
        def search_about(term)
          results = Pito::Search::Semantic.call(scope: ::Game, column: ::Game::EMBEDDING_COLUMN, query: term, limit: SEARCH_MAX_RESULTS)
          return about_unavailable if results.nil?
          return about_empty if results.empty?

          rows   = results.map { |r| r[:record] }
          top    = results.first[:similarity]
          scores = results.to_h { |r| [ r[:record].id, about_score(r[:similarity], top: top) ] }

          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: build_payload(rows, scores: scores) } ])
        end

        # An `about` hit's bar is scored RELATIVE TO THE TOP HIT of its own
        # result set (#owner 2026-07-18: "the 1st result should always be 100
        # and the rest scaled to reflect this"): the ceiling passed to
        # DisplayScore is the set's best similarity, so the leader reads 100
        # by construction and everyone else reads how far above the honesty
        # floor they sit relative to it — a close second reads ~93, a distant
        # one ~15, and the bar discriminates in both cases. 100 therefore
        # means "the best you've got for THIS query", not "objectively
        # identical" — an honest claim, because Pito::Search::Semantic's
        # floor already refused to show anything that isn't genuinely close.
        # (Raw ×100 pinned bars into a mushy 55-68 band; floor-to-1.0 pinned
        # them 0-33 with the library's best answer rendered as a sad 16.)
        def about_score(similarity, top:)
          floor = Pito::Search::Semantic::DEFAULT_FLOOR
          return 100 if top <= floor # sole degenerate case: top AT the floor

          Pito::Recommendation::DisplayScore.display_score(
            similarity, floor: floor, ceiling: top
          ).round
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

          # Deep-fetched (SEARCH_MAX_RESULTS, not page_size) BEFORE the floor
          # filter below — capping at a single page here would truncate the
          # ranking before the floor ever got a chance to cut the irrelevant
          # tail, leaving fewer than a page of genuine matches to page through
          # even when deeper neighbors would have cleared it. The floor gate
          # (3.1.1) still FILTERS after: a neighbor under it renders a
          # zero-length bar, i.e. "not actually similar", and padding the page
          # with those contradicts the honest-miss contract the games paths
          # keep.
          similar = seed.nearest_neighbors(::Video::EMBEDDING_COLUMN, distance: "cosine").limit(SEARCH_MAX_RESULTS)
                        .select { |v| 1.0 - v.neighbor_distance.to_f >= Pito::Recommendation::DisplayScore::VID_FLOOR }
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

        # ── vids `about` path (free-text semantic search) ────────────────────

        # Mirrors search_about's shape, scoped to Video — no seed, a free-text
        # description ranked by meaning via the same Pito::Search::Semantic
        # seam. `limit:` is SEARCH_MAX_RESULTS (not page_size), same as
        # games' `about` — the deep ranking pages through build_video_payload's
        # list_cursor mechanism exactly like games' does.
        def search_about_vid(term)
          results = Pito::Search::Semantic.call(scope: ::Video, column: ::Video::EMBEDDING_COLUMN, query: term, limit: SEARCH_MAX_RESULTS)
          return about_unavailable if results.nil?
          return about_empty if results.empty?

          rows   = results.map { |r| r[:record] }
          top    = results.first[:similarity]
          scores = results.to_h { |r| [ r[:record].id, about_score(r[:similarity], top: top) ] }

          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: build_video_payload(rows, scores: scores) } ])
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
              # Owning tool, read by the pager's inline tool lookup in
              # GameList#list_next_games so `next`/`more` pages at search's
              # page size (20), not :list's (50).
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
        #   search_like_vid/search_about_vid; nil for search_for_vid — Video::List only
        #   renders a Score column when this is present, matching build_payload's games
        #   contract.
        #
        # Pages exactly like build_payload's games cursor: when the source list
        # exceeds a page, the full ordered id list is stamped into list_cursor as
        # `ranked_ids` so video_search's follow-up handler (Pito::FollowUp::
        # Handlers::VideoSearch, which inherits VideoList#list_next_videos) pages
        # that id list instead of replaying a fresh, unranked `list videos` query
        # — and a "more results" footer is appended, same as games. reply_target
        # is re-stamped to "video_search" (Video::List defaults to "video_list")
        # so config/pito/tools.yml's narrower video_search action set applies:
        # the pager (`next`/`more`) and per-row/column tools work, but
        # `sort`/`order`/`analyze` stay excluded — re-sorting a ranking would
        # scramble it, and there's no "whole scope" to (re-)analyze on a
        # query-specific result set.
        def build_video_payload(videos, scores: nil)
          page    = page_size
          rows    = videos.first(page)
          payload = Pito::MessageBuilder::Video::List.call(rows, conversation:, columns: [], scores:)
          # scores present == like/about (semantic) mode; nil == for (lexical)
          # mode — same mapping build_payload uses above.
          payload["list_footer"] = Pito::Copy.render(scores ? "pito.copy.search.footer_like" : "pito.copy.search.footer_for")

          if videos.size > page
            payload["list_cursor"] = {
              "ranked_ids"     => videos.map(&:id),
              "offset"         => page,
              "channel"        => nil,
              "sort_token"     => nil,
              "sort_direction" => nil,
              "columns"        => [],
              # Owning tool, read by the pager's inline tool lookup in
              # VideoList#list_next_videos so `next`/`more` pages at search's
              # page size (20), not :list's (50).
              "tool"           => "search"
            }
            more_text = Pito::Copy.render(
              "pito.copy.list_more",
              count: rows.size,
              total: videos.size,
              rest:  videos.size - rows.size,
              tool:  pager[:more_tool]
            )
            payload["list_footer"] = [ payload["list_footer"].presence, more_text ].compact.join(" ")
          end

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

        # Zero exact matches for an explicit `for` query — a real, filtered miss (not
        # "the library is empty"), so it reuses the same copy `list games` uses
        # for an empty-after-filtering result. Also reused for vids' `for` miss
        # and vids' `like` no-embedding degrade (search_conversations.rb
        # already establishes this key as the cross-noun "search yielded
        # nothing" copy, not a games-only one — see its own no_matches).
        def no_matches
          text("pito.copy.games.list_filter_empty")
        end

        # The embedder is genuinely unreachable (Pito::Search::Semantic
        # returned nil, not []) — a real fault, not a soft miss, so this is
        # the one `about` reply that's a Result::Error rather than a friendly
        # Result::Ok. Pre-rendered (mirrors Show#unknown_entity /
        # Delete#unknown, e.g. `message_key: Pito::Copy.render("pito.copy.huh")`)
        # so the finalizer routes it to `text:` while keeping the :error chrome.
        def about_unavailable
          Pito::Chat::Result::Error.new(
            message_key: Pito::Copy.render("pito.copy.search.about_unavailable"), message_args: {}
          )
        end

        # A real query embedded and searched fine, but nothing cleared
        # Pito::Search::Semantic's floor — an honest "nothing feels close"
        # miss, distinct from #no_matches' strict-filters wording (that copy
        # promises literal matches were checked; this one promises meaning
        # was checked).
        def about_empty
          text("pito.copy.search.about_empty")
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
