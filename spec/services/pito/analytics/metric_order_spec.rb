# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::MetricOrder do
  describe ".for" do
    it "returns the :system order for a vid (area charts first, then heart; comments moved to :enhanced)" do
      expect(described_class.for(role: :system, level: :vid)).to eq(
        %i[views watched_hours subs avg_view_duration avg_viewed_pct likes]
      )
    end

    it "returns the :enhanced order for a vid (heatmap first, bars, retention, comments last)" do
      expect(described_class.for(role: :enhanced, level: :vid)).to eq(
        %i[day_of_week_heatmap subscribed_status devices geography demographics_age demographics_gender retention comments]
      )
    end

    it "includes retention for a game (channel/game aggregate the vids' curves)" do
      expect(described_class.for(role: :enhanced, level: :game)).to eq(
        %i[day_of_week_heatmap subscribed_status devices geography demographics_age demographics_gender retention comments]
      )
    end

    it "includes retention for a channel" do
      expect(described_class.for(role: :enhanced, level: :channel)).to include(:retention)
    end

    it "keeps :system identical across levels, with subscribed_status moved to :enhanced" do
      %i[vid game channel].each do |level|
        expect(described_class.for(role: :system, level:)).not_to include(:subscribed_status)
        expect(described_class.for(role: :enhanced, level:)).to include(:subscribed_status)
      end
      expect(described_class.for(role: :system, level: :game)).to eq(described_class.for(role: :system, level: :channel))
    end
  end

  describe ".available?" do
    it "is available at every level for retention (channel/game aggregate the vids)" do
      expect(described_class.available?(:retention, :vid)).to be(true)
      expect(described_class.available?(:retention, :game)).to be(true)
      expect(described_class.available?(:retention, :channel)).to be(true)
    end

    it "is available everywhere for non-restricted metrics" do
      %i[views subscribed_status devices geography].each do |m|
        %i[vid game channel].each { |lvl| expect(described_class.available?(m, lvl)).to be(true) }
      end
    end
  end

  describe ".report / .label_key / .reports" do
    it "maps each metric to its backing report group" do
      expect(described_class.report(:views)).to eq("scalars")
      expect(described_class.report(:devices)).to eq("device")
      expect(described_class.report(:geography)).to eq("country")
      expect(described_class.report(:day_of_week_heatmap)).to eq("daily")
      expect(described_class.report(:demographics_gender)).to eq("demographics")
    end

    it "resolves each metric's label copy key" do
      expect(described_class.label_key(:subs)).to eq("pito.copy.analytics.metrics.subs_net")
      expect(described_class.label_key(:watched_hours)).to eq("pito.copy.analytics.metrics.watch_hours")
      # every label key resolves to real copy
      Pito::Analytics::MetricOrder::METRICS.each_key do |metric|
        expect { Pito::Copy.render(described_class.label_key(metric)) }.not_to raise_error
      end
    end

    it "returns the distinct report groups for a role+level" do
      # :system is now all scalars (subscribed_status moved to :enhanced)
      expect(described_class.reports(role: :system, level: :vid)).to match_array(%w[scalars])
      # :enhanced vid → subscribed_status + device + country + demographics + retention + daily
      expect(described_class.reports(role: :enhanced, level: :vid)).to match_array(
        %w[subscribed_status device country demographics retention daily]
      )
      # :enhanced game → now includes retention (channel/game aggregate the vids)
      expect(described_class.reports(role: :enhanced, level: :game)).to include("retention")
    end
  end
end
