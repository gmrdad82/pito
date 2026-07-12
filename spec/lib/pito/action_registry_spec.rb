# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::ActionRegistry do
  # Isolate every test with a fresh registry snapshot so real app actions
  # are never mutated across examples.
  around do |example|
    saved = described_class.instance_variable_get(:@registry).dup
    described_class.reset!
    example.run
    described_class.instance_variable_set(:@registry, saved)
  end

  # Helper to define a minimal action in the isolated registry.
  def define_action(name, scope: :global, confirmation: nil)
    described_class.define(
      name,
      path:     -> { "/#{name}" },
      method:   :post,
      i18n_key: "pito.actions.#{name}",
      scope:    scope,
      confirmation: confirmation
    )
  end

  # ── Registration ────────────────────────────────────────────────────────────

  describe ".define" do
    it "registers an action and returns a Pito::Action" do
      define_action(:reindex)
      action = described_class[:reindex]
      expect(action).to be_a(Pito::Action)
      expect(action.name).to eq(:reindex)
    end

    it "coerces a string name to a symbol" do
      described_class.define("stringname", path: -> { "/s" }, i18n_key: "x.y")
      expect { described_class[:stringname] }.not_to raise_error
    end

    it "defaults scope to :global" do
      define_action(:global_action)
      expect(described_class[:global_action].scope).to eq(:global)
    end

    it "raises ArgumentError for an unknown scope" do
      expect {
        described_class.define(:bad, path: -> { "/" }, i18n_key: "x", scope: :invalid)
      }.to raise_error(ArgumentError, /unknown scope/)
    end

    it "allows valid scopes: :home, :videos, :games" do
      %i[home videos games].each do |s|
        define_action(:"action_#{s}", scope: s)
        expect(described_class[:"action_#{s}"].scope).to eq(s)
      end
    end

    it "overwrites a previously registered action with the same name" do
      define_action(:overwrite, scope: :home)
      define_action(:overwrite, scope: :videos)
      expect(described_class[:overwrite].scope).to eq(:videos)
    end
  end

  # ── Lookup ──────────────────────────────────────────────────────────────────

  describe ".[]" do
    it "returns the action for a known key" do
      define_action(:lookup_test)
      expect(described_class[:lookup_test]).to be_a(Pito::Action)
    end

    it "raises KeyError for an unknown key" do
      expect { described_class[:does_not_exist] }.to raise_error(KeyError)
    end

    it "coerces string key to symbol" do
      define_action(:sym_key)
      expect { described_class["sym_key"] }.not_to raise_error
    end
  end

  # ── .all ────────────────────────────────────────────────────────────────────

  describe ".all" do
    it "returns all registered actions" do
      define_action(:alpha)
      define_action(:beta)
      names = described_class.all.map(&:name)
      expect(names).to include(:alpha, :beta)
    end

    it "returns an empty array when no actions are registered" do
      expect(described_class.all).to eq([])
    end
  end

  # ── .for_screen ─────────────────────────────────────────────────────────────

  describe ".for_screen" do
    before do
      define_action(:nav,    scope: :global)
      define_action(:dash,   scope: :home)
      define_action(:vids,   scope: :videos)
      define_action(:games_act, scope: :games)
    end

    it "returns :global actions for any screen" do
      expect(described_class.for_screen(:home).map(&:name)).to include(:nav)
      expect(described_class.for_screen(:videos).map(&:name)).to include(:nav)
    end

    it "returns screen-specific actions together with globals" do
      home_names = described_class.for_screen(:home).map(&:name)
      expect(home_names).to include(:nav, :dash)
      expect(home_names).not_to include(:vids, :games_act)
    end

    it "does not include other-screen-scoped actions" do
      video_names = described_class.for_screen(:videos).map(&:name)
      expect(video_names).not_to include(:dash, :games_act)
    end

    it "accepts a string screen argument" do
      expect(described_class.for_screen("home").map(&:name)).to include(:dash)
    end
  end

  # ── .reset! ─────────────────────────────────────────────────────────────────

  describe ".reset!" do
    it "clears all registered actions" do
      define_action(:tmp)
      described_class.reset!
      expect(described_class.all).to be_empty
    end
  end

  # ── Action value object ──────────────────────────────────────────────────────

  describe "Pito::Action path resolution" do
    it "calls the path_proc lazily" do
      called = 0
      described_class.define(:lazy, path: -> { called += 1; "/lazy" }, i18n_key: "x.y")
      expect(called).to eq(0)
      described_class[:lazy].path
      expect(called).to eq(1)
    end

    it "stores confirmation hash when provided" do
      define_action(:destructive, confirmation: { title: "Confirm?", danger: true })
      expect(described_class[:destructive].confirmation).to eq({ title: "Confirm?", danger: true })
    end

    it "stores nil confirmation when not provided" do
      define_action(:safe)
      expect(described_class[:safe].confirmation).to be_nil
    end
  end
end
