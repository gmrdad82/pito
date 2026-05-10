require "rails_helper"

RSpec.describe VideoDaily, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:video) }
  end

  describe "validations" do
    it "is invalid without a date" do
      record = build(:video_daily, date: nil)
      expect(record).not_to be_valid
      expect(record.errors[:date]).to include("can't be blank")
    end

    it "is invalid without a video_id" do
      record = build(:video_daily, video: nil)
      expect(record).not_to be_valid
    end

    it "is invalid with a duplicate (video_id, date) pair" do
      existing = create(:video_daily)
      duplicate = build(:video_daily, video: existing.video, date: existing.date)
      expect(duplicate).not_to be_valid
    end

    it "rejects a row when (video_id, date) collides at the DB level" do
      existing = create(:video_daily)
      expect {
        described_class.connection.execute(<<~SQL)
          INSERT INTO video_dailies
            (video_id, date, created_at, updated_at)
          VALUES
            (#{existing.video_id}, '#{existing.date.iso8601}', NOW(), NOW())
        SQL
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "defaults" do
    it "defaults every counter column to 0" do
      record = create(:video_daily)
      counters = %i[
        views engaged_views red_views
        estimated_minutes_watched estimated_red_minutes_watched
        likes dislikes comments shares
        videos_added_to_playlists videos_removed_from_playlists
        subscribers_gained subscribers_lost
        video_thumbnail_impressions
        card_impressions card_clicks
        card_teaser_impressions card_teaser_clicks
      ]
      counters.each do |attr|
        expect(record.public_send(attr)).to eq(0), "expected #{attr} to default to 0"
      end
    end

    it "leaves every monetization column NULL" do
      record = create(:video_daily)
      %i[estimated_revenue estimated_ad_revenue gross_revenue
         estimated_red_partner_revenue monetized_playbacks
         ad_impressions].each do |attr|
        expect(record.public_send(attr)).to be_nil
      end
    end
  end

  describe "scopes" do
    describe ".for_window" do
      it "filters by date range" do
        video = create(:video)
        inside  = create(:video_daily, video: video, date: 5.days.ago.to_date)
        outside = create(:video_daily, video: video, date: 30.days.ago.to_date)
        result = described_class.for_window(7.days.ago.to_date, Date.current)
        expect(result).to include(inside)
        expect(result).not_to include(outside)
      end
    end

    describe ".ordered_by_date" do
      it "ascends by date" do
        video = create(:video)
        newer = create(:video_daily, video: video, date: 2.days.ago.to_date)
        older = create(:video_daily, video: video, date: 5.days.ago.to_date)
        expect(described_class.ordered_by_date).to eq([ older, newer ])
      end
    end
  end
end
