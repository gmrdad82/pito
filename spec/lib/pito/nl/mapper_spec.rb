# frozen_string_literal: true

require "rails_helper"

# Coverage map — Pito::Nl::Mapper is the GBNF-constrained few-shot composer
# Pito::Nl::Router hands off to when no cached nl_examples neighbor is close
# enough (see mapper.rb's own header for the full router-vs-mapper split).
# Pito::Nl::CompletionClient is stubbed throughout — the live nlmapper
# sidecar is NEVER hit — and so is Pito::Embedding::Client (the few-shot
# retrieval's embedder, v2): by DEFAULT it returns nil vectors, which
# exercises the mapper's static full-pool fallback and keeps every example
# deterministic even when a real PITO_EMBEDDER_URL is exported in the shell
# (WebMock allows localhost). Retrieval-specific contexts override the stub
# with hand-built vectors. The validity check runs through the REAL chat
# parser pipeline (Pito::Lex::Lexer -> Pito::Lex::KeywordSanitizer ->
# Pito::Chat::Parser), exactly as #parsed_tool documents.
RSpec.describe Pito::Nl::Mapper do
  let(:client) { instance_double(Pito::Nl::CompletionClient) }
  let(:embedder) { instance_double(Pito::Embedding::Client) }

  before do
    allow(Pito::Nl::CompletionClient).to receive(:new).and_return(client)
    allow(Pito::Embedding::Client).to receive(:new).and_return(embedder)
    allow(embedder).to receive(:embed) { |texts| Array.new(Array(texts).length) }
  end

  # Mapper memoizes its grammar (full AND per-tool) and its exemplar `say`
  # vectors in module ivars keyed on Pito::Dispatch::Config.data's object
  # identity (see mapper.rb's #grammar / #exemplar_vectors comments). Nothing
  # else in the app references Pito::Nl::Mapper yet, but resetting around
  # every example keeps this file's own memoization specs from leaking state
  # into any other example here, regardless of run order.
  around do |example|
    original_grammar = described_class.instance_variable_get(:@grammar)
    original_tool_grammars = described_class.instance_variable_get(:@tool_grammars)
    original_data = described_class.instance_variable_get(:@grammar_data)
    original_vectors = described_class.instance_variable_get(:@exemplar_vectors)
    original_vector_data = described_class.instance_variable_get(:@exemplar_data)
    example.run
    described_class.instance_variable_set(:@grammar, original_grammar)
    described_class.instance_variable_set(:@tool_grammars, original_tool_grammars)
    described_class.instance_variable_set(:@grammar_data, original_data)
    described_class.instance_variable_set(:@exemplar_vectors, original_vectors)
    described_class.instance_variable_set(:@exemplar_data, original_vector_data)
  end

  # Independently rebuilds the expected FULL-POOL few-shot message array
  # straight off Pito::Dispatch::Config — the shape of the static fallback
  # (and of any pool within the FEW_SHOT_TOP_K budget). A regression check
  # against #chat_messages, not a tautology against the mapper's own
  # (private) implementation. Reads the exemplar count off Config itself
  # rather than a hardcoded number, so an authored exemplar never silently
  # desyncs this spec from tools.yml.
  def expected_messages(final_content)
    messages = [ { role: "system", content: described_class::INSTRUCTION } ]
    Pito::Dispatch::Config.nl_exemplars.each do |exemplar|
      messages << { role: "user", content: exemplar[:say] }
      messages << { role: "assistant", content: exemplar[:run] }
    end
    messages << { role: "user", content: final_content }
    messages
  end

  describe ".map" do
    context "when the completion parses to a known chat tool" do
      it "returns the stripped command and its canonicalized tool" do
        allow(client).to receive(:chat).and_return(" ls vids \n")

        expect(described_class.map("show my vids")).to eq(command: "ls vids", tool: :list)
      end

      it "sends a system turn, the FULL exemplar pool (static fallback — embedder stubbed away), then the utterance" do
        captured = nil
        allow(client).to receive(:chat) do |messages:, **|
          captured = messages
          "ls vids"
        end

        described_class.map("show my vids")

        expect(captured).to eq(expected_messages("show my vids"))
        expect(captured.first).to eq(role: "system", content: described_class::INSTRUCTION)
        expect(captured.last).to eq(role: "user", content: "show my vids")
        expect(captured[1...-1].size).to eq(2 * Pito::Dispatch::Config.nl_exemplars.size)
      end
    end

    # The v2 few-shot retrieval (see mapper.rb's #chat_messages design note):
    # exemplar `say` vectors + the utterance vector are hand-built 2-dim
    # geometry here — exemplar i gets [i, 1], the utterance [1, 0], so cosine
    # similarity STRICTLY INCREASES with pool index and the nearest
    # FEW_SHOT_TOP_K are exactly the LAST K pool entries. Similarity-rank
    # order (descending) is then the REVERSE of tools.yml order, which is
    # what makes the original-order assertion below prove the reordering
    # actually happens rather than fall out of the ranking by accident.
    context "few-shot retrieval (embedder available)" do
      let(:pool) { Pito::Dispatch::Config.nl_exemplars }

      before do
        allow(embedder).to receive(:embed) do |texts|
          texts.map do |text|
            index = pool.index { |exemplar| exemplar[:say] == text }
            index ? [ index.to_f, 1.0 ] : [ 1.0, 0.0 ]
          end
        end
      end

      it "prompts with only the FEW_SHOT_TOP_K nearest exemplars, restored to original tools.yml order" do
        skip "needs a pool larger than FEW_SHOT_TOP_K" unless pool.size > described_class::FEW_SHOT_TOP_K

        captured = nil
        allow(client).to receive(:chat) do |messages:, **|
          captured = messages
          "ls vids"
        end

        described_class.map("show my vids")

        nearest_in_original_order = pool.last(described_class::FEW_SHOT_TOP_K)
        expect(captured[1...-1]).to eq(
          nearest_in_original_order.flat_map do |exemplar|
            [ { role: "user", content: exemplar[:say] }, { role: "assistant", content: exemplar[:run] } ]
          end
        )
        expect(captured.size).to eq(2 + 2 * described_class::FEW_SHOT_TOP_K)
      end

      it "skips embedding entirely when the pool already fits the FEW_SHOT_TOP_K budget" do
        allow(Pito::Dispatch::Config).to receive(:nl_exemplars).and_return(pool.first(2))
        allow(client).to receive(:chat).and_return("ls vids")

        described_class.map("show my vids")

        expect(embedder).not_to have_received(:embed)
      end

      it "embeds the pool once across maps, and re-embeds after Config.reload!" do
        allow(client).to receive(:chat).and_return("ls vids")

        described_class.map("show my vids")
        described_class.map("show my games")

        # The pool embed is the only multi-text call; per-map utterance
        # embeds are single-text and excluded by the length predicate.
        expect(embedder).to have_received(:embed).with(satisfy { |texts| texts.length > 1 }).once

        Pito::Dispatch::Config.reload!
        described_class.map("show my vids")

        expect(embedder).to have_received(:embed).with(satisfy { |texts| texts.length > 1 }).twice
      end
    end

    # The graceful-degradation contract: retrieval failing at EITHER embed
    # (the pool or the utterance) must yield the exact v1 static full-pool
    # prompt — never a partial selection, never an error — plus one warn.
    context "few-shot retrieval fallback" do
      let(:pool) { Pito::Dispatch::Config.nl_exemplars }

      it "falls back to the full pool with a warn when the embedder is unconfigured/unreachable (nil vectors)" do
        allow(Rails.logger).to receive(:warn).and_call_original
        captured = nil
        allow(client).to receive(:chat) do |messages:, **|
          captured = messages
          "ls vids"
        end

        described_class.map("show my vids")

        expect(captured).to eq(expected_messages("show my vids"))
        expect(Rails.logger).to have_received(:warn).with(/exemplar retrieval unavailable/)
      end

      it "falls back to the full pool when only the utterance embed returns nil" do
        allow(embedder).to receive(:embed) do |texts|
          texts.length == 1 ? [ nil ] : texts.map { [ 1.0, 0.0 ] }
        end
        captured = nil
        allow(client).to receive(:chat) do |messages:, **|
          captured = messages
          "ls vids"
        end

        described_class.map("show my vids")

        expect(captured).to eq(expected_messages("show my vids"))
      end

      it "does not cache a failed pool embed — the next map retries and recovers" do
        skip "needs a pool larger than FEW_SHOT_TOP_K" unless pool.size > described_class::FEW_SHOT_TOP_K

        pool_embed_calls = 0
        allow(embedder).to receive(:embed) do |texts|
          if texts.length > 1
            pool_embed_calls += 1
            pool_embed_calls == 1 ? Array.new(texts.length) : texts.map { [ 1.0, 0.0 ] }
          else
            [ [ 1.0, 0.0 ] ]
          end
        end
        captured = nil
        allow(client).to receive(:chat) do |messages:, **|
          captured = messages
          "ls vids"
        end

        described_class.map("show my vids")
        expect(captured).to eq(expected_messages("show my vids"))

        described_class.map("show my vids")
        expect(captured[1...-1].size).to eq(2 * described_class::FEW_SHOT_TOP_K)
        expect(pool_embed_calls).to eq(2)
      end
    end

    context "when the completion is junk that fails to parse (a slash lookalike)" do
      it "returns nil" do
        allow(client).to receive(:chat).and_return("/nope")

        expect(described_class.map("do the thing")).to be_nil
      end
    end

    context "when the completion parses but resolves to no known chat tool" do
      it "returns nil" do
        allow(client).to receive(:chat).and_return("banana risotto")

        expect(described_class.map("do the thing")).to be_nil
      end
    end

    # The Q27c write-tool guard (WRITE_ACTION_LEXICON — see mapper.rb): a
    # composition landing on a WRITE tool survives only when the owner's own
    # words name that tool's action. The completion is stubbed to the exact
    # wrong/right command, so these prove the GUARD's verdict, not the
    # model's — "crack open vid 30" can never come back as a link no matter
    # what the sidecar emits.
    context "write-tool guard" do
      it "refuses a link composition for a phrase that never names a link action" do
        allow(client).to receive(:chat).and_return("link 30 3")

        expect(described_class.map("crack open vid 30")).to be_nil
      end

      it "refuses the same unasked write on the tool:-constrained re-try path" do
        allow(client).to receive(:chat).and_return("link 30 3")

        expect(described_class.map("crack open vid 30", tool: :link)).to be_nil
      end

      it "composes delete when the phrase names the action" do
        allow(client).to receive(:chat).and_return("delete vid 4")

        expect(described_class.map("kill vid 4")).to eq(command: "delete vid 4", tool: :delete)
      end

      it "counts a folded nl.synonym as naming the action (remove -> delete)" do
        allow(client).to receive(:chat).and_return("delete vid 4")

        expect(described_class.map("please remove vid 4")).to eq(command: "delete vid 4", tool: :delete)
      end

      it "counts an update-footage auto-run phrasing as action-named (the Q17 exception)" do
        allow(client).to receive(:chat).and_return("update game footage 7 9")

        expect(described_class.map("logged another two hours on game 7"))
          .to eq(command: "update game footage 7 9", tool: :update)
      end

      it "leaves read-tool compositions unguarded" do
        allow(client).to receive(:chat).and_return("analyze vid 30 full")

        expect(described_class.map("crack open vid 30")).to eq(command: "analyze vid 30 full", tool: :analyze)
      end

      # 2026-07-20 verify-pass re-derivation (see WRITE_ACTION_LEXICON's
      # derivation-rule comment): update's attested acquisition/platform
      # verbs (add/put/pick-up/pay/cost/come-out/runs-on) survive the
      # guard; copula-only facts still block — the boundary is an
      # owner-action verb. The say-phrases here are the exact nl_examples
      # rows the omission degraded to the huh copy.
      it "composes update when an attested acquisition verb names the action" do
        allow(client).to receive(:chat).and_return("update game price 5 12")

        expect(described_class.map("picked up game 5 for 12 bucks"))
          .to eq(command: "update game price 5 12", tool: :update)
      end

      it "composes update for a verbed platform imperative" do
        allow(client).to receive(:chat).and_return("update game platform 12 ps5")

        expect(described_class.map("add ps5 to game 12"))
          .to eq(command: "update game platform 12 ps5", tool: :update)
      end

      it "still refuses an update composition for a copula-only fact statement" do
        allow(client).to receive(:chat).and_return("update game platform 42 switch")

        expect(described_class.map("game 42 is also on switch")).to be_nil
      end

      # The pool-wide coherence invariant (same verify pass): every
      # nl.exemplars pair whose run-command parses to a guarded write tool
      # must carry a say-phrase that names that tool's action — the
      # few-shot pool must never teach a composition the guard then
      # refuses. (Module_function makes Mapper's helpers public module
      # methods, so the guard's own predicate chain is exercised directly.)
      it "accepts the say-phrase of every write-tool exemplar in the pool" do
        Pito::Dispatch::Config.nl_exemplars.each do |exemplar|
          tool = described_class.parsed_tool(exemplar[:run])
          next unless described_class::WRITE_ACTION_LEXICON.key?(tool)

          normalized = described_class.normalize(exemplar[:say])
          expect(described_class.action_named?(tool: tool, utterance: normalized)).to be(true),
            "nl.exemplars pair #{exemplar[:say].inspect} -> #{exemplar[:run].inspect} " \
            "teaches a #{tool} composition its own say-phrase cannot survive"
        end
      end
    end

    context "when the sidecar is unreachable (client returns nil)" do
      it "returns nil" do
        allow(client).to receive(:chat).and_return(nil)

        expect(described_class.map("show my vids")).to be_nil
      end
    end

    context "when the utterance is blank" do
      it "returns nil without ever building a completion client" do
        expect(Pito::Nl::CompletionClient).not_to receive(:new)

        expect(described_class.map("")).to be_nil
        expect(described_class.map(nil)).to be_nil
        expect(described_class.map("   ")).to be_nil
      end
    end

    context "grammar memoization" do
      before { allow(Pito::Nl::GbnfBuilder).to receive(:call).and_call_original }

      it "builds the grammar once for repeated maps, then rebuilds after Config.reload!" do
        allow(client).to receive(:chat).and_return("ls vids")

        described_class.map("show my vids")
        described_class.map("show my games")

        expect(Pito::Nl::GbnfBuilder).to have_received(:call).once

        Pito::Dispatch::Config.reload!
        described_class.map("show my vids")

        expect(Pito::Nl::GbnfBuilder).to have_received(:call).twice
      end
    end

    context "normalization parity with Pito::Nl::Router#normalize" do
      it "routes a synonym-bearing utterance through its normalized form in the final user turn" do
        captured = nil
        allow(client).to receive(:chat) do |messages:, **|
          captured = messages
          "ls vids"
        end

        described_class.map("show me my clips")

        expect(captured.last).to eq(role: "user", content: "show me my vids")
      end
    end
  end
end
