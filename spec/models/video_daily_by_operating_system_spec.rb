require "rails_helper"

RSpec.describe VideoDailyByOperatingSystem, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:video) }
  end

  describe "validations" do
    it "is invalid without an operating_system" do
      record = build(:video_daily_by_operating_system, operating_system: nil)
      expect(record).not_to be_valid
      expect(record.errors[:operating_system]).to include("can't be blank")
    end

    it "is invalid with a duplicate (video_id, date, operating_system)" do
      existing = create(:video_daily_by_operating_system)
      duplicate = build(:video_daily_by_operating_system,
                        video: existing.video,
                        date: existing.date,
                        operating_system: existing.operating_system)
      expect(duplicate).not_to be_valid
    end
  end

  describe "defaults" do
    it "defaults counters to 0 and ratios to NULL" do
      record = create(:video_daily_by_operating_system)
      expect(record.views).to eq(0)
      expect(record.estimated_minutes_watched).to eq(0)
      expect(record.average_view_duration).to be_nil
      expect(record.average_view_percentage).to be_nil
    end
  end

  describe "scopes" do
    describe ".for_operating_system" do
      it "filters by operating_system" do
        video = create(:video)
        ios  = create(:video_daily_by_operating_system, video: video, operating_system: "IOS", date: 1.day.ago.to_date)
        andr = create(:video_daily_by_operating_system, video: video, operating_system: "ANDROID", date: 2.days.ago.to_date)
        expect(described_class.for_operating_system("IOS")).to include(ios)
        expect(described_class.for_operating_system("IOS")).not_to include(andr)
      end
    end

    describe ".for_window" do
      it "filters by date range" do
        video = create(:video)
        inside  = create(:video_daily_by_operating_system, video: video, operating_system: "IOS", date: 3.days.ago.to_date)
        outside = create(:video_daily_by_operating_system, video: video, operating_system: "IOS", date: 30.days.ago.to_date)
        result = described_class.for_window(7.days.ago.to_date, Date.current)
        expect(result).to include(inside)
        expect(result).not_to include(outside)
      end
    end
  end
end
