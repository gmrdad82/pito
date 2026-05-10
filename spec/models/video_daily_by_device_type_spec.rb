require "rails_helper"

RSpec.describe VideoDailyByDeviceType, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:video) }
  end

  describe "validations" do
    it "is invalid without a device_type" do
      record = build(:video_daily_by_device_type, device_type: nil)
      expect(record).not_to be_valid
      expect(record.errors[:device_type]).to include("can't be blank")
    end

    it "is invalid with a duplicate (video_id, date, device_type)" do
      existing = create(:video_daily_by_device_type)
      duplicate = build(:video_daily_by_device_type,
                        video: existing.video,
                        date: existing.date,
                        device_type: existing.device_type)
      expect(duplicate).not_to be_valid
    end
  end

  describe "defaults" do
    it "defaults counters to 0 and ratios to NULL" do
      record = create(:video_daily_by_device_type)
      expect(record.views).to eq(0)
      expect(record.estimated_minutes_watched).to eq(0)
      expect(record.average_view_duration).to be_nil
      expect(record.average_view_percentage).to be_nil
    end
  end

  describe "scopes" do
    describe ".for_device_type" do
      it "filters by device_type" do
        video = create(:video)
        mobile  = create(:video_daily_by_device_type, video: video, device_type: "MOBILE", date: 1.day.ago.to_date)
        desktop = create(:video_daily_by_device_type, video: video, device_type: "DESKTOP", date: 2.days.ago.to_date)
        expect(described_class.for_device_type("MOBILE")).to include(mobile)
        expect(described_class.for_device_type("MOBILE")).not_to include(desktop)
      end
    end

    describe ".for_window" do
      it "filters by date range" do
        video = create(:video)
        inside  = create(:video_daily_by_device_type, video: video, device_type: "MOBILE", date: 3.days.ago.to_date)
        outside = create(:video_daily_by_device_type, video: video, device_type: "MOBILE", date: 30.days.ago.to_date)
        result = described_class.for_window(7.days.ago.to_date, Date.current)
        expect(result).to include(inside)
        expect(result).not_to include(outside)
      end
    end
  end
end
