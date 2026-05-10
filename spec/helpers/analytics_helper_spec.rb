require "rails_helper"

RSpec.describe AnalyticsHelper, type: :helper do
  describe "#format_metric" do
    it "renders integers with delimiters for counts" do
      expect(helper.format_metric(1234567, type: :count)).to eq("1,234,567")
    end

    it "renders durations as m:ss" do
      expect(helper.format_metric(125, type: :duration_seconds)).to eq("2:05")
    end

    it "renders ratios as percentages with two decimals" do
      expect(helper.format_metric(0.4567, type: :ratio)).to eq("45.67%")
    end

    it "renders money as $x.xx" do
      expect(helper.format_metric(12.5, type: :money)).to eq("$12.50")
    end

    it "renders nil values as an em-dash placeholder" do
      expect(helper.format_metric(nil, type: :count)).to eq("—")
    end
  end

  describe "#analytics_window_label" do
    it "maps each enum value to a short label by default" do
      expect(helper.analytics_window_label("7d")).to eq("7d")
      expect(helper.analytics_window_label("28d")).to eq("28d")
      expect(helper.analytics_window_label("90d")).to eq("90d")
      expect(helper.analytics_window_label("lifetime")).to eq("lifetime")
    end

    it "maps each enum value to a long label when long: true" do
      expect(helper.analytics_window_label("7d", long: true)).to eq("last 7 days")
      expect(helper.analytics_window_label("28d", long: true)).to eq("last 28 days")
      expect(helper.analytics_window_label("90d", long: true)).to eq("last 90 days")
      expect(helper.analytics_window_label("lifetime", long: true)).to eq("lifetime")
    end
  end

  describe "#data_freshness_label" do
    it "renders 'never synced' when no rows exist" do
      expect(helper.data_freshness_label(nil)).to eq("never synced")
    end

    it "renders the timestamp as a human relative phrase" do
      label = helper.data_freshness_label(2.minutes.ago)
      expect(label).to start_with("synced ")
      expect(label).to end_with(" ago")
    end
  end
end
