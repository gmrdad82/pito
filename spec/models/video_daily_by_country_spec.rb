require "rails_helper"

RSpec.describe VideoDailyByCountry, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:video) }
  end

  describe "validations" do
    it "is invalid without a country_code" do
      record = build(:video_daily_by_country, country_code: nil)
      expect(record).not_to be_valid
      expect(record.errors[:country_code]).to include("can't be blank")
    end

    it "is invalid with a duplicate (video_id, date, country_code)" do
      existing = create(:video_daily_by_country)
      duplicate = build(:video_daily_by_country,
                        video: existing.video,
                        date: existing.date,
                        country_code: existing.country_code)
      expect(duplicate).not_to be_valid
    end
  end

  describe "defaults" do
    it "defaults counters to 0 and ratios to NULL" do
      record = create(:video_daily_by_country)
      expect(record.views).to eq(0)
      expect(record.estimated_minutes_watched).to eq(0)
      expect(record.average_view_duration).to be_nil
      expect(record.average_view_percentage).to be_nil
    end
  end

  describe "scopes" do
    describe ".for_country" do
      it "filters by country_code" do
        video = create(:video)
        us = create(:video_daily_by_country, video: video, country_code: "US", date: 1.day.ago.to_date)
        gb = create(:video_daily_by_country, video: video, country_code: "GB", date: 2.days.ago.to_date)
        expect(described_class.for_country("US")).to include(us)
        expect(described_class.for_country("US")).not_to include(gb)
      end
    end

    describe ".for_window" do
      it "filters by date range" do
        video = create(:video)
        inside  = create(:video_daily_by_country, video: video, country_code: "US", date: 3.days.ago.to_date)
        outside = create(:video_daily_by_country, video: video, country_code: "US", date: 30.days.ago.to_date)
        result = described_class.for_window(7.days.ago.to_date, Date.current)
        expect(result).to include(inside)
        expect(result).not_to include(outside)
      end
    end
  end
end
