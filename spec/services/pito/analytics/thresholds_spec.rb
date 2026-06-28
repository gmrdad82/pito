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

  describe ".subs_target_daily (1%/week net-growth pace)" do
    it "is subs × SUBS_WEEKLY_GROWTH / 7" do
      expect(described_class.subs_target_daily(subs: 700)).to be_within(0.001).of(700 * 0.01 / 7.0)
    end

    it "is zero for zero/negative subscribers" do
      expect(described_class.subs_target_daily(subs: 0)).to eq(0.0)
      expect(described_class.subs_target_daily(subs: -10)).to eq(0.0)
    end

    it "uses the SUBS_WEEKLY_GROWTH constant" do
      expect(described_class::SUBS_WEEKLY_GROWTH).to eq(0.01)
    end
  end

  describe ".watched_hours_target_daily (views_target × avg view duration)" do
    it "is views_target_daily × DEFAULT_AVG_VIEW_HOURS" do
      vt = described_class.views_target_daily(subs: 700)
      expect(described_class.watched_hours_target_daily(views_target_daily: vt))
        .to be_within(0.001).of(vt * described_class::DEFAULT_AVG_VIEW_HOURS)
    end

    it "is zero when views_target_daily is zero" do
      expect(described_class.watched_hours_target_daily(views_target_daily: 0.0)).to eq(0.0)
    end

    it "uses the DEFAULT_AVG_VIEW_HOURS constant" do
      expect(described_class::DEFAULT_AVG_VIEW_HOURS).to eq(0.05)
    end
  end

  describe ".target_daily (per-metric dispatcher)" do
    it "dispatches :views to views_target_daily" do
      expect(described_class.target_daily(metric: :views, subs: 700))
        .to eq(described_class.views_target_daily(subs: 700))
    end

    it "dispatches :subs to subs_target_daily" do
      expect(described_class.target_daily(metric: :subs, subs: 700))
        .to eq(described_class.subs_target_daily(subs: 700))
    end

    it "dispatches :watched_hours to watched_hours_target_daily using views_target" do
      vt = described_class.views_target_daily(subs: 700)
      expect(described_class.target_daily(metric: :watched_hours, subs: 700, views_target_daily: vt))
        .to eq(described_class.watched_hours_target_daily(views_target_daily: vt))
    end

    it "computes views_target internally when views_target_daily: is not supplied for :watched_hours" do
      result = described_class.target_daily(metric: :watched_hours, subs: 700)
      expected = described_class.watched_hours_target_daily(
        views_target_daily: described_class.views_target_daily(subs: 700)
      )
      expect(result).to be_within(0.001).of(expected)
    end

    it "returns 0.0 for an unknown metric" do
      expect(described_class.target_daily(metric: :unknown, subs: 100)).to eq(0.0)
    end

    it "dispatches :avg_view_duration to the constant AVG_VIEW_DURATION_TARGET_SECONDS" do
      expect(described_class.target_daily(metric: :avg_view_duration, subs: 100))
        .to eq(described_class::AVG_VIEW_DURATION_TARGET_SECONDS.to_f)
    end

    it "dispatches :avg_viewed_pct to the constant RETENTION_TARGET_PCT" do
      expect(described_class.target_daily(metric: :avg_viewed_pct, subs: 100))
        .to eq(described_class::RETENTION_TARGET_PCT.to_f)
    end

    it "AVG_VIEW_DURATION_TARGET_SECONDS is 120 (2-minute goal)" do
      expect(described_class::AVG_VIEW_DURATION_TARGET_SECONDS).to eq(120)
    end

    it "RETENTION_TARGET_PCT is 50 (50% retention goal)" do
      expect(described_class::RETENTION_TARGET_PCT).to eq(50)
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
