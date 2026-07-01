# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Grammar::Normalizer do
  # ── Fixture spec setup ────────────────────────────────────────────────────

  before do
    Pito::Grammar::Registry.register_all!

    # :chat namespace fixture specs
    Pito::Grammar::Registry.register_spec(
      Pito::Grammar::Spec.new(
        namespace: :chat,
        name: :list,
        slots: [
          Pito::Grammar::Slot.new(name: :status,   kind: :enum, source: :release_status, optional: true),
          Pito::Grammar::Slot.new(name: :genre,    kind: :enum, source: :genres, repeatable: true, optional: true),
          Pito::Grammar::Slot.new(name: :platform, kind: :enum, source: :platforms, optional: true, introducer: :for)
        ]
      )
    )

    # :chat :search — free slot fixture
    Pito::Grammar::Registry.register_spec(
      Pito::Grammar::Spec.new(
        namespace: :chat,
        name: :search,
        slots: [
          Pito::Grammar::Slot.new(name: :query, kind: :free, optional: true)
        ]
      )
    )

    # :chat :config — kv slot fixture
    Pito::Grammar::Registry.register_spec(
      Pito::Grammar::Spec.new(
        namespace: :chat,
        name: :config,
        slots: [
          Pito::Grammar::Slot.new(name: :settings, kind: :kv, optional: true, repeatable: true)
        ]
      )
    )
  end

  after { Pito::Grammar::Registry.reset! }

  def lex(s) = Pito::Lex::Lexer.call(s)

  # ── Task i: core normalization ─────────────────────────────────────────────

  describe ".call" do
    describe "full happy path — multi-slot with connectives" do
      subject(:match) do
        described_class.call(
          lex("list upcoming racing and rpg games for playstation"),
          namespace: :chat
        )
      end

      it "resolves the verb" do
        expect(match.name).to eq(:list)
      end

      it "is matched" do
        expect(match).to be_matched
      end

      it "resolves status to 'upcoming'" do
        expect(match.values[:status]).to eq("upcoming")
      end

      it "resolves genre to Racing and RPG (repeatable)" do
        expect(match.values[:genre]).to eq([ "Racing", "RPG" ])
      end

      it "resolves platform to 'PlayStation 5' via `for` introducer" do
        expect(match.values[:platform]).to eq("PlayStation 5")
      end

      it "returns the full expected values hash" do
        expect(match.values).to eq(
          status: "upcoming",
          genre:  [ "Racing", "RPG" ],
          platform: "PlayStation 5"
        )
      end

      it "has no unknowns (games is a filler)" do
        expect(match.unknowns).to be_empty
      end

      it "has no leftovers" do
        expect(match.leftovers).to be_empty
      end

      it "has confidence 1.0 (clean match)" do
        expect(match.confidence).to eq(1.0)
      end
    end

    describe "partial / unresolvable enum value" do
      subject(:match) { described_class.call(lex("list upc"), namespace: :chat) }

      it "resolves the verb to :list" do
        expect(match.name).to eq(:list)
      end

      it "is matched (verb resolved)" do
        expect(match).to be_matched
      end

      it "puts the unresolvable token in unknowns" do
        expect(match.unknowns).to include("upc")
      end

      it "does not put unresolvable token in leftovers" do
        expect(match.leftovers).not_to include("upc")
      end
    end

    describe "non-member enum word goes to unknowns" do
      subject(:match) { described_class.call(lex("list zzzz"), namespace: :chat) }

      it "resolves the verb" do
        expect(match.name).to eq(:list)
      end

      it "is matched" do
        expect(match).to be_matched
      end

      it "puts zzzz in unknowns" do
        expect(match.unknowns).to include("zzzz")
      end

      it "reduces confidence below 1.0" do
        expect(match.confidence).to be < 1.0
      end
    end

    describe "unknown verb" do
      subject(:match) { described_class.call(lex("frobnicate stuff"), namespace: :chat) }

      it "is not matched" do
        expect(match).not_to be_matched
      end

      it "returns nil name" do
        expect(match.name).to be_nil
      end

      it "has zero confidence" do
        expect(match.confidence).to eq(0.0)
      end
    end

    describe ":free slot — slurps remaining tokens as a string" do
      subject(:match) { described_class.call(lex("search dark souls remastered"), namespace: :chat) }

      it "resolves the verb to :search" do
        expect(match.name).to eq(:search)
      end

      it "is matched" do
        expect(match).to be_matched
      end

      it "captures all remaining tokens in the free slot" do
        expect(match.values[:query]).to eq("dark souls remastered")
      end

      it "has no leftovers" do
        expect(match.leftovers).to be_empty
      end
    end

    describe ":kv slot — captures key:value pairs with numeric coercion" do
      subject(:match) { described_class.call(lex("config limit:50 threshold:0.75"), namespace: :chat) }

      it "resolves the verb to :config" do
        expect(match.name).to eq(:config)
      end

      it "is matched" do
        expect(match).to be_matched
      end

      it "stores integer value" do
        expect(match.kwargs[:limit]).to eq(50)
      end

      it "coerces integer to Integer" do
        expect(match.kwargs[:limit]).to be_a(Integer)
      end

      it "stores float value" do
        expect(match.kwargs[:threshold]).to eq(0.75)
      end

      it "coerces float to Float" do
        expect(match.kwargs[:threshold]).to be_a(Float)
      end
    end

    describe ":kv slot — string value is kept as String" do
      subject(:match) { described_class.call(lex("config mode:debug"), namespace: :chat) }

      it "stores string value as String" do
        expect(match.kwargs[:mode]).to eq("debug")
      end
    end

    describe "filler words are silently dropped" do
      subject(:match) { described_class.call(lex("list the upcoming rpg games"), namespace: :chat) }

      it "resolves status correctly despite fillers" do
        expect(match.values[:status]).to eq("upcoming")
      end

      it "resolves genre correctly despite fillers" do
        expect(match.values[:genre]).to eq([ "RPG" ])
      end

      it "has no unknowns" do
        expect(match.unknowns).to be_empty
      end
    end

    describe "platform without introducer is not resolved" do
      # 'playstation' without 'for' should NOT fill the platform slot
      # because platform has introducer: :for
      subject(:match) { described_class.call(lex("list playstation"), namespace: :chat) }

      it "does not fill platform without the `for` introducer" do
        expect(match.values[:platform]).to be_nil
      end

      it "puts playstation in unknowns (no free slot, has enum slots)" do
        expect(match.unknowns).to include("playstation")
      end
    end
  end

  describe "connective `and` in repeatable slot" do
    it "appends both values to the same slot across `and`" do
      match = described_class.call(lex("list racing and rpg"), namespace: :chat)
      expect(match.values[:genre]).to eq([ "Racing", "RPG" ])
    end
  end

  describe "connective `for` as introducer" do
    it "fills introducer-gated slot when `for` precedes the value" do
      match = described_class.call(lex("list for playstation"), namespace: :chat)
      expect(match.values[:platform]).to eq("PlayStation 5")
    end

    it "consumes the `for` token (not in leftovers or unknowns)" do
      match = described_class.call(lex("list for playstation"), namespace: :chat)
      expect(match.leftovers).not_to include("for")
      expect(match.unknowns).not_to include("for")
    end
  end

  # ── Repeatable enum accumulation ──────────────────────────────────────────

  describe "repeatable enum accumulation" do
    it "collects all matching genre tokens into an Array in order" do
      match = described_class.call(lex("list racing rpg shooter"), namespace: :chat)
      expect(match.values[:genre]).to eq([ "Racing", "RPG", "Shooter" ])
    end

    it "genre and status can coexist — each fills its own slot" do
      match = described_class.call(lex("list upcoming rpg racing"), namespace: :chat)
      expect(match.values[:status]).to eq("upcoming")
      expect(match.values[:genre]).to eq([ "RPG", "Racing" ])
    end

    it "a single repeatable value is still stored as an Array" do
      match = described_class.call(lex("list rpg"), namespace: :chat)
      expect(match.values[:genre]).to eq([ "RPG" ])
      expect(match.values[:genre]).to be_an(Array)
    end
  end

  # ── Filler-word stripping (deep) ──────────────────────────────────────────

  describe "filler-word stripping" do
    it "strips multiple consecutive global filler words" do
      match = described_class.call(lex("list the a an games upcoming rpg"), namespace: :chat)
      expect(match.values[:status]).to eq("upcoming")
      expect(match.values[:genre]).to eq([ "RPG" ])
      expect(match.unknowns).to be_empty
    end

    it "filler words are not counted in confidence penalty" do
      match = described_class.call(lex("list the upcoming rpg games"), namespace: :chat)
      expect(match.confidence).to eq(1.0)
    end
  end

  # ── Introducer-gated slots (deeper) ───────────────────────────────────────

  describe "introducer-gated slot — platform only allowed after `for`" do
    it "platform word without `for` goes to unknowns" do
      match = described_class.call(lex("list switch"), namespace: :chat)
      expect(match.values[:platform]).to be_nil
      expect(match.unknowns).to include("switch")
    end

    it "platform word after `for` is resolved and not in unknowns" do
      match = described_class.call(lex("list for switch"), namespace: :chat)
      expect(match.values[:platform]).to eq("Nintendo Switch")
      expect(match.unknowns).to be_empty
    end
  end

  # ── Conditional slots (when: / eligible?) ─────────────────────────────────

  describe "conditional slots — when: condition" do
    before do
      # Register a :slash :toggle spec with conditional slots:
      #   literal :mode   — source: :config_providers
      #   enum    :state  — source: :on_off, condition: { mode: %w[sound fx] }
      #   kv      :cfg    — source: :config_keys, condition: { mode: %w[google voyage] }
      Pito::Grammar::Registry.register_spec(
        Pito::Grammar::Spec.new(
          namespace: :slash,
          name: :toggle,
          slots: [
            Pito::Grammar::Slot.new(name: :mode, kind: :literal, source: :config_providers),
            Pito::Grammar::Slot.new(name: :state, kind: :enum, source: :on_off,
                                    optional: true,
                                    condition: { mode: %w[sound] }),
            Pito::Grammar::Slot.new(name: :cfg, kind: :kv, source: :config_keys,
                                    optional: true, repeatable: true,
                                    condition: { mode: %w[google voyage] })
          ]
        )
      )
    end

    describe "when prior literal resolves to a toggle provider (sound)" do
      subject(:match) { described_class.call(lex("toggle sound on"), namespace: :slash) }

      it "resolves the verb to :toggle" do
        expect(match.name).to eq(:toggle)
      end

      it "captures state as 'on'" do
        expect(match.values[:state]).to eq("on")
      end

      it "does not fill :cfg (ineligible for sound)" do
        expect(match.values[:cfg]).to be_nil
      end

      it "has no unknowns" do
        expect(match.unknowns).to be_empty
      end
    end

    describe "when prior literal resolves to a credential provider (google)" do
      subject(:match) { described_class.call(lex("toggle google"), namespace: :slash) }

      it "resolves the verb to :toggle" do
        expect(match.name).to eq(:toggle)
      end

      it "does not fill :state (ineligible for google)" do
        expect(match.values[:state]).to be_nil
      end
    end

    describe "on/off synonym resolution via condition-gated enum" do
      it "resolves 'off' to canonical 'off' for a toggle provider" do
        match = described_class.call(lex("toggle sound off"), namespace: :slash)
        expect(match.values[:state]).to eq("off")
      end

      it "does not accidentally fill :state for a credential provider with an on/off-like word" do
        # 'on' is in on_off vocab; but for google the :state slot is ineligible
        match = described_class.call(lex("toggle google on"), namespace: :slash)
        expect(match.values[:state]).to be_nil
      end
    end

    describe "on/off synonyms resolve to canonical via eligible condition" do
      it "resolves 'enable' (synonym of 'on') for a sound-like provider" do
        match = described_class.call(lex("toggle sound enable"), namespace: :slash)
        expect(match.values[:state]).to eq("on")
      end

      it "resolves 'disable' (synonym of 'off') for a toggle provider" do
        match = described_class.call(lex("toggle sound disable"), namespace: :slash)
        expect(match.values[:state]).to eq("off")
      end
    end
  end

  # ── Config-like slash spec: sound→on/off, google→kv ──────────────────────

  describe "config-like spec with conditional slots" do
    before do
      Pito::Grammar::Registry.register_spec(
        Pito::Grammar::Spec.new(
          namespace: :slash,
          name: :config,
          slots: [
            Pito::Grammar::Slot.new(name: :provider, kind: :literal, source: :config_providers),
            Pito::Grammar::Slot.new(name: :state, kind: :enum, source: :on_off,
                                    optional: true,
                                    condition: { provider: %w[sound] }),
            Pito::Grammar::Slot.new(name: :setting, kind: :kv, source: :config_keys,
                                    optional: true, repeatable: true,
                                    condition: { provider: %w[google voyage igdb webhook] })
          ]
        )
      )
    end

    context "when provider is 'sound'" do
      subject(:match) { described_class.call(lex("config sound on"), namespace: :slash) }

      it "resolves provider to 'sound'" do
        expect(match.values[:provider]).to eq("sound")
      end

      it "resolves state to 'on' (condition met)" do
        expect(match.values[:state]).to eq("on")
      end

      it "has no unknowns" do
        expect(match.unknowns).to be_empty
      end
    end

    context "when provider is 'google' (credential provider)" do
      subject(:match) { described_class.call(lex("config google"), namespace: :slash) }

      it "resolves provider to 'google'" do
        expect(match.values[:provider]).to eq("google")
      end

      it "does not fill :state (ineligible for credential provider)" do
        expect(match.values[:state]).to be_nil
      end
    end

    context "when provider is 'sound' and value is 'off'" do
      subject(:match) { described_class.call(lex("config sound off"), namespace: :slash) }

      it "resolves state to 'off'" do
        expect(match.values[:state]).to eq("off")
      end
    end
  end

  describe "fuzzy enum correction" do
    # Uses the :list fixture spec (release_status: released/upcoming/tba)

    context "1-off typo on a release-status value ('upcomin' → 'upcoming')" do
      subject(:match) { described_class.call(lex("list upcomin"), namespace: :chat) }

      # "upcomin" (7 chars, threshold 2); dist("upcomin","upcoming") = 1 → match
      it "resolves :status to 'upcoming' via fuzzy fallback" do
        expect(match.values[:status]).to eq("upcoming")
      end

      it "records the correction in match.corrections" do
        expect(match.corrections).to eq({ "upcomin" => "upcoming" })
      end

      it "does not add 'upcomin' to unknowns" do
        expect(match.unknowns).not_to include("upcomin")
      end

      it "is still matched" do
        expect(match.matched?).to be(true)
      end
    end

    context "1-off typo on a release-status value ('releazed' → 'released')" do
      subject(:match) { described_class.call(lex("list releazed"), namespace: :chat) }

      # "releazed" (8 chars, threshold 2); dist("releazed","released") = 1
      it "resolves :status to 'released'" do
        expect(match.values[:status]).to eq("released")
      end

      it "records the correction" do
        expect(match.corrections["releazed"]).to eq("released")
      end
    end

    context "unresolvable word — no fuzzy match either" do
      subject(:match) { described_class.call(lex("list xyz"), namespace: :chat) }

      it "adds 'xyz' to unknowns (no correction fires)" do
        expect(match.unknowns).to include("xyz")
      end

      it "corrections is empty" do
        expect(match.corrections).to be_empty
      end
    end

    context "free slot is NOT affected by fuzzy resolution" do
      # :search spec has a :free slot — tokens go there unmodified.
      subject(:match) { described_class.call(lex("search gamr"), namespace: :chat) }

      it "preserves the query verbatim" do
        expect(match.values[:query]).to eq("gamr")
      end

      it "has no corrections" do
        expect(match.corrections).to be_empty
      end
    end

    context "match has no fuzzy correction when exact match is found" do
      subject(:match) { described_class.call(lex("list upcoming"), namespace: :chat) }

      it "resolves status via exact match" do
        expect(match.values[:status]).to eq("upcoming")
      end

      it "corrections is empty (exact match does not count as a correction)" do
        expect(match.corrections).to be_empty
      end
    end
  end
end
