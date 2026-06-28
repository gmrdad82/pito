# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Thresholds do
  describe ".views_target_daily (per-week pace, M=1)" do
    it "is subscribers / 7" do
      expect(described_class.views_target_daily(subs: 7)).to eq(1.0)
      expect(described_class.views_target_daily(subs: 700)).to eq(100.0)
    end

    it "matches the owner's anchor example (10 subs → ~1.43/day → 10 views/7d = green)" do
      expect(described_class.views_target_daily(subs: 10)).to be_within(0.001).of(10 / 7.0)
    end

    it "is zero for zero/negative subscribers" do
      expect(described_class.views_target_daily(subs: 0)).to eq(0.0)
      expect(described_class.views_target_daily(subs: -5)).to eq(0.0)
    end
  end

  describe ".green_anchor_fraction" do
    it "is target/ceiling within 0..1" do
      expect(described_class.green_anchor_fraction(target: 2, ceiling: 10)).to eq(0.2)
    end

    it "clamps to 1.0 when target ≥ ceiling (underperforming → green only at the top)" do
      expect(described_class.green_anchor_fraction(target: 50, ceiling: 10)).to eq(1.0)
    end

    it "is 1.0 for a non-positive ceiling" do
      expect(described_class.green_anchor_fraction(target: 5, ceiling: 0)).to eq(1.0)
    end
  end

  describe ".subs_for (subscriber basis per level)" do
    let(:ch_a) { create(:channel) }
    let(:ch_b) { create(:channel) }

    before do
      subs = { ch_a.id => 100, ch_b.id => 50 }
      allow(Pito::Stats).to receive(:get) do |entity, key|
        key == :subscribers ? subs[entity.id] : nil
      end
    end

    it "channel level → Σ the channels' subs" do
      expect(described_class.subs_for(level: :channel, entity_ids: [ ch_a.id, ch_b.id ])).to eq(150)
    end

    it "vid level → the vid's channel subs" do
      v = create(:video, channel: ch_a)
      expect(described_class.subs_for(level: :vid, entity_ids: [ v.id ])).to eq(100)
    end

    it "game level → Σ DISTINCT channels owning the linked vids" do
      game = create(:game)
      v1   = create(:video, channel: ch_a)
      v2   = create(:video, channel: ch_b)
      v3   = create(:video, channel: ch_a) # same channel as v1 → counted once
      [ v1, v2, v3 ].each { |v| VideoGameLink.create!(video: v, game: game) }

      expect(described_class.subs_for(level: :game, entity_ids: [ game.id ])).to eq(150)
    end

    it "is 0 for an unknown level" do
      expect(described_class.subs_for(level: :nope, entity_ids: [ 1 ])).to eq(0)
    end
  end
end
