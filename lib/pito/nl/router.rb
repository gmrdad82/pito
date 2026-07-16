# frozen_string_literal: true

module Pito
  module Nl
    # Embedding router — the NL mapper's CHEAP path (3.0.0). Before a chat
    # turn ever reaches the slower GBNF-constrained local LLM (see
    # Pito::Nl::GbnfBuilder's grammar + the completion client), this class
    # tries to answer the question purely by cosine-nearest lookup: does the
    # owner's utterance sit close to one of the phrasings already authored
    # under a tool's `nl_examples:` in config/pito/tools.yml? If so, with
    # enough confidence, the mapper never has to run the LLM at all.
    #
    # THREE CORPORA, THREE JOBS (tools.yml's own comment says this too — worth
    # repeating here, since it is easy to blur):
    #   * per-tool `nl_examples:`          — THIS class's training neighbors,
    #                                        read via
    #                                        Pito::Dispatch::Config.nl_examples.
    #   * top-level `nl.exemplars`         — the GBNF mapper's few-shot
    #                                        say → run pairs.
    #   * spec/fixtures/nl_calibration.yml — the held-out test set that
    #                                        MEASURES (never trains) this
    #                                        router's thresholds.
    # Never let one corpus's phrasings leak into another's job.
    #
    # The `nl_examples` table is a MATERIALIZED, EMBEDDED cache of the first
    # corpus — see db/migrate/20260715190000_create_nl_examples.rb for the
    # schema rationale (digest-gated re-embed, nullable embedding, partial
    # HNSW index). `.sync!` keeps the cache honest against tools.yml edits;
    # `.route` is the read path an actual chat turn calls.
    module Router
      module_function

      # ── Cache row ────────────────────────────────────────────────────────
      #
      # No standalone AR model exists for this table elsewhere in app/models
      # — the cache is an implementation detail of the router, not a domain
      # concept another class should reach into, so it is nested here rather
      # than promoted to app/models/nl_example.rb. `table_name` is explicit
      # because Rails' default inference for a namespaced class would look
      # for "examples", not "nl_examples".
      class Example < ApplicationRecord
        self.table_name = "nl_examples"
      end

      # ── Public API ───────────────────────────────────────────────────────

      # Materializes the cache from config/pito/tools.yml's per-tool
      # `nl_examples:` corpora. Idempotent and safe to call at boot AND
      # lazily (see `.route`'s self-heal below): rows are upserted keyed by
      # `digest` (SHA256 of the phrase text) so an unchanged phrase never
      # re-embeds, a NEW phrase gets a fresh (nil-embedding) row, and a
      # phrase REMOVED from tools.yml is pruned. Only rows still missing an
      # embedding after the upsert/prune ever reach the embedder — a sync
      # where nothing changed touches no HTTP endpoint at all.
      def sync!
        entries = corpus
        return if entries.empty? # Config.data raises LoadError at boot on a
        # malformed file, so an empty ontology should never reach here in
        # practice — treat it as "nothing to do" rather than pruning the
        # whole cache on what is more likely a transient load problem than
        # real intent.

        upsert!(entries)
        prune!(entries)
        embed_pending!
      end

      # Routes a free-text +utterance+ to the nearest chat tool, or nil when
      # nothing in the cache is close enough to be worth surfacing.
      #
      # Returns { tool:, confidence:, nearest_phrase: } or nil. `confidence`
      # is `1 - cosine_distance` of the single nearest neighbor (1.0 ==
      # identical embedding). This method only REPORTS that number against
      # the `suggest` floor — the CALLER compares it against
      # `nl_thresholds[:auto_run]` to decide whether to dispatch silently or
      # confirm first. Keeping that decision out of this class means the
      # gate's policy can change (or be A/B'd) without touching the router,
      # and the calibration spec (spec/fixtures/nl_calibration.yml) can
      # assert on the reported number directly.
      def route(utterance)
        return nil if utterance.blank?

        vector = Pito::Embedding::Client.new.embed([ normalize(utterance) ]).first
        # Client#embed's forgiving contract already collapses "sidecar down"
        # and "PITO_EMBEDDER_URL unset" to the same nil slot — one guard
        # covers both an unconfigured embedder and a live failure.
        return nil if vector.nil?

        # Self-heal: an empty embedded cache means either this is the very
        # first call before boot-time sync ran, or the embedder just came
        # back after being down during the last sync (K2 — degrade, don't
        # refuse). Boot-time sync is the normal path; this lazy retry is the
        # fallback, attempted once per call rather than looped.
        sync! unless embedded.exists?

        best = nearest(vector, limit: 5).first
        return nil if best.nil?

        confidence = 1.0 - best.neighbor_distance.to_f
        threshold  = Pito::Dispatch::Config.nl_thresholds[:suggest]
        # A missing threshold means the ontology declares no `nl:` block at
        # all — treat that as NL routing being switched off, not as an
        # unbounded 0.0 floor that would match almost anything.
        return nil if threshold.nil? || confidence < threshold

        { tool: best.tool.to_sym, confidence: confidence, nearest_phrase: best.phrase }
      end

      # ── Private ──────────────────────────────────────────────────────────

      # The full { tool:, phrase:, digest: } corpus the ontology currently
      # declares — one entry per (tool, phrase) pair, computed fresh from
      # Pito::Dispatch::Config on every call (cheap: no I/O, just a walk over
      # the already-memoized, deep-frozen YAML).
      # Chitchat tools stay OUT of the router's neighbor set: their literal
      # trigger words ("hi", "bye") already parse through the grammar, so
      # their nl_examples never reach the unknown-input fallback this router
      # serves — but as cache rows their ultra-short phrases sit at a high
      # cosine baseline against ANY short text, magnetizing false positives
      # (measured 2026-07-15: "asdfghjkl" hit greet at 0.785). Their
      # nl_examples stay in tools.yml for the MCP/help consumers.
      ROUTER_EXCLUDED_TOOLS = %w[greet farewell].freeze

      def corpus
        Pito::Dispatch::Config.data.fetch(:tools).flat_map do |name, tool|
          next [] if ROUTER_EXCLUDED_TOOLS.include?(name.to_s)

          # Same "declares a chat: block" membership test Pito::Nl::
          # GbnfBuilder uses — nl_examples exists to route free-text CHAT
          # input, so a slash-only tool's examples (if it ever authored any)
          # have no business in a cache the chat router queries.
          next [] unless tool.key?(:chat)

          Pito::Dispatch::Config.nl_examples(tool: name).map do |phrase|
            { tool: name.to_s, phrase: phrase, digest: Digest::SHA256.hexdigest(phrase) }
          end
        end.uniq { |entry| entry[:digest] }
        # Defensive: two tools authoring the identical phrase text would
        # collide on the digest unique index. tools.yml curation keeps
        # per-tool corpora distinct today (verified: zero collisions across
        # the live corpus) — this only guards a future authoring slip; the
        # first tool declared in the YAML wins.
      end

      # Upserts every current entry keyed by `digest` — an unchanged phrase's
      # row is untouched (its `embedding` column is never in this attribute
      # list, so a re-run can never null out a cached vector); a phrase whose
      # owning tool moved gets its `tool` column corrected in place.
      def upsert!(entries)
        now = Time.current
        rows = entries.map { |entry| entry.merge(created_at: now, updated_at: now) }
        Example.upsert_all(rows, unique_by: :digest)
      end

      # Drops rows whose digest no longer appears in the ontology — a phrase
      # deleted from tools.yml's nl_examples: leaves no orphaned cache row
      # (and no orphaned HNSW-indexed vector) behind.
      def prune!(entries)
        wanted = entries.map { |entry| entry[:digest] }
        Example.where.not(digest: wanted).delete_all
      end

      # Embeds every row still missing a vector — new rows from `upsert!`
      # above, plus any row a previous sync left nil because the sidecar was
      # down at the time (K2: never raise, retry next sweep). ONE batched
      # forgiving `embed` call covers the whole pending set — "cheap" here
      # specifically means no per-row HTTP round trip, only one.
      def embed_pending!
        pending = Example.where(embedding: nil).to_a
        return if pending.empty? # the cheap path: nothing changed since the
        # last successful embed, so no HTTP call happens at all.

        vectors = Pito::Embedding::Client.new.embed(pending.map(&:phrase))
        pending.zip(vectors).each do |row, vector|
          next if vector.nil? # stays nil; retried on the next sync! sweep.

          row.update_column(:embedding, vector)
        end
      end

      # Lexical snapping BEFORE embedding — tools.yml's `nl.synonyms:` folds a
      # chatting owner's word choice ("clips" / "films") onto the tool
      # corpus's own vocabulary ("vids") so the embedding lands nearer the
      # trained neighbors. Downcase + whitespace-squeeze first so token
      # lookups are case/spacing-insensitive; punctuation is left alone on
      # purpose — the corpus phrases themselves keep their own punctuation
      # ("what's in my library?"), so stripping it here would only pull the
      # utterance's embedding AWAY from its nearest trained neighbor.
      def normalize(utterance)
        synonyms = Pito::Dispatch::Config.nl_synonyms
        utterance.to_s.downcase.gsub(/\s+/, " ").strip.split(" ")
                 .map { |word| synonyms[word.to_sym] || word }
                 .join(" ")
      end

      # Rows carrying an embedding — the only ones a cosine query, or the
      # self-heal emptiness check in `.route`, ever cares about.
      def embedded
        Example.where.not(embedding: nil)
      end

      # Hand-rolled cosine-nearest query — mirrors Pito::Chat::Handlers::
      # SearchConversations#cosine_candidates exactly (see that file's
      # comment for why this is hand-rolled rather than `has_neighbors`'
      # `nearest_neighbors` scope): `Example.type_for_attribute(:embedding)`
      # already casts/serializes correctly because the `neighbor` gem
      # registers the "vector" Postgres OID globally, regardless of
      # `has_neighbors` — only the `<=>` cosine-distance ORDER BY needs
      # writing out by hand.
      def nearest(vector, limit:)
        attribute = Example.type_for_attribute(:embedding)
        literal   = Example.connection.quote(attribute.serialize(attribute.cast(vector)))
        distance  = "nl_examples.embedding <=> #{literal}"

        embedded
          .select("nl_examples.*, (#{distance}) AS neighbor_distance")
          .order(Arel.sql("#{distance} ASC"))
          .limit(limit)
      end
    end
  end
end
