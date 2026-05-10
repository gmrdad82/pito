require "rails_helper"

RSpec.describe Analytics::VideoDecorator do
  let(:video) { create(:video) }
  let(:decorator) { described_class.new(video) }

  describe "#window_summary" do
    it "returns the matching VideoWindowSummary" do
      summary = create(:video_window_summary, video: video, window: "28d")
      expect(decorator.window_summary("28d")).to eq(summary)
    end
  end

  describe "#daily_for_window" do
    it "returns VideoDaily rows in the window's date range" do
      mid_row = create(:video_daily, video: video, date: 5.days.ago.to_date)
      _old_row = create(:video_daily, video: video, date: 60.days.ago.to_date)
      result = decorator.daily_for_window(7.days.ago.to_date, Date.current).to_a
      expect(result).to eq([ mid_row ])
    end
  end

  describe "#retention" do
    it "returns VideoRetention rows ordered by elapsed_ratio_bucket" do
      late = create(:video_retention, video: video, elapsed_ratio_bucket: 0.9)
      early = create(:video_retention, video: video, elapsed_ratio_bucket: 0.1)
      expect(decorator.retention.to_a).to eq([ early, late ])
    end
  end

  describe "#country_breakdown_for_window" do
    it "returns SUM-aggregated views per country" do
      create(:video_daily_by_country, video: video, country_code: "US", date: 1.day.ago.to_date, views: 100)
      create(:video_daily_by_country, video: video, country_code: "GB", date: 1.day.ago.to_date, views: 30)
      result = decorator.country_breakdown_for_window(7.days.ago.to_date, Date.current)
      expect(result["US"]).to eq(100)
      expect(result["GB"]).to eq(30)
    end
  end

  describe "#device_breakdown_for_window" do
    it "returns SUM-aggregated views per device type" do
      create(:video_daily_by_device_type, video: video, device_type: "MOBILE", date: 1.day.ago.to_date, views: 80)
      create(:video_daily_by_device_type, video: video, device_type: "DESKTOP", date: 1.day.ago.to_date, views: 30)
      result = decorator.device_breakdown_for_window(7.days.ago.to_date, Date.current)
      expect(result["MOBILE"]).to eq(80)
      expect(result["DESKTOP"]).to eq(30)
    end
  end

  describe "#os_breakdown_for_window" do
    it "returns SUM-aggregated views per operating system" do
      create(:video_daily_by_operating_system, video: video, operating_system: "ANDROID", date: 1.day.ago.to_date, views: 50)
      result = decorator.os_breakdown_for_window(7.days.ago.to_date, Date.current)
      expect(result["ANDROID"]).to eq(50)
    end
  end

  describe "#traffic_source_breakdown_for_window" do
    it "returns SUM-aggregated views per traffic source" do
      create(:video_daily_by_traffic_source, video: video, traffic_source_type: "YT_SEARCH", date: 1.day.ago.to_date, views: 90)
      result = decorator.traffic_source_breakdown_for_window(7.days.ago.to_date, Date.current)
      expect(result["YT_SEARCH"]).to eq(90)
    end
  end

  describe "#subscribed_status_breakdown_for_window" do
    it "returns SUM-aggregated views per subscribed status" do
      create(:video_daily_by_subscribed_status, video: video, subscribed_status: "SUBSCRIBED", date: 1.day.ago.to_date, views: 70)
      result = decorator.subscribed_status_breakdown_for_window(7.days.ago.to_date, Date.current)
      expect(result["SUBSCRIBED"]).to eq(70)
    end
  end

  describe "#demographics_for_window" do
    it "returns SUM-aggregated viewer_percentage per (age_group, gender)" do
      create(:video_daily_by_age_group_gender,
             video: video, age_group: "AGE_18_24", gender: "FEMALE",
             date: 1.day.ago.to_date, viewer_percentage: 0.5)
      result = decorator.demographics_for_window(7.days.ago.to_date, Date.current)
      expect(result[[ "AGE_18_24", "FEMALE" ]]).to eq(0.5)
    end
  end
end
