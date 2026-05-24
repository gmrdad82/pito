# frozen_string_literal: true

require "rails_helper"

# Pito::SyncTargets — registry + cascade map for the server-side sync
# state (2026-05-25 sync-rebuild). Replaces the localStorage cascade
# every sync VC used to maintain client-side.
RSpec.describe Pito::SyncTargets do
  describe "PANELS_BY_SCREEN" do
    it "lists every home panel that renders a sync VC" do
      expect(described_class::PANELS_BY_SCREEN["home"]).to include(
        "channels", "latest_videos", "upcoming_games",
        "notifications_feed", "calendar",
        "stack", "notifications", "security"
      )
    end

    it "freezes the constant" do
      expect(described_class::PANELS_BY_SCREEN).to be_frozen
    end
  end

  describe "PARENTS_TO_CHILDREN" do
    it "registers the four home.stack sub-panels under home.stack" do
      expect(described_class::PARENTS_TO_CHILDREN["home.stack"]).to eq(%w[
        home.stack.meilisearch
        home.stack.voyage
        home.stack.postgres
        home.stack.assets
      ])
    end

    it "freezes the constant" do
      expect(described_class::PARENTS_TO_CHILDREN).to be_frozen
    end
  end

  describe ".panel_targets" do
    it "flattens PANELS_BY_SCREEN into <screen>.<panel> strings" do
      expect(described_class.panel_targets).to include(
        "home.channels", "home.stack", "home.security"
      )
    end

    it "does not include the app master or any sub-panel" do
      expect(described_class.panel_targets).not_to include("app")
      expect(described_class.panel_targets).not_to include("home.stack.meilisearch")
    end
  end

  describe ".sub_panel_targets" do
    it "returns every sub-panel target" do
      expect(described_class.sub_panel_targets).to match_array(%w[
        home.stack.meilisearch
        home.stack.voyage
        home.stack.postgres
        home.stack.assets
      ])
    end
  end

  describe ".all" do
    it "returns every panel + sub-panel target (no master)" do
      expect(described_class.all).to include("home.stack", "home.stack.voyage")
      expect(described_class.all).not_to include("app")
    end
  end

  describe ".cascade_targets" do
    it "fans 'app' out to itself + every known target" do
      cascade = described_class.cascade_targets("app")
      expect(cascade.first).to eq("app")
      expect(cascade).to include("home.security")
      expect(cascade).to include("home.stack")
      expect(cascade).to include("home.stack.meilisearch")
      expect(cascade.length).to eq(1 + described_class.all.length)
    end

    it "fans a parent panel out to itself + its registered children" do
      expect(described_class.cascade_targets("home.stack")).to eq(%w[
        home.stack
        home.stack.meilisearch
        home.stack.voyage
        home.stack.postgres
        home.stack.assets
      ])
    end

    it "returns just the target for a sub-panel (no upward propagation)" do
      expect(described_class.cascade_targets("home.stack.voyage")).to eq(%w[home.stack.voyage])
    end

    it "returns just the target for a panel with no children" do
      expect(described_class.cascade_targets("home.security")).to eq(%w[home.security])
    end

    it "accepts a symbol target" do
      expect(described_class.cascade_targets(:"home.stack").first).to eq("home.stack")
    end

    it "returns just the input for an unknown target (no crash)" do
      expect(described_class.cascade_targets("bogus.thing")).to eq(%w[bogus.thing])
    end
  end

  describe ".valid?" do
    it "accepts the master 'app' target" do
      expect(described_class.valid?("app")).to be(true)
    end

    it "accepts a panel target" do
      expect(described_class.valid?("home.stack")).to be(true)
    end

    it "accepts a sub-panel target" do
      expect(described_class.valid?("home.stack.voyage")).to be(true)
    end

    it "rejects unknown targets" do
      expect(described_class.valid?("bogus")).to be(false)
      expect(described_class.valid?("home.bogus")).to be(false)
      expect(described_class.valid?("")).to be(false)
    end
  end

  describe ".suppression_chain" do
    it "returns the panel + master for a leaf panel" do
      expect(described_class.suppression_chain("home.security")).to eq(%w[home.security app])
    end

    it "returns sub-panel + parent + master for a sub-panel" do
      expect(described_class.suppression_chain("home.stack.voyage")).to eq(%w[
        home.stack.voyage home.stack app
      ])
    end

    it "returns just the master itself when target is 'app'" do
      expect(described_class.suppression_chain("app")).to eq(%w[app])
    end

    it "returns nil for an unknown target" do
      expect(described_class.suppression_chain("bogus")).to be_nil
    end
  end
end
