# frozen_string_literal: true

require "rails_helper"
require_relative "../support/dispatch_config_injection"

# ============================================================================
# THE ADD-A-TOOL PROOF  (G130 — the MCP analog of the add-a-verb proof)
# ============================================================================
# The owner's config-only contract, extended to MCP: a new read-only TOOL is a
# verbs.yml `mcp:` block (or an `mcp_readers:` entry) and NOTHING ELSE — no Ruby
# verb→tool table, no Registry edit, no endpoint edit. This file proves it.
#
# It invents a brand-new synthetic verb `almanac` carrying an `mcp:` block, plus a
# standalone `mcp_readers:` entry `pito_almanac_log`, injected as YAML through the
# test-only DispatchConfigInjection seam. With ZERO production edits it then proves:
#
#   1. SCHEMA    — Pito::Dispatch::Schema accepts the injected document.
#   2. TOOLS/LIST — Pito::Mcp::Registry surfaces both the verb-backed tool and the
#                   reader, with a correct JSON-Schema inputSchema derived from params.
#   3. EXECUTION — the tool's `input` grammar template builds a string the REAL
#                  Pito::Dispatch::Router recognizes as the `almanac` verb and runs
#                  its handler. (T2.2 will prove the Executor BUILDS that string from
#                  a `pito_almanac(topic:)` tool call and calls this same Router path.)
#   4. THE POINT — Registry / Router / Schema are the unmodified shipped code.
#
# A real new tool over an EXISTING read verb needs zero Ruby at all; this proof
# invents a whole verb, so it also adds one fixture handler — exactly as the
# add-a-verb proof does.

# ── The fixture handler — a plain read-only Pito::Chat::Handler subclass, reachable
# ONLY through the injected config's chat.dispatch. Writes nothing (MCP is read-only).
module Pito
  module DispatchProof
    class AlmanacHandler < Pito::Chat::Handler
      self.verb            = :almanac
      self.description_key = "pito.chat.almanac.descriptions.almanac"

      def call
        topic = message.body_tokens.map { |t| t.value.to_s.downcase }.first
        Pito::Chat::Result::Ok.new(events: [ {
          kind:    :system,
          payload: { "text" => "Almanac for #{topic}.", proof: :almanac, topic: }
        } ])
      end
    end
  end
end

RSpec.describe "the add-a-tool proof (G130)", type: :dispatch do
  # ── the synthetic verb + its mcp block, authored purely as YAML config ──────────
  ALMANAC_VERB_YAML = <<~YAML
    almanac:
      aliases: [almanacs]
      description: pito.chat.almanac.descriptions.almanac
      auth: session
      chat:
        dispatch: DispatchProof::AlmanacHandler
        slots:
          - name: topic
            kind: enum
            source: almanac_topics
            optional: true
      mcp:
        tool: pito_almanac
        description: "Read the almanac for a topic (proof tool)."
        read_only: true
        params:
          topic:  { type: string, enum: [weather, tides], required: true }
          detail: { type: array,  items: string, required: false, hint: "extra sections" }
        input: "almanac %{topic}"
        input_suffixes:
          detail: " with %{values}"
  YAML

  ALMANAC_VOCAB_YAML = <<~YAML
    almanac_topics:
      members: [weather, tides]
  YAML

  # A standalone reader tool with no backing verb.
  ALMANAC_READER_YAML = <<~YAML
    pito_almanac_log:
      tool: pito_almanac_log
      description: "Read the almanac request log (proof reader)."
      read_only: true
      params:
        limit: { type: integer, required: false, hint: "how many entries" }
  YAML

  let(:conversation) { Conversation.singleton }

  before do
    I18n.backend.store_translations(
      :en, pito: { chat: { almanac: { descriptions: { almanac: "Almanac — the proof tool verb." } } } }
    )
    inject_dispatch_config!(
      verbs:       ALMANAC_VERB_YAML,
      vocabularies: ALMANAC_VOCAB_YAML,
      mcp_readers: ALMANAC_READER_YAML
    )
  end

  after { restore_dispatch_config! }

  def parse(input)
    tokens = Pito::Lex::KeywordSanitizer.call(Pito::Lex::Lexer.call(input))
    Pito::Chat::Parser.call(tokens, raw: input, conversation:)
  end

  # ── 1. SCHEMA — the injected document (verb mcp block + reader) is well-formed ──
  describe "schema integrity" do
    it "Pito::Dispatch::Schema.validate accepts the injected document (0 errors)" do
      expect(Pito::Dispatch::Schema.validate(injected_dispatch_document)).to eq([])
    end
  end

  # ── 2. TOOLS/LIST — the Registry surfaces the new tools with ZERO Ruby edits ────
  describe "tools/list (Pito::Mcp::Registry, config-only)" do
    it "surfaces the verb-backed tool pito_almanac" do
      expect(Pito::Mcp::Registry.tool_names).to include("pito_almanac")
    end

    it "surfaces the standalone reader pito_almanac_log" do
      expect(Pito::Mcp::Registry.tool_names).to include("pito_almanac_log")
    end

    it "derives the tool's JSON-Schema inputSchema from its params" do
      tool = Pito::Mcp::Registry.tools.find { |t| t[:name] == "pito_almanac" }

      expect(tool[:description]).to match(/almanac/i)
      expect(tool[:inputSchema]).to include("type" => "object", "additionalProperties" => false)
      expect(tool[:inputSchema]["required"]).to eq(%w[topic])
      expect(tool[:inputSchema]["properties"]["topic"])
        .to include("type" => "string", "enum" => %w[weather tides])
      expect(tool[:inputSchema]["properties"]["detail"])
        .to include("type" => "array", "items" => { "type" => "string" })
    end

    it "returns the full verb descriptor (kind, backing verb, input template)" do
      d = Pito::Mcp::Registry.tool("pito_almanac")
      expect(d).to include(kind: :verb, verb: "almanac", input: "almanac %{topic}")
      expect(d[:input_suffixes]).to eq(detail: " with %{values}")
    end

    it "returns a reader descriptor with no backing verb" do
      d = Pito::Mcp::Registry.tool("pito_almanac_log")
      expect(d).to include(kind: :reader, verb: nil, input: nil)
      expect(d[:params]).to have_key(:limit)
    end
  end

  # ── 3. EXECUTION — the built grammar routes through the REAL Router ─────────────
  # T2.2 (Executor) will prove `pito_almanac(topic: "weather")` BUILDS "almanac
  # weather" from `input`/`input_suffixes`; here we prove that string dispatches.
  describe "execution (the tool's grammar template dispatches)" do
    it "the input template, once filled, parses as the almanac verb" do
      expect(parse("almanac weather").verb).to eq(:almanac)
    end

    it "Router.call runs the almanac handler for the tool's input string" do
      result = Pito::Dispatch::Router.call(input: "almanac weather", conversation:)

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload][:proof]).to eq(:almanac)
      expect(result.events.first[:payload][:topic]).to eq("weather")
    end

    it "an input_suffix clause also dispatches (almanac weather with tides)" do
      expect(parse("almanac weather with tides").verb).to eq(:almanac)
    end

    # T1.4b — the Executor BUILDS the grammar from a tool call and routes it, with
    # ZERO Ruby edits (the injected config drives the whole path).
    it "the Executor builds 'almanac weather' from a pito_almanac call and runs the handler" do
      result = Pito::Mcp::Executor.call(tool: "pito_almanac", arguments: { "topic" => "weather" })
      expect(result).to be_a(Pito::Mcp::Executor::Result)
      expect(result.is_error).to be(false)
      expect(result.text).to include("Almanac for weather.")
    end

    it "the Executor appends an input_suffix from an array argument (detail: [tides])" do
      expect(Pito::Mcp::Executor.build_input(
        Pito::Mcp::Registry.tool("pito_almanac"),
        { "topic" => "weather", "detail" => [ "tides" ] }
      )).to eq("almanac weather with tides")
    end
  end

  # ── 4. THE POINT — every path above ran against UNMODIFIED production code ──────
  describe "THE POINT — zero production code was touched" do
    {
      "lib/pito/mcp/registry.rb"    => [ Pito::Mcp::Registry, :tools ],
      "lib/pito/dispatch/router.rb" => [ Pito::Dispatch::Router, :call ],
      "lib/pito/dispatch/schema.rb" => [ Pito::Dispatch::Schema, :validate ]
    }.each do |relative_path, (mod, meth)|
      it "#{relative_path} is the real, unmodified implementation" do
        expect(mod.method(meth).source_location.first).to end_with(relative_path)
      end
    end

    it "the ONLY hand-written code the new tool needed is the fixture handler (in this spec)" do
      source = Pito::DispatchProof::AlmanacHandler.instance_method(:call).source_location.first
      expect(source).to end_with("spec/dispatch/add_a_tool_proof_spec.rb")
    end
  end
end
