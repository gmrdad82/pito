# frozen_string_literal: true

module Pito
  module Nl
    # NL command composer — the NL mapper's EXPENSIVE path (3.0.0). This is
    # what Pito::Nl::Router (the CHEAP cosine-nearest path) hands off to when
    # no cached nl_examples neighbor is close enough: ask the GBNF-constrained
    # local LLM (llama.cpp `nlmapper` sidecar, see Pito::Nl::CompletionClient)
    # to rewrite the owner's free text as one typeable PITO command, then
    # PROVE the answer is real by round-tripping it through the actual chat
    # parser — never surface LLM output pito itself would reject.
    #
    # Router vs Mapper, restated (see Router's own header comment for the full
    # three-corpora breakdown): Router asks "does this sit near a phrasing we
    # already trained on?" — cheap, one embed call. Mapper asks "can the local
    # LLM COMPOSE a valid command for this?" — slower (a completion, not a
    # lookup), reserved for utterances Router couldn't place at all.
    module Mapper
      module_function

      # Tightened 2026-07-15 (minimal edit, same voice): "Output ONLY the
      # command" widened to "Output ONLY the shortest valid command" after
      # live traffic showed the model padding its answer past the valid
      # command instead of stopping. Paired with MAX_TOKENS / REPEAT_PENALTY
      # below — three angles on the same failure.
      #
      # Trailing ` /no_think` (2026-07-15, hand-verified): Qwen3's OWN
      # documented in-prompt soft switch to suppress its `<think>...</think>`
      # reasoning preamble — belt and suspenders alongside CompletionClient's
      # `chat_template_kwargs: { enable_thinking: false }` request param
      # (see that class's #perform_request doc comment). Root cause was the
      # GBNF grammar strangling the model mid-think; with thinking off via
      # either mechanism the model composed the command on the first try.
      INSTRUCTION = "Rewrite the owner's words as one PITO command. " \
                    "Output ONLY the shortest valid command. /no_think"

      # Short on purpose: this is one command line ("ls rpg games", "link 14
      # 3"), never prose. The GBNF grammar already bounds the SHAPE of the
      # output; this just bounds generation length so a runaway completion
      # can't stall the sidecar's CPU-bound decode loop.
      #
      # 24, not 32 (2026-07-15 live-proof): unbounded sampling was observed
      # padding digit runs — a two-token answer like "link 14 3" kept
      # decoding past the valid command until it hit the token cap instead
      # of stopping. Tightened alongside REPEAT_PENALTY below: cut the
      # runway shorter AND discourage the repetition itself.
      MAX_TOKENS = 24

      # Discourages the decoder from repeating a token/run it already
      # emitted. llama.cpp's own default is 1.0 (off); every OTHER caller of
      # Pito::Nl::CompletionClient#chat keeps that default — this is
      # Mapper-specific.
      #
      # PROVENANCE:
      #   2026-07-15 (static prompt) — bumped 1.0 -> 1.3 after live traffic
      #   showed unbounded (1.0) sampling padding digit runs past the
      #   shortest valid command (e.g. composing the `link <vid> <game>`
      #   command from "link that new vid 14 to elden ring which is game 3":
      #   the decoder kept going past the valid "link 14 3" answer instead of
      #   stopping — an ID trailing into repeats of itself — until it hit
      #   MAX_TOKENS). Tuned against the STATIC few-shot prompt (v1), where
      #   the relevant exemplar sat buried mid-context.
      #
      #   2026-07-16 (v2 retrieval re-tune, 1.3 -> 1.1) — retrieval (see
      #   #chat_messages' design note) concentrates the most-relevant `run`
      #   string right before the generation point, so at 1.3 the decoder
      #   was penalized for RETYPING exactly the command it should retype
      #   and dodged to a wrong tool ("sync vids" present at 0.87 similarity
      #   -> composed "update videos"). Live sweep over this file's own held-
      #   out fixture (spec/fixtures/nl_mapper_calibration.yml, 15 rows):
      #   1.3 -> 6/15, 1.15 -> 9/15, 1.1 -> 9/15, 1.0 -> 8/15 (fixture header
      #   carries the full data + static-prompt controls). Chose 1.1 over the
      #   tied 1.15 as the smaller step off the un-penalized 1.0 default.
      #   DIGIT-PADDING RE-VERIFIED CLEAN at 1.1 BEFORE adopting it (2026-07-
      #   16): 5 fresh multi-digit-id probes on the exact `link <vid> <game>`
      #   composition this constant exists to guard — "link vid 105 to game
      #   12", "hook vid 40 up with game 128", "connect video 233 with game
      #   47", "show game 105", "put vid 76 together with game 214" — each
      #   run twice live through Pito::Nl::Mapper.map; all 5 composed the
      #   exact expected command, byte-identical across both rounds, no
      #   runaway repetition. See CompletionClient#chat's doc comment for the
      #   repeat_penalty passthrough.
      #
      #   2026-07-20 (Q56-A re-sweep, 1.1 holds) — re-measured after the
      #   mapper-hardening pass grew nl.exemplars to 44 pairs and the Q27c
      #   write-guard landed (WRITE_ACTION_LEXICON below). Live sweep over
      #   the fixture's 10 `entries:` rows, TWO rounds per value, scores
      #   identical across both rounds at every value:
      #     1.0 -> 9/10, 1.1 -> 10/10, 1.15 -> 10/10, 1.3 -> 8/10.
      #   (1.0's one miss: the breakdowns row composed "show game 8 full";
      #   1.3's two: the sync row degraded to nil and the similar-in-style
      #   row dodged to a `search …` composition — the exact search-like
      #   drift Q51 pins against.) 1.1 and 1.15 tie at the ceiling; kept 1.1
      #   as the smaller step off the un-penalized 1.0 default, same
      #   tiebreak as the v2 retune above.
      REPEAT_PENALTY = 1.1

      # Few-shot retrieval width (v2, 2026-07-16 — see #chat_messages for the
      # design history): how many exemplar pairs the prompt carries, cosine-
      # picked per utterance from the full `nl.exemplars` pool. 8 balances the
      # two live-measured failure modes: SMALL enough that growing the pool can
      # never crowd an unrelated tool's worked example out of the model's
      # attention (the brittleness that killed static-all), LARGE enough to
      # keep pattern diversity — multi-slot composition, number words, filler-
      # heavy phrasing — in view for a 0.6B model. 8 pairs also keep the turn
      # array comfortably inside the qwen sidecar's --ctx-size 2048
      # (docker-compose*.yml `nlmapper` command) alongside the grammar and the
      # completion budget, with room for the pool to keep growing for free.
      FEW_SHOT_TOP_K = 8

      # ── Write-tool guard (Q27c, 2026-07-20/21 owner interview) ───────────
      # The mapper must NEVER hand back a WRITE-tool command unless the
      # owner's own words name that tool's action — live traffic showed the
      # composer confabulating writes for read-shaped asks ("crack open vid
      # 30" is an analyze ask; a link/delete composition for it is a
      # hallucination, not a mapping). The keys of this Hash ARE the write
      # set; a composed tool found here must match its action lexicon
      # against the NORMALIZED utterance (post nl.synonyms fold — "remove"/
      # "erase" already read "delete" by then, but the raw forms stay listed
      # so the guard never depends on #normalize's exact steps) or #map
      # returns nil and the ask falls through to the router's did-you-mean /
      # unknown copy. Tools absent here (every read tool) are unguarded.
      #
      # Lexicon derivation rule: the interview's verb families + their
      # nl.synonyms + the action verbs already attested in each tool's own
      # nl_examples corpus AND its nl.exemplars say-phrases (tools.yml — the
      # two places that define owner-voice action wording), with
      # hand-authored inflections. The exemplar half is a coherence
      # invariant — the few-shot pool must never teach a composition this
      # guard then refuses (mapper_spec pins it pool-wide). Update's
      # add/put/pick-up/pay/cost/come-out/runs-on families were re-derived
      # 2026-07-20 after a verify pass caught them attested-but-omitted:
      # "add ps5 to game 12" (an nl_examples row) composed :update, the
      # guard nil'd it, and the ask degraded to the huh copy.
      #
      # Deliberately NOT included — the boundary is an OWNER-ACTION VERB,
      # so a phrasing survives on one ("game 6 also plays on ps5", "picked
      # up game 5 for 12 bucks") and never on a copula or price-drift
      # alone:
      #   * link's no-verb relink family ("vid 3 is actually hollow
      #     knight" — Q47);
      #   * update's copula facts ("tekken 8 is 49.99 now", "game 42 is
      #     also on switch") and price-drift statements ("game 6 dropped
      #     to 9.99", "game 3 goes for 15 euros") — the only verb is the
      #     price/platform's own movement, and "dropped" is delete/
      #     schedule's verb: accepting it here would bless
      #     mis-compositions of destructive-intent phrasing as updates.
      # Verb-less writes are exactly what Q27c rules the mapper may never
      # compose on its own. Cost of the exclusion: those rows stay attested
      # in nl_examples (they still teach the router's cosine neighbors),
      # but their asks end at the huh copy — Handlers::Unknown#gated_result
      # needs a surviving composition even for the did-you-mean.
      #
      # EXCEPTION (interview-ruled): update-footage auto-run phrasings count
      # as action-named — logged/recorded/played/add-hours wordings sit in
      # update's lexicon (the Q17 field that may auto-run needs its owner-
      # voice deltas to survive the guard).
      WRITE_ACTION_LEXICON = {
        delete: /\b(?:delet(?:e[sd]?|ing)|remov(?:e[sd]?|ing)|eras(?:e[sd]?|ing)|kill(?:s|ed|ing)?|trash(?:es|ed|ing)?|drop(?:s|ped|ping)?|wip(?:e[sd]?|ing)|scrap(?:s|ped|ping)?|bin(?:s|ned|ning)?|get(?:s|ting)? rid of|thr(?:ow(?:s|ing)?|ew) (?:\S+ ){0,3}?away)\b/,
        link: /\b(?:link(?:s|ed|ing)?|attach(?:es|ed|ing)?|hook(?:s|ed|ing)?|connect(?:s|ed|ing)?|tie(?:s)?|tying|pair(?:s|ing)?|belong(?:s|ed|ing)?|go(?:es|ing)? (?:with|together))\b/,
        unlink: /\b(?:unlink(?:s|ed|ing)?|unhook(?:s|ed|ing)?|detach(?:es|ed|ing)?|divorc(?:e[sd]?|ing))\b/,
        publish: /\b(?:publish(?:es|ed|ing)?|ship(?:s|ped|ping)?|releas(?:e[sd]?|ing)|go(?:es|ing)? live|went live|(?:put(?:s|ting)?|push(?:es|ed|ing)?|send(?:s|ing)?|flip(?:s|ped|ping)?|make(?:s)?|making|take(?:s)?|taking|took) (?:\S+ ){0,4}?(?:out|live|public))\b/,
        unlist: /\b(?:unlist(?:s|ed|ing)?|hid(?:es?|den|ing)?|delist(?:s|ed|ing)?|(?:take(?:s)?|taking|took|pull(?:s|ed|ing)?|get(?:s|ting)?) (?:\S+ ){0,4}?off)\b|\boff (?:\S+ ){0,3}?listing\b/,
        schedule: /\b(?:schedul(?:e[sd]?|ing)|queu(?:e[sd]?|ing)|queueing|lin(?:e[sd]?|ing) up|line-?up|slot(?:s|ted|ting)?|pencil(?:s|led|ling)?|premier(?:e[sd]?|ing)|calendar|slate|drop(?:s|ped|ping)?|go(?:es|ing)? (?:out|live)|went (?:out|live)|(?:put(?:s|ting)?|push(?:es|ed|ing)?) (?:\S+ ){0,4}?out)\b/,
        sync: /\b(?:sync(?:s|ed|ing)?|refresh(?:es|ed|ing)?|fetch(?:es|ed|ing)?|pull(?:s|ed|ing)?|grab(?:s|bed|bing)?|fresh(?:est)?|new uploads?|from youtube|check(?:s|ed|ing)? youtube)\b/,
        import: /\b(?:import(?:s|ed|ing)?|add(?:s|ed|ing)?|grab(?:s|bed|bing)?|fetch(?:es|ed|ing)?|bring(?:s|ing)?|brought|pull(?:s|ed|ing)? (?:\S+ ){0,4}?in)\b/,
        reindex: /\b(?:re-?index(?:es|ed|ing)?|re-?embed(?:s|ded|ding)?|embeddings?|rebuil[dt](?:s|ing)?|redo(?:es|ing)?|redid|regenerat(?:e[sd]?|ing))\b/,
        update: /\b(?:updat(?:e[sd]?|ing)|set(?:s|ting)?|chang(?:e[sd]?|ing)|log(?:s|ged|ging)?|record(?:s|ed|ing)?|play(?:s|ed|ing)|add(?:s|ed|ing)?|put(?:s|ting)?|pick(?:s|ed|ing)? up|pa(?:y(?:s|ing)?|id)|cost(?:s|ing)?|(?:came|come(?:s)?|coming) out|run(?:s|ning)? on|footage|hours?|minutes?|sessions?)\b/
      }.freeze

      # Maps a free-text +utterance+ to { command:, tool: } — a validated,
      # parser-approved PITO command line and the chat tool it canonicalizes
      # to — or nil when the utterance is blank, the sidecar is unreachable,
      # the completion doesn't parse to a known chat tool, or the composed
      # tool is a write the utterance never asked for (WRITE_ACTION_LEXICON
      # above).
      #
      # `tool:` (3.0.0 mismatch re-try) constrains the completion to a
      # SINGLE-TOOL grammar (Pito::Nl::GbnfBuilder's `only:`) — the model
      # can then only compose a command FOR that one tool. The parsed result
      # is additionally validated to resolve to THAT SAME tool; anything
      # else (the model still can't legally produce one, or — shouldn't
      # happen under a single-tool grammar, but K2 never trusts LLM output —
      # parses to some other tool) returns nil rather than a mismatched
      # mapping. See Pito::Chat::Handlers::Unknown's gate for the one caller
      # that passes `tool:`, and its header comment for the live finding
      # ("rm games" for a :list intent) this exists to fix. Default `tool:
      # nil` is unchanged: the full multi-tool grammar, exactly as before.
      #
      # K2 data honesty: every failure mode here degrades to nil, never
      # raises. A down nlmapper sidecar is exactly as valid an outcome as a
      # nonsense completion — both mean "pito has no opinion," and the caller
      # (the unknown-input fallback) already has a friendly reply for that.
      def map(utterance, tool: nil)
        return nil if utterance.blank?

        normalized = normalize(utterance)
        completion = Pito::Nl::CompletionClient.new.chat(
          messages: chat_messages(normalized),
          grammar: grammar(tool: tool),
          max_tokens: MAX_TOKENS,
          repeat_penalty: REPEAT_PENALTY
        )
        # CompletionClient#chat is itself fully forgiving (unconfigured
        # PITO_NLMAPPER_URL, non-2xx, malformed body, timeout — all nil), so
        # this one guard covers "sidecar down" AND "sidecar answered blank."
        return nil if completion.blank?

        command = completion.strip
        parsed_tool_name = parsed_tool(command)
        return nil if parsed_tool_name.nil?
        return nil if tool && parsed_tool_name != tool.to_sym
        return nil unless action_named?(tool: parsed_tool_name, utterance: normalized)

        { command: command, tool: parsed_tool_name }
      end

      # ── Private ──────────────────────────────────────────────────────────

      # Memoized per Pito::Dispatch::Config.data IDENTITY (not merely
      # memoized-once): `.data` is itself memoized and only changes object
      # identity on `.reload!` (dev's to_prepare hook, or a test resetting
      # config), so keying the cache on that object's identity means a
      # tools.yml edit rebuilds the grammar on the very next call, exactly
      # like GbnfBuilder's own "add a chat tool, it just appears" contract —
      # with no cache invalidation this module has to remember to do by hand.
      #
      # Per-tool memo (3.0.0 mismatch re-try): `grammar(tool: :list)` builds
      # (and caches) the single-tool grammar for that one tool — see #map's
      # `tool:` param — in its OWN slot of `@tool_grammars`, keyed by tool
      # Symbol, so a re-try against the same tool never rebuilds it. That
      # hash rides the SAME Config.data identity check as the full grammar:
      # a tools.yml edit (or `Config.reload!`) invalidates both together
      # rather than needing a second invalidation mechanism to remember.
      def grammar(tool: nil)
        data = Pito::Dispatch::Config.data
        unless @grammar_data.equal?(data)
          @grammar = nil
          @tool_grammars = {}
          @grammar_data = data
        end

        if tool
          (@tool_grammars ||= {})[tool.to_sym] ||= Pito::Nl::GbnfBuilder.call(only: tool)
        else
          @grammar ||= Pito::Nl::GbnfBuilder.call
        end
      end

      # Few-shot MESSAGE ARRAY: one system turn (the terse instruction), then
      # the retrieval-picked exemplars from the ontology's top-level
      # `nl.exemplars:` (config/pito/tools.yml — see #few_shot_exemplars) as
      # alternating user("<say>") / assistant("<run>") PAIRS, ending on the
      # owner's own (normalized) utterance as the final, still-open user turn
      # for the grammar to complete as the assistant's reply — the canonical
      # instruct few-shot form.
      #
      # Multi-turn, not exemplars-in-the-system-block (2026-07-15,
      # live-proof; see CompletionClient's doc comment for the fuller
      # rationale): a 0.6B model imitates alternating chat turns far better
      # than prose worked-examples buried in one system string — the old
      # "owner: ...\ncommand: ..." lines-in-a-system-block shape left
      # `greet` sitting as a constrained-decoding attractor no matter the
      # utterance. Real user/assistant turns give the model the SAME shape
      # it was instruct-tuned on, so it actually generalizes past the
      # exemplars instead of pattern-matching the nearest one.
      #
      # DESIGN DECISION (v2, retrieval-picked — owner decision 2026-07-16;
      # read before "improving" this):
      #   v1 shipped static-ALL (every exemplar, every call) and deferred
      #   retrieval "until the exemplar bank grows past what fits in context".
      #   The real constraint arrived earlier and wasn't context size: a live
      #   experiment (4 controlled runs, fully deterministic) proved that
      #   ADDING any exemplar reshuffles the model's compositions for
      #   UNRELATED tools — with a 0.6B model, every pair in the prompt
      #   competes for attention, so the pool could never grow safely.
      #   v2 embeds the pool's `say` strings once (in-memory, keyed on
      #   Config.data identity — see #exemplar_vectors), cosine-ranks them
      #   against the already-normalized utterance at map time, and prompts
      #   with only the FEW_SHOT_TOP_K nearest: an addition now changes a
      #   prompt only when it is genuinely nearer the utterance than an
      #   incumbent, never by mere presence.
      #   The selected pairs keep their ORIGINAL tools.yml order, NOT
      #   similarity order — the pool's authored sequence is the one stable
      #   axis (same utterance -> same turn array byte-for-byte; a pair's
      #   position relative to the utterance turn never depends on a
      #   similarity tie), so determinism and recency-position effects stay
      #   pinned as the pool grows.
      #   Degradation: any embedding failure (unconfigured/unreachable
      #   embedder, a nil vector slot) falls back to the full static v1
      #   prompt with one warn — retrieval failing can never make the mapper
      #   WORSE than the design it replaced. The GBNF grammar and the rest of
      #   the completion call are untouched by all of this.
      def chat_messages(utterance)
        messages = [ { role: "system", content: INSTRUCTION } ]
        few_shot_exemplars(utterance).each do |exemplar|
          messages << { role: "user", content: exemplar[:say] }
          messages << { role: "assistant", content: exemplar[:run] }
        end
        messages << { role: "user", content: utterance }
        messages
      end

      # Retrieval-picks the FEW_SHOT_TOP_K pool exemplars nearest to
      # +utterance+ (already normalized by #map), restored to their original
      # tools.yml order (see #chat_messages' design note). A pool already
      # within the K budget short-circuits to itself — nothing could be
      # crowded out, so there is nothing to rank (and no embed to pay for).
      # The index tiebreak on equal similarity keeps selection deterministic;
      # `.sort` before the lookup is the original-order restoration.
      def few_shot_exemplars(utterance)
        pool = Pito::Dispatch::Config.nl_exemplars
        return pool if pool.size <= FEW_SHOT_TOP_K

        vectors = exemplar_vectors(pool)
        return static_fallback(pool) if vectors.nil?

        utterance_vector = Pito::Embedding::Client.new.embed([ utterance ]).first
        return static_fallback(pool) if utterance_vector.nil?

        pool.each_index
            .sort_by { |i| [ -cosine(utterance_vector, vectors[i]), i ] }
            .first(FEW_SHOT_TOP_K)
            .sort
            .map { |i| pool[i] }
      end

      # In-memory vector cache for the pool's `say` strings — ONE forgiving
      # batched embed per tools.yml identity, never a DB table, never a
      # per-call re-embed of the pool. Keyed on Pito::Dispatch::Config.data
      # object identity EXACTLY like #grammar above: a tools.yml edit (or a
      # test's Config.reload!) invalidates the vectors on the very next call
      # with no bespoke invalidation for this module to remember. A failed
      # embed (ANY nil slot — partial vectors would silently mis-rank) is NOT
      # cached: the next map call retries, so a transient sidecar outage
      # degrades those calls to the static fallback instead of poisoning the
      # cache until the next reload. The client applies the EmbeddingGemma
      # task prompt at the wire level itself (Client::PROMPT_PREFIX) — the
      # raw `say` text is exactly what belongs here.
      def exemplar_vectors(pool)
        data = Pito::Dispatch::Config.data
        unless @exemplar_data.equal?(data)
          @exemplar_vectors = nil
          @exemplar_data = data
        end
        return @exemplar_vectors if @exemplar_vectors

        vectors = Pito::Embedding::Client.new.embed(pool.map { |exemplar| exemplar[:say] })
        return nil if vectors.any?(&:nil?)

        @exemplar_vectors = vectors
      end

      # The write-tool guard's predicate (Q27c — see WRITE_ACTION_LEXICON's
      # own comment for the policy and the lexicon derivation rule). Applied
      # to EVERY composition, the `tool:`-constrained mismatch re-try
      # included: a blanket "never compose an unasked write", not a path-
      # specific patch. +utterance+ is the already-normalized form #map
      # built the prompt from — guard and prompt always judge the same text.
      def action_named?(tool:, utterance:)
        lexicon = WRITE_ACTION_LEXICON[tool]
        lexicon.nil? || utterance.match?(lexicon)
      end

      # Cosine similarity over plain Float arrays, hand-rolled on purpose:
      # the pool is ~44 vectors of 768 dims — a linear scan is microseconds,
      # and these vectors never touch the DB, so pgvector/`neighbor` would be
      # infrastructure for nothing. Zero-norm input scores 0.0 rather than
      # dividing by zero.
      def cosine(left, right)
        dot = 0.0
        norm_left = 0.0
        norm_right = 0.0
        left.each_index do |i|
          dot += left[i] * right[i]
          norm_left += left[i] * left[i]
          norm_right += right[i] * right[i]
        end
        denominator = Math.sqrt(norm_left * norm_right)
        denominator.zero? ? 0.0 : dot / denominator
      end

      # The v1 static-ALL prompt, kept as the degradation path (see
      # #chat_messages' design note). One warn per fallen-back map call —
      # operator visibility in the docker logs without paging on designed
      # degradation, mirroring Pito::Embedding::Client's own forgiving-path
      # stance (this fires on the mapper's rare, expensive path only).
      def static_fallback(pool)
        Rails.logger.warn(
          "[Pito::Nl::Mapper] exemplar retrieval unavailable (embedder unconfigured, down, " \
          "or returned a nil vector) — falling back to the full static few-shot pool"
        )
        pool
      end

      # Lexical snapping BEFORE the prompt is built — MIRRORS Pito::Nl::
      # Router#normalize exactly (downcase, whitespace-squeeze, then fold
      # tools.yml's `nl.synonyms:` word-for-word onto the corpus's own
      # vocabulary). Deliberately duplicated rather than extracted: the two
      # normalizations serve different consumers (an embedding vs a few-shot
      # prompt) that happen to want the identical steps today — coupling
      # them through a shared method would make an intentional future
      # divergence (say, the mapper wanting to keep punctuation the grammar
      # cares about) look like a bug instead of a choice. If Router#normalize
      # ever changes its steps, mirror the change here too.
      def normalize(utterance)
        synonyms = Pito::Dispatch::Config.nl_synonyms
        utterance.to_s.downcase.gsub(/\s+/, " ").strip.split(" ")
                 .map { |word| synonyms[word.to_sym] || word }
                 .join(" ")
      end

      # The validity check: does +command+ parse to a KNOWN chat tool through
      # the REAL chat parser — the same Pito::Lex::Lexer -> Pito::Lex::
      # KeywordSanitizer -> Pito::Chat::Parser pipeline Pito::Dispatch::
      # Router itself runs on typed input (see that class's #parse)? Anything
      # else (a parse-error slash lookalike, a phrase that falls through to
      # :unknown, blank output) is untrusted LLM text and must not reach the
      # owner as a command. `conversation: nil` is safe here — Parser stores
      # it but the parse path never reads it (reserved for future use per its
      # own doc comment).
      def parsed_tool(command)
        tokens = Pito::Lex::KeywordSanitizer.call(Pito::Lex::Lexer.call(command))
        message = Pito::Chat::Parser.call(tokens, raw: command, conversation: nil)
        return nil unless message.kind == :new_turn

        message.tool
      rescue Pito::Chat::Parser::NotAChatMessage
        nil
      end
    end
  end
end
