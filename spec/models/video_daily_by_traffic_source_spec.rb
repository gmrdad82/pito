require "rails_helper"

RSpec.describe VideoDailyByTrafficSource, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:video) }
  end

  describe "validations" do
    it "is invalid without a traffic_source_type" do
      record = build(:video_daily_by_traffic_source, traffic_source_type: nil)
      expect(record).not_to be_valid
      expect(record.errors[:traffic_source_type]).to include("can't be blank")
    end

    it "is invalid with a duplicate (video_id, date, traffic_source_type)" do
      existing = create(:video_daily_by_traffic_source)
      duplicate = build(:video_daily_by_traffic_source,
                        video: existing.video,
                        date: existing.date,
                        traffic_source_type: existing.traffic_source_type)
      expect(duplicate).not_to be_valid
    end
  end

  describe "defaults" do
    it "defaults counters to 0 and ratios to NULL" do
      record = create(:video_daily_by_traffic_source)
      expect(record.views).to eq(0)
      expect(record.estimated_minutes_watched).to eq(0)
      expect(record.video_thumbnail_impressions).to eq(0)
      expect(record.video_thumbnail_impressions_click_rate).to be_nil
    end
  end

  describe "scopes" do
    describe ".for_traffic_source" do
      it "filters by traffic_source_type" do
        video = create(:video)
        search   = create(:video_daily_by_traffic_source, video: video,
                          traffic_source_type: "YT_SEARCH", date: 1.day.ago.to_date)
        external = create(:video_daily_by_traffic_source, video: video,
                          traffic_source_type: "EXT_URL", date: 2.days.ago.to_date)
        expect(described_class.for_traffic_source("YT_SEARCH")).to include(search)
        expect(described_class.for_traffic_source("YT_SEARCH")).not_to include(external)
      end
    end

    describe ".for_window" do
      it "filters by date range" do
        video = create(:video)
        inside = create(:video_daily_by_traffic_source, video: video,
                        traffic_source_type: "YT_SEARCH", date: 3.days.ago.to_date)
        outside = create(:video_daily_by_traffic_source, video: video,
                         traffic_source_type: "YT_SEARCH", date: 30.days.ago.to_date)
        result = described_class.for_window(7.days.ago.to_date, Date.current)
        expect(result).to include(inside)
        expect(result).not_to include(outside)
      end
    end
  end

  describe "ratio storage precision" do
    it "stores video_thumbnail_impressions_click_rate as a ratio with 6 decimals" do
      record = create(:video_daily_by_traffic_source,
                      video_thumbnail_impressions_click_rate: 0.085)
      record.reload
      # numeric(10, 6) -> 0.085 stored as 0.085000.
      expect(record.video_thumbnail_impressions_click_rate).to eq(BigDecimal("0.085000"))
    end
  end
end
