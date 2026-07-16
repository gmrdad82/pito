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
      # Mapper-specific. Bumped to 1.3 2026-07-15 after live traffic showed
      # unbounded (1.0) sampling padding digit runs past the shortest valid
      # command (e.g. an ID trailing into repeats of itself). See
      # CompletionClient#chat's doc comment for the passthrough.
      REPEAT_PENALTY = 1.3

      # Maps a free-text +utterance+ to { command:, tool: } — a validated,
      # parser-approved PITO command line and the chat tool it canonicalizes
      # to — or nil when the utterance is blank, the sidecar is unreachable,
      # or the completion doesn't parse to a known chat tool.
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

        completion = Pito::Nl::CompletionClient.new.chat(
          messages: chat_messages(normalize(utterance)),
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
      # EVERY exemplar from the ontology's top-level `nl.exemplars:`
      # (config/pito/tools.yml) as an alternating user("<say>") /
      # assistant("<run>") PAIR, ending on the owner's own (normalized)
      # utterance as the final, still-open user turn for the grammar to
      # complete as the assistant's reply — the canonical instruct few-shot
      # form.
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
      # DESIGN DECISION (v1, static — read before "improving" this):
      #   (a) static, ALL exemplars, zero extra embeds — what this ships.
      #       The 23 authored exemplars are short worked examples (~20-30
      #       tokens each); the whole turn array runs ~700 tokens,
      #       comfortably inside Qwen3-0.6B's --ctx-size 4096
      #       (docker-compose*.yml) alongside the grammar and the completion
      #       budget. Fully deterministic: the same utterance always sees
      #       the same messages.
      #   (b) retrieval-picked top-K (the plan's original "retrieval-picked"
      #       ambition) needs the exemplar `say` strings embedded and cached
      #       somewhere — nl_exemplars lives in YAML, not a table, so that is
      #       new infrastructure (a cache row shape + sync job, mirroring
      #       Pito::Nl::Router::Example), not a one-line change. Deferred
      #       until the exemplar bank grows past what fits comfortably in
      #       context — a real constraint, not a guess.
      def chat_messages(utterance)
        messages = [ { role: "system", content: INSTRUCTION } ]
        Pito::Dispatch::Config.nl_exemplars.each do |exemplar|
          messages << { role: "user", content: exemplar[:say] }
          messages << { role: "assistant", content: exemplar[:run] }
        end
        messages << { role: "user", content: utterance }
        messages
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
