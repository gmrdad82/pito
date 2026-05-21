require "rails_helper"

# ADR 0018 — Action bus + cable architecture.
#
# Contract spec: every action registered in `Pito::ActionRegistry` must
# satisfy the brand-capitalization rule + the cable-panel grammar
# enforced by the ADR. Adding a new action that violates either fails
# this spec — single seam covers every consumer (web, palette, leader,
# MCP, CLI) at once.
RSpec.describe Pito::ActionRegistry do
  describe ".[]" do
    it "returns the registered action by name" do
      action = described_class[:reindex_meilisearch]
      expect(action.name).to eq(:reindex_meilisearch)
      expect(action.method).to eq(:post)
      expect(action.cable_panel).to eq("pito:settings:stack:meilisearch")
    end

    it "returns the registered :reindex_voyage entry" do
      action = described_class[:reindex_voyage]
      expect(action.name).to eq(:reindex_voyage)
      expect(action.method).to eq(:post)
      expect(action.cable_panel).to eq("pito:settings:stack:voyage")
    end

    it "raises KeyError for unknown names" do
      expect { described_class[:nonexistent_action] }.to raise_error(KeyError)
    end
  end

  describe ".all" do
    it "returns an array of Pito::Action records" do
      expect(described_class.all).to all(be_a(Pito::Action))
    end

    it "includes both reindex actions" do
      names = described_class.all.map(&:name)
      expect(names).to include(:reindex_meilisearch, :reindex_voyage)
    end
  end

  describe "registered actions — contract" do
    it "all reindex actions carry a brand-capitalized confirmation" do
      reindex_actions = described_class.all.select { |a| a.name.to_s.start_with?("reindex_") }

      expect(reindex_actions).not_to be_empty

      reindex_actions.each do |action|
        expect(action.confirmation).to be_a(Hash), "#{action.name} missing confirmation hash"
        expect(action.confirmation[:brand]).to match(/Meilisearch|Voyage AI/), "#{action.name} brand drift: #{action.confirmation[:brand].inspect}"
        expect(action.confirmation[:danger]).to be(true), "#{action.name} must be danger:true"
      end
    end

    it "every cable_panel matches the pito:<screen>:<panel>[:<sub-panel>] grammar" do
      panels = described_class.all.map(&:cable_panel).compact
      panels.each do |channel|
        expect(channel).to match(/\Apito:[a-z_]+(:[a-z_]+)+\z/), "channel #{channel.inspect} violates ADR 0017 grammar"
      end
    end

    it "every i18n key resolves to a non-empty name + hint" do
      described_class.all.each do |action|
        name = I18n.t("#{action.i18n_key}.name")
        hint = I18n.t("#{action.i18n_key}.hint")
        expect(name).to be_a(String).and(be_present), "#{action.name} i18n .name missing"
        expect(hint).to be_a(String).and(be_present), "#{action.name} i18n .hint missing"
      end
    end
  end

  describe "Pito::Action#to_h" do
    it "serializes the JS-readable subset" do
      action = described_class[:reindex_meilisearch]
      h = action.to_h
      expect(h[:name]).to eq("reindex_meilisearch")
      expect(h[:method]).to eq("post")
      expect(h[:cable_panel]).to eq("pito:settings:stack:meilisearch")
      expect(h[:confirmation]).to include(brand: "Meilisearch", danger: true)
      expect(h[:i18n_name]).to be_present
      expect(h[:i18n_hint]).to be_present
    end

    it "lazily resolves the route path" do
      action = described_class[:reindex_meilisearch]
      expect(action.path).to eq("/settings/stack/meilisearch/reindex")
    end
  end
end
