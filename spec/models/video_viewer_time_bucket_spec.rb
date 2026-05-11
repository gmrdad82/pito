require "rails_helper"

RSpec.describe VideoViewerTimeBucket, type: :model do
  let(:video) { create(:video) }

  describe "associations" do
    it { is_expected.to belong_to(:video) }
  end

  describe "validations" do
    subject { build(:video_viewer_time_bucket, video: video) }

    it { is_expected.to be_valid }

    it "rejects hour_of_day_utc below 0" do
      subject.hour_of_day_utc = -1
      expect(subject).to be_invalid
      expect(subject.errors[:hour_of_day_utc]).to be_present
    end

    it "rejects hour_of_day_utc above 23" do
      subject.hour_of_day_utc = 24
      expect(subject).to be_invalid
      expect(subject.errors[:hour_of_day_utc]).to be_present
    end

    it "accepts hour_of_day_utc at 0 and 23 boundary" do
      subject.hour_of_day_utc = 0
      expect(subject).to be_valid
      subject.hour_of_day_utc = 23
      expect(subject).to be_valid
    end

    it "rejects day_of_week_utc below 0" do
      subject.day_of_week_utc = -1
      expect(subject).to be_invalid
      expect(subject.errors[:day_of_week_utc]).to be_present
    end

    it "rejects day_of_week_utc above 6" do
      subject.day_of_week_utc = 7
      expect(subject).to be_invalid
      expect(subject.errors[:day_of_week_utc]).to be_present
    end

    it "rejects negative view_count" do
      subject.view_count = -1
      expect(subject).to be_invalid
    end

    it "rejects negative watch_time_seconds" do
      subject.watch_time_seconds = -1
      expect(subject).to be_invalid
    end

    it "enforces uniqueness on (video_id, day_of_week_utc, hour_of_day_utc)" do
      create(:video_viewer_time_bucket,
             video: video,
             day_of_week_utc: 3,
             hour_of_day_utc: 14)
      dupe = build(:video_viewer_time_bucket,
                   video: video,
                   day_of_week_utc: 3,
                   hour_of_day_utc: 14)
      expect(dupe).to be_invalid
      expect(dupe.errors[:video_id]).to be_present
    end
  end

  describe ".for_channel" do
    it "joins through videos and filters by channel id" do
      other_channel = create(:channel)
      same_channel  = video.channel
      bucket_same  = create(:video_viewer_time_bucket, video: video)
      _other_video = create(:video, channel: other_channel)
      create(:video_viewer_time_bucket, video: _other_video, hour_of_day_utc: 5)

      scope = described_class.for_channel(same_channel.id)

      expect(scope.pluck(:id)).to contain_exactly(bucket_same.id)
    end
  end

  describe ".rolled_up_to_tz" do
    before do
      # Two buckets at the same UTC slot, summed.
      create(:video_viewer_time_bucket,
             video: video,
             day_of_week_utc: 0,
             hour_of_day_utc: 0,
             view_count: 10,
             watch_time_seconds: 600)
      create(:video_viewer_time_bucket,
             video: video,
             day_of_week_utc: 3,
             hour_of_day_utc: 14,
             view_count: 50,
             watch_time_seconds: 3000)
    end

    it "returns rows under Etc/UTC unchanged" do
      rows = described_class.where(video_id: video.id).rolled_up_to_tz("Etc/UTC")
      pairs = rows.map { |r| [ r["dow_local"].to_i, r["hod_local"].to_i, r["view_count"].to_i ] }
      expect(pairs).to contain_exactly(
        [ 0, 0, 10 ],
        [ 3, 14, 50 ]
      )
    end

    it "shifts dow/hod under Asia/Kolkata (+05:30)" do
      rows = described_class.where(video_id: video.id).rolled_up_to_tz("Asia/Kolkata")
      pairs = rows.map { |r| [ r["dow_local"].to_i, r["hod_local"].to_i ] }
      # UTC Sun 00:00 → Kolkata Sun 05:30 (dow 0, hod 5)
      # UTC Wed 14:00 → Kolkata Wed 19:30 (dow 3, hod 19)
      expect(pairs).to contain_exactly([ 0, 5 ], [ 3, 19 ])
    end

    it "shifts dow under Pacific/Kiritimati (+14:00)" do
      rows = described_class.where(video_id: video.id).rolled_up_to_tz("Pacific/Kiritimati")
      pairs = rows.map { |r| [ r["dow_local"].to_i, r["hod_local"].to_i ] }
      # UTC Sun 00:00 → Kiritimati Sun 14:00 (dow 0, hod 14)
      # UTC Wed 14:00 → Kiritimati Thu 04:00 (dow 4, hod 4)
      expect(pairs).to contain_exactly([ 0, 14 ], [ 4, 4 ])
    end

    it "groups duplicate local cells in a single tz query" do
      # Two distinct UTC buckets that land on the same local cell after
      # conversion to Asia/Kolkata.
      create(:video_viewer_time_bucket,
             video: video,
             day_of_week_utc: 0,
             hour_of_day_utc: 1,
             view_count: 5,
             watch_time_seconds: 300)
      # UTC Sun 00:00 → Kolkata Sun 05:30 (dow 0, hod 5)
      # UTC Sun 01:00 → Kolkata Sun 06:30 (dow 0, hod 6)
      # The two are distinct cells in Kolkata; pick a slot that
      # genuinely collapses: none from default fixture; use a fresh
      # video for a clean fixture.
      fresh_video = create(:video)
      create(:video_viewer_time_bucket,
             video: fresh_video,
             day_of_week_utc: 0,
             hour_of_day_utc: 0,
             view_count: 3,
             watch_time_seconds: 100)
      create(:video_viewer_time_bucket,
             video: fresh_video,
             day_of_week_utc: 0,
             hour_of_day_utc: 1,
             view_count: 7,
             watch_time_seconds: 200)
      # Aggregate across both videos at the channel scope — picks up
      # all 4 buckets. Two unique Kolkata cells: (0,5)=10+3=13 and
      # (0,6)=5+7=12. Plus (3,19) from the second fixture.
      channel_id = video.channel_id
      fresh_video.update!(channel_id: channel_id)
      rows = described_class.for_channel(channel_id).rolled_up_to_tz("Asia/Kolkata")
      pairs = rows.map { |r| [ r["dow_local"].to_i, r["hod_local"].to_i, r["view_count"].to_i ] }
      expect(pairs).to include([ 0, 5, 13 ])
      expect(pairs).to include([ 0, 6, 12 ])
    end
  end

  describe "DB-level constraints" do
    it "enforces hour range via CHECK constraint" do
      expect {
        described_class.connection.execute(<<~SQL)
          INSERT INTO video_viewer_time_buckets
            (video_id, hour_of_day_utc, day_of_week_utc, view_count, watch_time_seconds, created_at, updated_at)
          VALUES (#{video.id}, 24, 0, 0, 0, NOW(), NOW())
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /viewer_time_buckets_hour_range/)
    end

    it "enforces dow range via CHECK constraint" do
      expect {
        described_class.connection.execute(<<~SQL)
          INSERT INTO video_viewer_time_buckets
            (video_id, hour_of_day_utc, day_of_week_utc, view_count, watch_time_seconds, created_at, updated_at)
          VALUES (#{video.id}, 0, 7, 0, 0, NOW(), NOW())
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /viewer_time_buckets_dow_range/)
    end
  end
end
