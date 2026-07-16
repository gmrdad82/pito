# frozen_string_literal: true

module Pito
  module Chat
    module Handlers
      # `search conversations …` — the conversations noun branch of the `search`
      # tool (config/pito/tools.yml declares ONE `search` tool; `games` vs
      # `conversations` is the noun, not a second tool). Reached ONLY through
      # Pito::Chat::Handlers::Search#delegate_conversations, which calls this
      # class's `call(kwargs:, context:)` directly — never through
      # Pito::Dispatch::Router / Pito::Chat::Registry.
      #
      # ## Why this is a PLAIN class, not a Pito::Chat::Handler subclass
      #
      # Pito::Chat::Registry.register_all! auto-discovers EVERY constant under
      # Pito::Chat::Handlers that (a) is a `Pito::Chat::Handler` subclass AND
      # (b) carries a truthy `@tool` ivar (see Registry#handlers), and stuffs it
      # into a plain Hash keyed by `.tool`. `search` already has exactly ONE
      # owner of that key — Pito::Chat::Handlers::Search — both in the registry
      # and in config/pito/tools.yml's `tools.search.chat.dispatch`. A second
      # `Pito::Chat::Handler` subclass declaring `self.tool = :search` would
      # silently clobber (or be clobbered by) Search's registry slot — a Hash
      # overwrite whose winner depends on Pito::Chat::Handlers.constants' load
      # order, an accident nobody should depend on. The Router itself never
      # consults the Registry for dispatch (it resolves `chat.dispatch` off
      # config directly — see Pito::Dispatch::Router#dispatch_class_for), so
      # this class needs no registry slot at all: it opts out entirely by NOT
      # inheriting Pito::Chat::Handler, which is what Registry's `c <
      # Pito::Chat::Handler` filter keys off. It hand-implements the same
      # `call(kwargs:, context:)` unpacking Pito::Chat::Handler#call provides
      # for free, so the delegation seam in Search#delegate_conversations sees
      # an identical contract either way.
      class SearchConversations
        # Bounded candidate pool of matching events fetched BEFORE grouping by
        # conversation — large enough that 20 distinct conversations (the search
        # pager's page_size) are almost always found even when hits cluster
        # inside a handful of chatty conversations, small enough to stay a
        # single fast index-backed query (HNSW for cosine, the embedding partial
        # index, for `like`; a plain ILIKE scan for `for`/bare). The anchor and
        # ranking rules below only ever see events inside this pool — see
        # #cosine_candidates / #ilike_candidates.
        CANDIDATE_POOL = 200

        # Kinds worth surfacing as a "conversation hit" — the same "owner-
        # searchable conversation content" allowlist EventIndexer uses to decide
        # what's worth embedding at all (chrome kinds like `thinking` /
        # `theme_diff` / confirmations carry no searchable prose). Applied to
        # BOTH the semantic and lexical candidate scopes so a `for`/bare ILIKE
        # scan can't surface UI chrome that `like` would never even embed.
        SEARCHABLE_KINDS = Pito::Embedding::EventIndexer::EMBEDDABLE_KINDS

        def self.call(kwargs:, context:)
          new(
            message:        context.message,
            conversation:   context.conversation,
            channel:        context.channel,
            period:         context.period,
            follow_up:      context.follow_up,
            viewport_width: context.viewport_width,
            kwargs:         kwargs
          ).call
        end

        attr_reader :message, :conversation, :channel, :period, :follow_up, :viewport_width, :kwargs

        def initialize(message:, conversation:, channel: nil, period: nil, follow_up: nil, viewport_width: nil, kwargs: {})
          @message        = message
          @conversation   = conversation
          @channel        = channel
          @period         = period
          @follow_up      = follow_up
          @viewport_width = viewport_width
          @kwargs         = kwargs
        end

        # Owner-locked grammar (3.0.0 L3):
        #   search conversations like <x>  → semantic — embed <x>, cosine-nearest
        #                                     over events.embedding.
        #   search conversations for <x>   → lexical — ILIKE over the events'
        #   search conversations <x>         (bare = `for`, same as Search#call)
        def call
          mode, term = extract_query
          return needs_seed if term.blank?

          mode == :like ? search_like(term) : search_lexical(term)
        end

        private

        # ── query parsing (SAME clause regexes as Pito::Chat::Handlers::Search —
        #    referenced, not duplicated, so a grammar change to one path can't
        #    silently drift out of sync with the other) ─────────────────────────

        def extract_query
          raw = message.raw.to_s
          if (m = raw.match(Pito::Chat::Handlers::Search::LIKE_CLAUSE))
            [ :like, m[1].strip ]
          elsif (m = raw.match(Pito::Chat::Handlers::Search::FOR_CLAUSE))
            [ :for, m[1].strip ]
          else
            [ :for, bare_query(raw) ]
          end
        end

        # Strips the tool word and an immediately-following noun token (here
        # always "conversation(s)", since Search#call only delegates here once
        # the noun already resolved to it), leaving the bare query.
        def bare_query(raw)
          raw.strip.sub(/\Asearch\b\s*/i, "").sub(Pito::Chat::Handlers::Search::NOUN_PREFIX, "").strip
        end

        # ── `like` path (semantic) ──────────────────────────────────────────────

        def search_like(term)
          vector = Pito::Embedding::Client.new.embed([ term ]).first
          # K2: degrade, don't refuse. An unconfigured embedder (PITO_EMBEDDER_URL
          # blank) or any embed failure returns a nil vector (Client#embed's
          # forgiving contract) — fall through to the lexical path rather than
          # erroring the turn.
          return search_lexical(term) if vector.nil?

          respond(rank_by_distance(cosine_candidates(vector, limit: CANDIDATE_POOL)))
        end

        # Hand-rolled cosine-nearest query — Event has no `has_neighbors`
        # declaration (unlike Game/Video's `EMBEDDING_COLUMN`), and this task
        # touches no other file to add one, so this replicates the relevant
        # slice of the `neighbor` gem's `nearest_neighbors` scope by hand: the
        # "vector" Postgres OID → Neighbor::Type::Vector mapping is registered
        # globally by the gem's Postgres adapter hook regardless of
        # `has_neighbors`, so `Event.type_for_attribute(:embedding)` already
        # casts/serializes correctly — only the `<=>` cosine-distance ORDER BY
        # (Neighbor::Utils.operator(:postgresql, :vector, "cosine") == "<=>")
        # needs writing out directly.
        def cosine_candidates(vector, limit:)
          attribute = ::Event.type_for_attribute(:embedding)
          literal   = ::Event.connection.quote(attribute.serialize(attribute.cast(vector)))
          distance  = "events.embedding <=> #{literal}"

          candidate_scope
            .where.not(embedding: nil)
            .select("events.*, (#{distance}) AS neighbor_distance")
            .order(Arel.sql("#{distance} ASC"))
            .limit(limit)
        end

        # ── `for`/bare path (lexical) ────────────────────────────────────────────

        def search_lexical(term)
          respond(rank_by_occurrences(ilike_candidates(term, limit: CANDIDATE_POOL)))
        end

        # Events carry no text/tsvector column (confirmed against db/schema.rb —
        # only `payload` jsonb, `embedding` vector, `embedded_digest`), so this is
        # the simplest HONEST lexical match available: a case-insensitive
        # substring scan over the whole jsonb payload cast to text. Crude — it
        # can match inside a structural payload key as readily as inside actual
        # prose, and it can't rank by relevance, only by how often the term
        # recurs (see #rank_by_occurrences) — the `like` path's HNSW cosine
        # search is the quality match; this is the honest fallback for owners
        # without an embedder configured, or for `for`/bare's exact-substring
        # intent.
        def ilike_candidates(term, limit:)
          candidate_scope
            .where("events.payload::text ILIKE :q", q: "%#{::Event.sanitize_sql_like(term)}%")
            .order(created_at: :desc)
            .limit(limit)
        end

        # Both paths scope to the owner's real scrollback only — `source: "app"`
        # — mirroring Pito::Mcp::Readers: the `source: "mcp"` anchor conversation
        # never gains events by construction, but this makes the exclusion
        # explicit rather than relying on that invariant silently holding.
        def candidate_scope
          ::Event.joins(:conversation)
                 .where(conversations: { source: "app" })
                 .where(kind: SEARCHABLE_KINDS)
        end

        # ── grouping + ranking (shared shape, different rank key) ───────────────

        # Groups a candidate pool by conversation, picking each conversation's
        # ANCHOR as its chronologically FIRST matching event in the pool
        # (position ASC) — landing a reply on the start of the relevant stretch
        # reads better than landing mid-thread on whichever single event ranked
        # closest. The ranking key (what decides which conversation appears
        # FIRST in the results, not which event anchors it) is supplied by the
        # caller: distance for `like`, recency for `for`/bare.
        def hit_groups(events)
          events.group_by(&:conversation_id).map do |conversation_id, group|
            { conversation_id: conversation_id, anchor: group.min_by(&:position), group: group }
          end
        end

        # Ranks conversations by their BEST (closest) hit's cosine distance —
        # smaller is closer — ascending, capped at the search pager's page_size.
        #
        # Also stamps `score` here — the group's best (closest) neighbor_distance
        # (the same value #rank_key uses, already computed; no extra query)
        # converted to a 0–100 integer via #distance_to_score. Semantic-only: the
        # `for`/bare path's #rank_by_occurrences never sets this key, so
        # #build_hits sees a plain `nil` for lexical hits rather than a
        # misleading score — mirroring how #rank_by_distance leaves
        # `occurrence_count` unset.
        def rank_by_distance(events)
          hit_groups(events)
            .map { |g|
              best_distance = g[:group].min_by { |e| e.neighbor_distance.to_f }.neighbor_distance.to_f
              g.merge(rank_key: best_distance, score: distance_to_score(best_distance))
            }
            .min_by(page_size) { |g| g[:rank_key] }
        end

        # Same pgvector cosine distance → 0–100 similarity conversion
        # Pito::Recommendation::Signals.embedding uses for the games' similar-
        # games score bars (`((1.0 - distance) * 100).clamp(0.0, 100.0)`,
        # rounded to an Integer here since this handler has no further blending
        # step) — so a conversation hit and a game at the same cosine distance
        # render the same score bar.
        def distance_to_score(distance)
          ((1.0 - distance.to_f) * 100).clamp(0.0, 100.0).round
        end

        # ILIKE gives no relevance score, so lexical ranking surfaces the
        # most-MENTIONED conversation first: the number of MATCHING events
        # grouped into this conversation within the candidate pool
        # (`group.size`, already fetched by #hit_groups; no extra query) is the
        # primary key, descending. Ties (equal occurrence counts — e.g. every
        # conversation that matched exactly once) break on recency of the
        # ANCHOR event (not the most recent matching event in that conversation
        # — the anchor is already the chronologically FIRST hit within the
        # pool, so ties resolve by how recently their earliest-in-pool hit
        # landed), also descending. `rank_key` is `[occurrence_count,
        # anchor.created_at]` — Array#<=> compares element-wise, so #max_by
        # sorts by occurrence count first and recency only as a tiebreak.
        # Capped at page_size.
        #
        # Also stamps `occurrence_count` here — the same group size the rank
        # key's first element uses. Lexical-only: the `like` path's
        # #rank_by_distance never sets this key, so #build_hits sees a plain
        # `nil` for semantic hits rather than a misleading count.
        def rank_by_occurrences(events)
          hit_groups(events)
            .map { |g| g.merge(rank_key: [ g[:group].size, g[:anchor].created_at ], occurrence_count: g[:group].size) }
            .max_by(page_size) { |g| g[:rank_key] }
        end

        def page_size
          Pito::Dispatch::Config.pager(tool: :search)[:page_size]
        end

        # ── payload / reply ──────────────────────────────────────────────────────

        def respond(ranked_groups)
          hits = build_hits(ranked_groups)
          hits.empty? ? no_matches : ok(hits)
        end

        # One row per conversation: title (or the existing Conversation#display_name
        # "Unnamed <id>" fallback — no new copy), a truncated EventText snippet of
        # the anchor event, and the anchor's event id. String-keyed throughout to
        # match the jsonb payload convention every other builder in the codebase
        # uses (e.g. Game::List's "list_cursor").
        #
        # "occurrence_count" rides along on `g[:occurrence_count]` — set by
        # #rank_by_occurrences (lexical `for`/bare path) to the count of
        # matching events grouped into this conversation; left unset (→ nil) by
        # #rank_by_distance (semantic `like` path), which ranks by cosine
        # distance, not mentions.
        #
        # "score" rides along on `g[:score]` — the mirror image: set by
        # #rank_by_distance (semantic `like` path) to the 0–100 similarity
        # #distance_to_score derives from the group's best neighbor_distance;
        # left unset (→ nil) by #rank_by_occurrences (lexical `for`/bare path),
        # which has no cosine distance to score from.
        def build_hits(ranked_groups)
          conversations = ::Conversation.where(id: ranked_groups.map { |g| g[:conversation_id] }).index_by(&:id)

          ranked_groups.filter_map do |g|
            conversation = conversations[g[:conversation_id]]
            next if conversation.nil? # defensive: deleted between query and render

            anchor = g[:anchor]
            {
              "conversation_id"   => conversation.id,
              "conversation_uuid" => conversation.uuid,
              "anchor_event_id"   => anchor.id,
              "title"             => conversation.display_name,
              "snippet"           => Pito::Mcp::EventText.call([ anchor ]).to_s.truncate(80),
              "occurrence_count"  => g[:occurrence_count],
              "score"             => g[:score]
            }
          end
        end

        # Renders the hits through the dedicated card builder
        # (Pito::MessageBuilder::Conversation::Hits) — list-styled, consistent
        # with the game/vid list cards. The builder owns the presentation
        # (heading, per-row cells) and stamps each row's `data` with
        # anchor_event_id + conversation_uuid, the contract the anchor-jump
        # client behavior reads to scroll to the matched message.
        def ok(hits)
          payload = Pito::MessageBuilder::Conversation::Hits.call(hits, conversation: conversation)
          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: payload } ])
        end

        # ── replies (no new copy this task — card + copy keys are separately
        #    queued; both of these reuse EXISTING Pito::Copy keys) ───────────────

        # SAME key Pito::Chat::Handlers::Search uses for a blank query.
        def needs_seed
          text("pito.chat.search.needs_seed")
        end

        # Zero matches after a real query — reuses the exact same fallback
        # Search#no_matches already established for its own `for`/bare zero-match
        # case (the games-flavoured wording is imperfect for a conversations
        # search, but it's the same honest reuse rather than new copy).
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
