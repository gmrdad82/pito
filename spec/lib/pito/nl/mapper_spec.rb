# frozen_string_literal: true

require "rails_helper"

# Coverage map — Pito::Nl::Mapper is the GBNF-constrained few-shot composer
# Pito::Nl::Router hands off to when no cached nl_examples neighbor is close
# enough (see mapper.rb's own header for the full router-vs-mapper split).
# Pito::Nl::CompletionClient is stubbed throughout — the live nlmapper
# sidecar is NEVER hit — while the validity check runs through the REAL chat
# parser pipeline (Pito::Lex::Lexer -> Pito::Lex::KeywordSanitizer ->
# Pito::Chat::Parser), exactly as #parsed_tool documents.
RSpec.describe Pito::Nl::Mapper do
  let(:client) { instance_double(Pito::Nl::CompletionClient) }

  before do
    allow(Pito::Nl::CompletionClient).to receive(:new).and_return(client)
  end

  # Mapper memoizes its grammar (full AND per-tool) in module ivars keyed on
  # Pito::Dispatch::Config.data's object identity (see mapper.rb's #grammar
  # comment). Nothing else in the app references Pito::Nl::Mapper yet, but
  # resetting around every example keeps this file's own memoization specs
  # from leaking state into any other example here, regardless of run order.
  around do |example|
    original_grammar = described_class.instance_variable_get(:@grammar)
    original_tool_grammars = described_class.instance_variable_get(:@tool_grammars)
    original_data = described_class.instance_variable_get(:@grammar_data)
    example.run
    described_class.instance_variable_set(:@grammar, original_grammar)
    described_class.instance_variable_set(:@tool_grammars, original_tool_grammars)
    described_class.instance_variable_set(:@grammar_data, original_data)
  end

  # Independently rebuilds the expected few-shot message array straight off
  # Pito::Dispatch::Config — a regression check against #chat_messages, not a
  # tautology against the mapper's own (private) implementation. Reads the
  # exemplar count off Config itself rather than a hardcoded number, so an
  # authored exemplar never silently desyncs this spec from tools.yml.
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

      it "sends a system turn, 2x the exemplar count of alternating turns, then the utterance" do
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
