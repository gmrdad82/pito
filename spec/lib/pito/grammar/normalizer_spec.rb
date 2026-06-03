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

    # :hashtag namespace fixture specs
    Pito::Grammar::Registry.register_spec(
      Pito::Grammar::Spec.new(
        namespace: :hashtag,
        name: :add,
        aliases: [ :include ],
        slots: [ Pito::Grammar::Slot.new(name: :metric, kind: :enum, source: :metrics, repeatable: true) ]
      )
    )
    Pito::Grammar::Registry.register_spec(
      Pito::Grammar::Spec.new(
        namespace: :hashtag,
        name: :remove,
        aliases: [ :drop, :delete ],
        slots: [ Pito::Grammar::Slot.new(name: :metric, kind: :enum, source: :metrics, repeatable: true) ]
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

    describe "alias resolution (include → :add)" do
      subject(:match) do
        described_class.call(lex("include subs"), namespace: :hashtag)
      end

      it "resolves alias to canonical verb name" do
        expect(match.name).to eq(:add)
      end

      it "resolves metric via synonym" do
        expect(match.values[:metric]).to eq([ "subscribers" ])
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

  # ── Task j: connectives and call_ops ──────────────────────────────────────

  describe ".call_ops" do
    describe "compound hashtag: add ctr and views and remove subs" do
      subject(:ops) do
        described_class.call_ops(
          lex("add ctr and views and remove subs"),
          namespace: :hashtag
        )
      end

      it "returns two matches" do
        expect(ops.length).to eq(2)
      end

      it "first op has name :add" do
        expect(ops[0].name).to eq(:add)
      end

      it "first op collects ctr and views" do
        expect(ops[0].values[:metric]).to eq([ "ctr", "views" ])
      end

      it "second op has name :remove" do
        expect(ops[1].name).to eq(:remove)
      end

      it "second op collects subs → subscribers" do
        expect(ops[1].values[:metric]).to eq([ "subscribers" ])
      end

      it "both ops are matched" do
        expect(ops.all?(&:matched?)).to be(true)
      end
    end

    describe "single op returns a 1-element array" do
      subject(:ops) { described_class.call_ops(lex("add views"), namespace: :hashtag) }

      it "returns one match" do
        expect(ops.length).to eq(1)
      end

      it "resolves correctly" do
        expect(ops[0].name).to eq(:add)
        expect(ops[0].values[:metric]).to eq([ "views" ])
      end
    end

    describe "alias splitting (drop is an alias of remove)" do
      subject(:ops) do
        described_class.call_ops(
          lex("add views drop subs"),
          namespace: :hashtag
        )
      end

      it "splits into two ops" do
        expect(ops.length).to eq(2)
      end

      it "first op is :add with views" do
        expect(ops[0].name).to eq(:add)
        expect(ops[0].values[:metric]).to eq([ "views" ])
      end

      it "second op is :remove with subscribers" do
        expect(ops[1].name).to eq(:remove)
        expect(ops[1].values[:metric]).to eq([ "subscribers" ])
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
end
