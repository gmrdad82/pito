# frozen_string_literal: true

require "rails_helper"
require_relative "../support/dispatch_config_injection"

# ============================================================================
# THE ADD-A-VERB PROOF  (plan-0.9.5 T8.12b — the P3 acceptance criterion)
# ============================================================================
# Owner's requirement, verbatim: "the foundation of being able to add future
# verbs from the YAML config without touching dispatcher, router, etc. We'll
# implement stuff like builder ofc."
#
# This file PROVES that claim end-to-end. It introduces a brand-new synthetic
# verb — `ping` (alias `pong`) — built out of NOTHING BUT:
#
#   1. a schema-valid config entry (injected as YAML into Pito::Dispatch::Config
#      through the test-only DispatchConfigInjection seam — see
#      spec/support/dispatch_config_injection.rb): a chat branch with one enum
#      slot over a tiny inline vocabulary, a dispatch class, a description key,
#      and a reply branch on the REAL `game_list` target (mode: append + a
#      `ref` resolver);
#   2. a fixture handler class (Pito::DispatchProof::PingHandler, below) that
#      answers the uniform dispatch contract call(kwargs:, context:) → Result::Ok
#      — the "we'll implement the builder ofc" part;
#   3. I18n test translations for its copy key.
#
# It then exercises SCHEMA, RECOGNITION, PALETTE, DISPATCH and REPLY through the
# PUBLIC ENTRY POINTS ONLY. Every one of those paths runs against UNMODIFIED
# router / matrix / schema / engine / reply-binding / delegator code — this file
# adds a spec plus a test-support helper and NOTHING under lib/ or app/. "THE
# POINT" example group asserts that structurally, via each class's real
# source_location.

# ── The fixture handler — the only hand-written code a verb author adds (besides
# the YAML). A plain Pito::Chat::Handler subclass: the base class supplies the
# uniform class-level call(kwargs:, context:) for free (lib/pito/chat/handler.rb).
# Deliberately NOT namespaced under Pito::Chat::Handlers, so no registry or
# handler sweep ever picks it up — it is reachable ONLY because the injected
# config's `chat.dispatch` points at it.
module Pito
  module DispatchProof
    class PingHandler < Pito::Chat::Handler
      self.verb            = :ping
      self.description_key = "pito.chat.ping.descriptions.ping"

      def call
        # Typed path: the mood enum token flows in via the parsed message.
        # Reply path: the row ref (a ::Game) bound by ReplyBinding arrives in kwargs.
        mood = message.body_tokens.map { |t| t.value.to_s.downcase }.first
        Pito::Chat::Result::Ok.new(events: [ {
          kind:    :system,
          payload: { proof: :ping, mood:, ref_id: kwargs[:ref]&.id }
        } ])
      end
    end
  end
end

RSpec.describe "the add-a-verb proof (T8.12b)", type: :dispatch do
  # ── the synthetic verb, authored purely as YAML config ──────────────────────
  PING_VERB_YAML = <<~YAML
    ping:
      aliases: [pong]
      description: pito.chat.ping.descriptions.ping
      auth: session
      chat:
        dispatch: DispatchProof::PingHandler
        slots:
          - name: mood
            kind: enum
            source: ping_moods
            optional: true
      reply:
        targets:
          game_list:
            mode: append
            ref: { resolver: id_among_rows }
  YAML

  # Members intentionally OUT of alphabetical order — the palette must sort them.
  PING_VOCAB_YAML = <<~YAML
    ping_moods:
      members: [zoom, zap, zip]
  YAML

  SORTED_MOODS = %w[zap zip zoom].freeze

  let(:conversation) { Conversation.singleton }

  before do
    I18n.backend.store_translations(
      :en, pito: { chat: { ping: { descriptions: { ping: "Ping — the proof verb." } } } }
    )
    inject_dispatch_config!(verbs: PING_VERB_YAML, vocabularies: PING_VOCAB_YAML)
  end

  after { restore_dispatch_config! }

  # Runs the real Lex → sanitize → Parser path (exactly what Router#parse does).
  def parse(input)
    tokens = Pito::Lex::KeywordSanitizer.call(Pito::Lex::Lexer.call(input))
    Pito::Chat::Parser.call(tokens, raw: input, conversation:)
  end

  # ── 1. SCHEMA — the injected document is well-formed ────────────────────────
  describe "schema integrity" do
    it "Pito::Dispatch::Schema.validate accepts the injected document (0 errors)" do
      expect(Pito::Dispatch::Schema.validate(injected_dispatch_document)).to eq([])
    end

    it "introduces no alias collisions (ping / pong are unique tokens)" do
      expect(Pito::Dispatch::Schema.alias_collisions(injected_dispatch_document)).to eq([])
    end

    it "the ping verb reads back through the public Config.verb API" do
      expect(Pito::Dispatch::Config.verb(:ping).dig(:chat, :dispatch)).to eq("DispatchProof::PingHandler")
    end
  end

  # ── 2. RECOGNITION — verb + alias parse as :ping (Lex/parse path) ────────────
  describe "recognition" do
    it "parses the canonical verb as a :new_turn for :ping" do
      msg = parse("ping zap")
      expect(msg.kind).to eq(:new_turn)
      expect(msg.verb).to eq(:ping)
    end

    it "canonicalises the alias pong → ping" do
      expect(parse("pong zap").verb).to eq(:ping)
    end
  end

  # ── 3. PALETTE — the verb + its slot members surface ────────────────────────
  describe "palette" do
    it "lists ping in the chat verb-stage completions, carrying its enum slot" do
      chat  = Pito::Suggestions::Catalog.to_h(authenticated: true)[:chat]
      entry = chat.find { |e| e[:name] == "ping" }

      expect(entry).to be_present
      expect(entry[:slots]).to include({ name: "mood", source: "ping_moods" })
    end

    it "autosuggests the slot's members alphabetically after 'ping '" do
      result = Pito::Suggestions::Engine.call(input: "ping ", cursor: 5, authenticated: true)

      expect(result[:menu_items].map { |i| i[:label] }).to eq(SORTED_MOODS)
    end
  end

  # ── 4. DISPATCH — Router runs the fixture handler end-to-end ─────────────────
  describe "dispatch (typed free-chat)" do
    it "routes 'ping zap' to the fixture handler and returns its Result::Ok" do
      result = Pito::Dispatch::Router.call(input: "ping zap", conversation:)

      expect(result).to be_a(Pito::Chat::Result::Ok)
      payload = result.events.first[:payload]
      expect(payload[:proof]).to eq(:ping)
      expect(payload[:mood]).to eq("zap") # the slot value reached the handler
    end

    it "dispatches through the alias too (pong → ping)" do
      result = Pito::Dispatch::Router.call(input: "pong zip", conversation:)

      expect(result.events.first[:payload][:mood]).to eq("zip")
    end
  end

  # ── 5. REPLY — ping is a config-driven action on the real game_list target ───
  describe "reply (declared on game_list)" do
    let!(:game) { create(:game) }
    let(:source_event) { instance_double(Event, payload: { "reply_target" => "game_list" }) }

    it "Pito::Dispatch::Matrix.actions_for(game_list) includes ping" do
      expect(Pito::Dispatch::Matrix.actions_for("game_list")).to include("ping")
    end

    it "FollowUp::Registry.actions_for (Matrix-derived) exposes ping to the reply gate" do
      expect(Pito::FollowUp::Registry.actions_for("game_list")).to include("ping")
    end

    it "VerbDelegator executes ping through the SAME Router path, binding the row ref" do
      result = Pito::FollowUp::VerbDelegator.call(
        source_event:, rest: "ping #{game.id}", conversation:
      )

      expect(result).to be_a(Pito::FollowUp::Result::Append)
      payload = result.events.first[:payload]
      expect(payload[:proof]).to eq(:ping)
      expect(payload[:ref_id]).to eq(game.id) # kwargs[:ref] resolved by id_among_rows
    end
  end

  # ── 6. THE POINT — every path above ran against UNMODIFIED production code ───
  #
  # The dispatch machinery this proof exercised is the real code shipped under
  # lib/ and app/: this file monkeypatches NONE of it. Proven structurally — each
  # class's live entry method resolves to its production source file, never this
  # spec. The only new artefacts are this spec + the config-injection support
  # helper (both test-only) and the fixture handler defined above. A future verb
  # therefore needs exactly: a YAML entry + a handler class. Zero dispatcher edits.
  describe "THE POINT — zero production code was touched" do
    {
      "lib/pito/dispatch/router.rb"                   => [ Pito::Dispatch::Router, :call ],
      "lib/pito/dispatch/matrix.rb"                   => [ Pito::Dispatch::Matrix, :actions_for ],
      "lib/pito/dispatch/schema.rb"                   => [ Pito::Dispatch::Schema, :validate ],
      "lib/pito/dispatch/reply_binding.rb"            => [ Pito::Dispatch::ReplyBinding, :bind ],
      "app/services/pito/suggestions/engine.rb"       => [ Pito::Suggestions::Engine, :call ],
      "app/services/pito/follow_up/verb_delegator.rb" => [ Pito::FollowUp::VerbDelegator, :call ]
    }.each do |relative_path, (mod, meth)|
      it "#{relative_path} is the real, unmodified implementation" do
        source = mod.method(meth).source_location.first
        expect(source).to end_with(relative_path)
      end
    end

    it "the ONLY hand-written code the new verb needed is the fixture handler (in this spec)" do
      source = Pito::DispatchProof::PingHandler.instance_method(:call).source_location.first
      expect(source).to end_with("spec/dispatch/add_a_verb_proof_spec.rb")
    end
  end
end
