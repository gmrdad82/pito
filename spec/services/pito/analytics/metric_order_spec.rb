# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::MetricOrder do
  describe ".for" do
    it "returns the :system order for a vid (all available); area-chart metrics grouped first" do
      expect(described_class.for(role: :system, level: :vid)).to eq(
        %i[views watched_hours subs avg_view_duration avg_viewed_pct likes comments subscribed_status]
      )
    end

    it "returns the :enhanced order for a vid (retention available)" do
      expect(described_class.for(role: :enhanced, level: :vid)).to eq(
        %i[retention devices geography day_of_week_heatmap demographics_gender demographics_age]
      )
    end

    it "skips retention (vid-only) for a game" do
      expect(described_class.for(role: :enhanced, level: :game)).not_to include(:retention)
      expect(described_class.for(role: :enhanced, level: :game)).to eq(
        %i[devices geography day_of_week_heatmap demographics_gender demographics_age]
      )
    end

    it "skips retention (vid-only) for a channel" do
      expect(described_class.for(role: :enhanced, level: :channel)).not_to include(:retention)
    end

    it "keeps :system identical across levels (no vid-only metrics in it)" do
      %i[vid game channel].each do |level|
        expect(described_class.for(role: :system, level:)).to include(:subscribed_status)
      end
    end
  end

  describe ".available?" do
    it "is vid-only for retention" do
      expect(described_class.available?(:retention, :vid)).to be(true)
      expect(described_class.available?(:retention, :game)).to be(false)
      expect(described_class.available?(:retention, :channel)).to be(false)
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
      # :system is all scalars + subscribed_status → two report groups
      expect(described_class.reports(role: :system, level: :vid)).to match_array(%w[scalars subscribed_status])
      # :enhanced vid → retention + device + country + daily + demographics
      expect(described_class.reports(role: :enhanced, level: :vid)).to match_array(
        %w[retention device country daily demographics]
      )
      # :enhanced game → no retention
      expect(described_class.reports(role: :enhanced, level: :game)).not_to include("retention")
    end
  end
end
