# frozen_string_literal: true

require "rails_helper"

# Coverage map — see lib/pito/nl/gbnf_builder.rb's header for the add-a-tool
# contract, determinism guarantee, and GBNF dialect notes this spec checks.
RSpec.describe Pito::Nl::GbnfBuilder do
  let(:grammar) { described_class.call }

  # Mirrors GbnfBuilder#chat_tool_names against the REAL config, independently
  # of the builder's own (private) implementation — so this is a regression
  # check, not a tautology. `@ai` is the one documented, explicit skip;
  # greet/farewell are the chitchat exclusion, reusing the same
  # Pito::Nl::Router::ROUTER_EXCLUDED_TOOLS constant the builder itself
  # reuses (see gbnf_builder.rb's own comment for the WHY).
  def config_chat_tool_names
    Pito::Dispatch::Config.data.fetch(:tools)
      .select { |_name, tool| tool.key?(:chat) }
      .reject { |name, _tool| name == :"@ai" }
      .reject { |name, _tool| Pito::Nl::Router::ROUTER_EXCLUDED_TOOLS.include?(name.to_s) }
      .keys
  end

  def rule_line(prefix)
    grammar.lines.find { |line| line.start_with?(prefix) }
  end

  # ── 1. Structure ─────────────────────────────────────────────────────────
  describe "grammar structure" do
    it "starts with root ::= " do
      expect(grammar).to start_with("root ::= ")
    end

    it "declares sp as a single literal space" do
      expect(grammar).to include('sp ::= " "')
    end

    it "bounds free text to printable ASCII, capped at 48 chars" do
      expect(grammar).to include("text ::= [ -~]{1,48}")
    end
  end

  # ── 2. Tool coverage ─────────────────────────────────────────────────────
  describe "tool coverage" do
    it "lists exactly the chat-dispatchable tools (minus @ai) as tool-<name> alternatives in root" do
      root_alternatives = grammar.lines.first.chomp.delete_prefix("root ::= ").split(" | ")
      expected = config_chat_tool_names.map { |name| "tool-#{name.to_s.tr('_', '-')}" }

      expect(root_alternatives.sort).to eq(expected.sort)
    end

    it "excludes @ai from root" do
      expect(grammar.lines.first).not_to include("tool-@ai")
    end

    it "excludes chitchat tools (greet, farewell) from root" do
      expect(grammar.lines.first).not_to include("tool-greet")
      expect(grammar.lines.first).not_to include("tool-farewell")
    end
  end

  # ── 3. Determinism ───────────────────────────────────────────────────────
  describe "determinism" do
    it "returns identical strings across two consecutive calls" do
      expect(described_class.call).to eq(described_class.call)
    end
  end

  # ── 4. Static vocabulary expansion ──────────────────────────────────────
  describe "static vocabulary expansion" do
    it "expands vocab-search-nouns with its members and synonyms" do
      rule = rule_line("vocab-search-nouns ::=")

      expect(rule).to include('"games"')
      expect(rule).to include('"conversations"')
      expect(rule).to include('"game"')
      expect(rule).to include('"conversation"')
    end
  end

  # ── 5. Resolver-backed vocabularies degrade to free text ────────────────
  describe "resolver-backed vocabularies" do
    it "degrades footage's game_titles slot to the text rule, not literal titles" do
      rule = rule_line("tool-footage ::=")

      expect(rule).to match(/\btext\b/)
      expect(grammar).not_to include("vocab-game-titles")
    end
  end

  # ── 6. The search special case ───────────────────────────────────────────
  describe "the search special case" do
    it "allows an optional like/for keyword before free text" do
      rule = rule_line("tool-search ::=").chomp

      expect(rule).to include('( sp ( "like" | "for" ) )? ( sp text )?')
    end
  end

  # ── 6.5. Single-tool grammar (`only:`) ──────────────────────────────────
  # Same mechanism as the full grammar (call/tool_body/vocab_rule are all
  # shared) — this only checks the `only:` narrowing itself. See gbnf_builder.
  # rb's "SINGLE-TOOL GRAMMARS" module comment and Pito::Nl::Mapper's `tool:`
  # param for the mismatch re-try this exists to serve.
  describe "single-tool grammar (only:)" do
    let(:constrained) { described_class.call(only: :list) }

    it "narrows root to exactly that one tool" do
      expect(constrained.lines.first.chomp).to eq("root ::= tool-list")
    end

    it "still emits that tool's own rule and vocab" do
      expect(constrained).to include("tool-list ::=")
      expect(constrained).to match(/vocab-nouns ::= .*"channels"/)
    end

    it "keeps the shared sp/text support rules" do
      expect(constrained).to include('sp ::= " "')
      expect(constrained).to include("text ::= [ -~]{1,48}")
    end

    it "omits every other tool's rule and vocab" do
      expect(constrained).not_to include("tool-delete")
      expect(constrained).not_to include("tool-search")
      expect(constrained).not_to include("vocab-search-nouns")
    end

    it "accepts a String tool name identically to a Symbol" do
      expect(described_class.call(only: "list")).to eq(constrained)
    end

    it "raises for a tool with no chat: block or excluded from the mapper (@ai, greet)" do
      expect { described_class.call(only: :"@ai") }.to raise_error(ArgumentError, /not a chat-mappable tool/)
      expect { described_class.call(only: :greet) }.to raise_error(ArgumentError, /not a chat-mappable tool/)
    end

    it "leaves the default (only: nil) full grammar unchanged" do
      expect(described_class.call).to eq(grammar)
    end
  end

  # ── 7. Add-a-tool property ───────────────────────────────────────────────
  # Injection idiom mirrors spec/dispatch/add_a_tool_proof_spec.rb: overrides
  # Pito::Dispatch::Config's memoized @data via the DispatchConfigInjection
  # test seam (spec/support/dispatch_config_injection.rb), included on
  # examples tagged type: :dispatch. No dispatch class needs to actually
  # exist — the builder only reads tool names/slots off Config.data.
  describe "add-a-tool property", type: :dispatch do
    SYNTHETIC_TOOL_YAML = <<~YAML
      gbnf_proof:
        description: pito.chat.gbnf_proof.descriptions.gbnf_proof
        auth: session
        chat:
          dispatch: Nl::GbnfBuilderProofHandler
          slots:
            - name: note
              kind: free
              optional: true
    YAML

    after { restore_dispatch_config! }

    it "adds tool-gbnf-proof to root once the tool is declared in config" do
      inject_dispatch_config!(verbs: SYNTHETIC_TOOL_YAML)

      expect(described_class.call.lines.first).to include("tool-gbnf-proof")
    end
  end

  # ── 8. Golden pin ─────────────────────────────────────────────────────────
  # A minimal fixture ontology isn't practical here: inject_dispatch_config!
  # MERGES a fragment over the real document (see merge_section! in
  # spec/support/dispatch_config_injection.rb) rather than replacing :tools /
  # :vocabularies, so every real tool would still appear alongside a fixture
  # one. Pinning 3 stable single-rule shapes instead, per the real ontology.
  # These break INTENTIONALLY whenever the grammar shape changes on purpose
  # (a tool added/renamed before "channels" alphabetically, search's slots
  # reordered, or search_nouns' membership edited) — regenerate the pin with:
  #   RAILS_ENV=test bin/rails runner 'puts Pito::Nl::GbnfBuilder.call'
  describe "golden pin (breaks intentionally on a real grammar-shape change)" do
    GOLDEN_ROOT_PREFIX =
      "root ::= tool-analyze | tool-at-a-glance | tool-breakdowns | tool-channels | tool-delete |"
    GOLDEN_TOOL_SEARCH_RULE =
      'tool-search ::= ("search") ( sp vocab-search-nouns )? ( sp ( "like" | "for" ) )? ( sp text )?'
    GOLDEN_VOCAB_SEARCH_NOUNS_RULE =
      'vocab-search-nouns ::= ("conversation" | "conversations" | "game" | "games" | "vid" | "video" | "videos" | "vids")'

    it "pins the root rule's opening alternatives" do
      expect(grammar).to start_with(GOLDEN_ROOT_PREFIX)
    end

    it "pins the tool-search rule verbatim" do
      expect(rule_line("tool-search ::=").chomp).to eq(GOLDEN_TOOL_SEARCH_RULE)
    end

    it "pins the vocab-search-nouns rule verbatim" do
      expect(rule_line("vocab-search-nouns ::=").chomp).to eq(GOLDEN_VOCAB_SEARCH_NOUNS_RULE)
    end
  end
end
