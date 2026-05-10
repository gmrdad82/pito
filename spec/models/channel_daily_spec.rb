require "rails_helper"

RSpec.describe ChannelDaily, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:channel) }
  end

  describe "validations" do
    it "is invalid without a date" do
      record = build(:channel_daily, date: nil)
      expect(record).not_to be_valid
      expect(record.errors[:date]).to include("can't be blank")
    end

    it "is invalid without a channel_id" do
      record = build(:channel_daily, channel: nil)
      expect(record).not_to be_valid
    end

    it "is invalid with a duplicate (channel_id, date) pair" do
      existing = create(:channel_daily)
      duplicate = build(:channel_daily,
                        channel: existing.channel,
                        date: existing.date)
      expect(duplicate).not_to be_valid
    end

    it "rejects a row when (channel_id, date) collides at the DB level" do
      existing = create(:channel_daily)
      expect {
        described_class.connection.execute(<<~SQL)
          INSERT INTO channel_dailies
            (channel_id, date, created_at, updated_at)
          VALUES
            (#{existing.channel_id}, '#{existing.date.iso8601}', NOW(), NOW())
        SQL
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "defaults" do
    it "defaults every counter column to 0" do
      record = create(:channel_daily)
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
      record = create(:channel_daily)
      monetization = %i[
        estimated_revenue estimated_ad_revenue
        gross_revenue estimated_red_partner_revenue
        monetized_playbacks ad_impressions
      ]
      monetization.each do |attr|
        expect(record.public_send(attr)).to be_nil, "expected #{attr} to be NULL"
      end
    end
  end

  describe "scopes" do
    describe ".for_window" do
      it "filters by date range" do
        channel = create(:channel)
        in_range  = create(:channel_daily, channel: channel, date: 5.days.ago.to_date)
        out_of_range = create(:channel_daily, channel: channel, date: 30.days.ago.to_date)
        result = described_class.for_window(7.days.ago.to_date, Date.current)
        expect(result).to include(in_range)
        expect(result).not_to include(out_of_range)
      end
    end

    describe ".ordered_by_date" do
      it "ascends by date" do
        channel = create(:channel)
        newer = create(:channel_daily, channel: channel, date: 2.days.ago.to_date)
        older = create(:channel_daily, channel: channel, date: 5.days.ago.to_date)
        expect(described_class.ordered_by_date).to eq([ older, newer ])
      end
    end
  end
end
