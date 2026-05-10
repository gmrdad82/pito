require "rails_helper"

RSpec.describe VideoDailyBySubscribedStatus, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:video) }
  end

  describe "validations" do
    it "is invalid without a subscribed_status" do
      record = build(:video_daily_by_subscribed_status, subscribed_status: nil)
      expect(record).not_to be_valid
      expect(record.errors[:subscribed_status]).to include("can't be blank")
    end

    it "is invalid with a duplicate (video_id, date, subscribed_status)" do
      existing = create(:video_daily_by_subscribed_status)
      duplicate = build(:video_daily_by_subscribed_status,
                        video: existing.video,
                        date: existing.date,
                        subscribed_status: existing.subscribed_status)
      expect(duplicate).not_to be_valid
    end
  end

  describe "defaults" do
    it "defaults counters to 0 and ratios to NULL" do
      record = create(:video_daily_by_subscribed_status)
      expect(record.views).to eq(0)
      expect(record.estimated_minutes_watched).to eq(0)
      expect(record.average_view_percentage).to be_nil
    end
  end

  describe "scopes" do
    describe ".for_subscribed_status" do
      it "filters by subscribed_status" do
        video = create(:video)
        sub = create(:video_daily_by_subscribed_status, video: video,
                     subscribed_status: "SUBSCRIBED", date: 1.day.ago.to_date)
        unsub = create(:video_daily_by_subscribed_status, video: video,
                       subscribed_status: "UNSUBSCRIBED", date: 2.days.ago.to_date)
        expect(described_class.for_subscribed_status("SUBSCRIBED")).to include(sub)
        expect(described_class.for_subscribed_status("SUBSCRIBED")).not_to include(unsub)
      end
    end

    describe ".for_window" do
      it "filters by date range" do
        video = create(:video)
        inside = create(:video_daily_by_subscribed_status, video: video,
                        subscribed_status: "SUBSCRIBED", date: 3.days.ago.to_date)
        outside = create(:video_daily_by_subscribed_status, video: video,
                         subscribed_status: "SUBSCRIBED", date: 30.days.ago.to_date)
        result = described_class.for_window(7.days.ago.to_date, Date.current)
        expect(result).to include(inside)
        expect(result).not_to include(outside)
      end
    end
  end
end
