# frozen_string_literal: true

module Pito
  module Nl
    # Compiles pito's tool ontology (config/pito/tools.yml, loaded via
    # Pito::Dispatch::Config) into a llama.cpp GBNF grammar string: a `root`
    # rule that constrains a local LLM to typeable PITO chat commands instead
    # of open natural language.
    #
    # ADD-A-TOOL CONTRACT: this builder reads ONLY Pito::Dispatch::Config
    # (`.data`, `.tool`) — it never re-parses YAML and never hardcodes a tool
    # name, slot, or vocabulary. A new chat tool declared in tools.yml (a
    # `chat:` block on a `tools.<name>` entry) appears in the grammar on the
    # very next call with zero changes here; the schema-integrity suite is
    # what keeps tools.yml itself honest.
    #
    # GBNF dialect notes (llama.cpp grammar-parser), since this is the only
    # place in the codebase that emits GBNF:
    #   * the entry point MUST be a rule named `root`.
    #   * whitespace is NOT implicit — every inter-token space is an explicit
    #     `sp` terminal (`sp ::= " "`); nothing else tells the grammar a
    #     space belongs between two tokens.
    #   * a free-text slot is bounded to printable ASCII, length-capped via
    #     GBNF `{m,n}` repetition (`text ::= [ -~]{1,48}`) rather than the
    #     more permissive `[^\n]+` or an unbounded `+` — keeps a constrained
    #     local model emitting typeable command text, not stray control
    #     bytes. The length cap is load-bearing, not cosmetic: live-proofed
    #     2026-07-15 against Qwen3, an unbounded `[ -~]+` let the model pad
    #     commands with digit-run junk (e.g. trailing "11111...") until
    #     max_tokens instead of stopping — bounding the rule gives the
    #     grammar a terminal state, so once no legal continuation remains
    #     llama.cpp forces EOS.
    #
    # Determinism: every collection this builder walks (tool names, alias
    # lists, vocabulary literal sets) is sorted before being joined. A golden
    # spec pins the exact output string, so run-to-run stability matters as
    # much as correctness — never rely on Hash/Set iteration order alone.
    #
    # SINGLE-TOOL GRAMMARS (`only:`, 3.0.0 mismatch re-try): `.call(only:
    # :list)` emits the SAME dialect/shape, but `root ::=` that one tool's
    # rule alone, plus only ITS OWN vocab/sp/text support rules — no other
    # tool exists in the grammar the model sees. Used by Pito::Nl::Mapper's
    # `tool:` constraint, which Pito::Chat::Handlers::Unknown's gate calls
    # when the router and the (unconstrained) mapper disagree on which tool
    # an utterance means (see that handler's header comment for the live
    # "rm games" finding this exists to fix) — with only one legal tool rule
    # left to complete, the model can no longer wander onto a different
    # tool's parse. Default `only: nil` is unchanged: the full multi-tool
    # grammar, exactly as before.
    module GbnfBuilder
      # `@ai` is a free-text passthrough tool BY DESIGN (see its entry in
      # tools.yml: "everything after `@ai` is raw free text handed to the
      # orchestrator loop"). Constraining it with a grammar would defeat its
      # purpose, so it is this builder's own explicit skip — a different
      # class of exclusion from the chitchat skip below (this one is about
      # free-text INTENT, not grammar safety).
      #
      # Auth-gated / slash-only tools (login, logout, connect, config,
      # jobs, …) need no name-list skip at all: they declare no `chat:`
      # block, so the "has a chat: block" membership test below already
      # excludes them — the config's own shape does the filtering, not a
      # hardcoded name list.
      SKIPPED_TOOLS = {
        "@ai": "free-text passthrough — the whole point is NO grammar constraint"
      }.freeze

      # Chitchat tools (greet, farewell) are ALSO excluded from the
      # mapper's grammar — reusing Pito::Nl::Router::ROUTER_EXCLUDED_TOOLS
      # rather than a second hardcoded name list. Referencing it directly
      # is safe, not a load-order hazard: both lib/pito/nl/*.rb files are
      # Zeitwerk-autoloaded (config.autoload_lib in config/application.rb)
      # and Router never references this builder back, so the lookup below
      # is a plain lazy constant resolution, no cycle.
      #
      # Live finding (2026-07-15): under constraint pressure, an uncertain
      # small model collapses onto the grammar's CHEAPEST legal terminal —
      # `greet` declares zero slots (see its tools.yml entry), so its rule
      # is nothing but the name alternation: one short token that is
      # immediately terminal. That made `greet` a magnet for unrelated,
      # garbled utterances the model couldn't otherwise place. The mapper
      # must never legitimately output chitchat anyway: a literal greeting
      # or farewell already parses through the grammar UPSTREAM of the
      # mapper (Pito::Chat::Parser's whole-input phrase match — see the
      # `greet`/`farewell` tools.yml entries) and so never reaches the
      # unknown-input fallback this mapper serves. See
      # Router::ROUTER_EXCLUDED_TOOLS's own comment for the router-side
      # half of the same finding (measured false positive: "asdfghjkl" hit
      # `greet` at 0.785 cosine).

      # Bounded free-text rule: printable ASCII, no control/newline bytes,
      # capped at 48 chars (see the GBNF dialect note above for the
      # live-proof rationale — unbounded `+` let a local model degenerate
      # into digit-padding instead of terminating). Used for `kind: free`
      # slots AND for resolver-backed vocabularies (channels/conversations/
      # game_titles/video_titles are runtime data resolved at dispatch
      # time, never a fixed literal set).
      FREE_TEXT_RULE = "text"

      module_function

      # Builds and returns the GBNF grammar as a String. `only:` (a tool name,
      # Symbol or String) narrows `root` to that ONE tool's rule — see the
      # "SINGLE-TOOL GRAMMARS" module comment above. Raises ArgumentError if
      # `only:` names a tool that isn't chat-mappable (not declared with a
      # `chat:` block, or excluded the same way the full grammar excludes
      # `@ai`/chitchat) — a caller bug, not a data problem, so this never
      # silently degrades to the full grammar instead.
      def call(only: nil)
        vocab_bodies = {}
        names = only ? [ validated_tool_name(only) ] : chat_tool_names
        # Compute every tool rule body FIRST (this also populates
        # vocab_bodies as a side effect), then sort once by rule name — root
        # and the rule listing below share that single deterministic order.
        tool_rules = names
          .map { |name| [ rule_name(name), tool_body(name, vocab_bodies) ] }
          .sort_by(&:first)

        lines = []
        lines << "root ::= #{tool_rules.map(&:first).join(' | ')}"
        lines << ""
        lines << 'sp ::= " "'
        lines << "#{FREE_TEXT_RULE} ::= [ -~]{1,48}"
        lines << ""
        tool_rules.each { |rule, body| lines << "#{rule} ::= #{body}" }
        lines << ""
        vocab_bodies.sort.each { |rule, body| lines << "#{rule} ::= (#{body})" }
        "#{lines.join("\n")}\n"
      end

      # ── Private ───────────────────────────────────────────────────────────────

      # Chat-dispatchable tool names (Symbols), minus the explicit skip list
      # and the chitchat exclusion. "Declares a `chat:` block" is the ONE
      # membership test — see SKIPPED_TOOLS above for why that alone is
      # sufficient for every other tool.
      def chat_tool_names
        Pito::Dispatch::Config.data.fetch(:tools)
          .select { |_name, tool| tool.key?(:chat) }
          .reject { |name, _tool| SKIPPED_TOOLS.key?(name) }
          .reject { |name, _tool| Pito::Nl::Router::ROUTER_EXCLUDED_TOOLS.include?(name.to_s) }
          .keys
      end

      # Guards `only:` against the exact same membership test the full
      # grammar's root already enforces implicitly (chat_tool_names) — a
      # single-tool grammar only makes sense for a tool the mapper would
      # ALSO see in the unconstrained grammar.
      def validated_tool_name(name)
        tool_name = name.to_sym
        return tool_name if chat_tool_names.include?(tool_name)

        raise ArgumentError,
              "Pito::Nl::GbnfBuilder: #{tool_name.inspect} is not a chat-mappable tool (only: requires one)"
      end

      def rule_name(tool_name)
        "tool-#{tool_name.to_s.tr('_', '-')}"
      end

      # The tool-name terminal plus its declared aliases as one alternation,
      # followed by its slots in declared order.
      def tool_body(tool_name, vocab_bodies)
        tool   = Pito::Dispatch::Config.tool(tool_name)
        labels = ([ tool_name ] + Array(tool[:aliases])).map(&:to_s).uniq.sort
        name_alt = "(#{labels.map { |l| quote(l) }.join(' | ')})"
        slots = Array(tool.dig(:chat, :slots))
        ([ name_alt ] + slots.map { |slot| slot_body(tool_name, slot, vocab_bodies) }).join(" ")
      end

      def slot_body(tool_name, slot, vocab_bodies)
        # `search`'s free `query` slot slurps an optional "about"/"like"/"for"
        # keyword before the query text — mirrors the handler's own clause
        # parsing (see the comment on the `search` tool in tools.yml). The
        # keyword lives OUTSIDE the bounded free-text rule so it never burns
        # chars of the 48-char query budget — a vibe query ("about chaotic
        # fast paced never lets up") is naturally the longest kind. Every
        # other slot follows the generic rule below.
        return search_query_body if tool_name == :search && slot[:name] == "query"

        value_rule = slot_value_rule(slot, vocab_bodies)
        core = slot[:repeatable] ? "#{value_rule} ( sp #{value_rule} )*" : value_rule
        core = "#{quote(slot[:introducer])} sp #{core}" if slot[:introducer]
        slot[:optional] ? "( sp #{core} )?" : "sp #{core}"
      end

      def search_query_body
        '( sp ( "about" | "like" | "for" ) )? ( sp text )?'
      end

      # `enum` slots resolve their vocabulary; `free` slots fall back to the
      # bounded free-text rule. (Resolver-backed vocabularies referenced by
      # an `enum` slot — e.g. price/delete/reindex's `game_titles` — also
      # resolve to free text; see vocab_rule.)
      def slot_value_rule(slot, vocab_bodies)
        case slot[:kind]
        when "enum" then vocab_rule(slot[:source], vocab_bodies)
        when "free" then FREE_TEXT_RULE
        else raise "Pito::Nl::GbnfBuilder: unsupported chat slot kind #{slot[:kind].inspect}"
        end
      end

      # Emits (memoized in +vocab_bodies+) a named literal-alternation rule
      # for a STATIC vocabulary — members AND synonym keys, since a typed
      # synonym must parse too. A resolver-backed vocabulary (channels,
      # conversations, game_titles, video_titles: `{ resolver: <name> }`,
      # no `members:`) has no fixed set — its values are runtime data — so
      # it becomes the free-text rule instead of literal alternatives.
      def vocab_rule(vocab_name, vocab_bodies)
        vocab = Pito::Dispatch::Config.data.fetch(:vocabularies).fetch(vocab_name.to_sym)
        return FREE_TEXT_RULE unless vocab.key?(:members)

        rule = "vocab-#{vocab_name.to_s.tr('_', '-')}"
        vocab_bodies[rule] ||= vocab_literals(vocab).map { |l| quote(l) }.join(" | ")
        rule
      end

      def vocab_literals(vocab)
        members  = Array(vocab[:members]).map(&:to_s)
        synonyms = (vocab[:synonyms] || {}).keys.map(&:to_s)
        (members + synonyms).uniq.sort
      end

      # GBNF terminal literal: double-quoted, with backslash/quote escaped
      # (defensive — no current vocabulary member needs it).
      def quote(token)
        escaped = token.to_s.gsub(/["\\]/) { |char| "\\#{char}" }
        "\"#{escaped}\""
      end
    end
  end
end
