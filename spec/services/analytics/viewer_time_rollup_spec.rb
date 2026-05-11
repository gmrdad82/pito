require "rails_helper"

RSpec.describe Analytics::ViewerTimeRollup do
  subject(:service) { described_class.new }

  let(:channel) { create(:channel) }
  let(:video) { create(:video, channel: channel) }

  describe "#call with scope: :video" do
    it "returns a hash keyed [dow_local, hod_local] => Result" do
      create(:video_viewer_time_bucket,
             video: video,
             day_of_week_utc: 3,
             hour_of_day_utc: 14,
             view_count: 50,
             watch_time_seconds: 3000)

      result = service.call(scope: :video, id: video.id, tz: "Etc/UTC")

      expect(result).to include([ 3, 14 ])
      cell = result[[ 3, 14 ]]
      expect(cell.views).to eq(50)
      expect(cell.watch_time_seconds).to eq(3000)
    end

    it "returns an empty hash when the video has no buckets" do
      expect(service.call(scope: :video, id: video.id, tz: "Etc/UTC")).to eq({})
    end

    it "scopes to the named video — excludes other videos on the channel" do
      other_video = create(:video, channel: channel)
      create(:video_viewer_time_bucket, video: video, hour_of_day_utc: 0)
      create(:video_viewer_time_bucket, video: other_video, hour_of_day_utc: 5)

      result = service.call(scope: :video, id: video.id, tz: "Etc/UTC")

      expect(result.keys.map(&:last)).to eq([ 0 ])
    end

    it "shifts to user tz when given an IANA name" do
      create(:video_viewer_time_bucket,
             video: video,
             day_of_week_utc: 0,
             hour_of_day_utc: 0,
             view_count: 7)

      result = service.call(scope: :video, id: video.id, tz: "Asia/Kolkata")

      # UTC Sun 00:00 → Kolkata Sun 05:30 → (dow 0, hod 5)
      expect(result.keys).to eq([ [ 0, 5 ] ])
      expect(result[[ 0, 5 ]].views).to eq(7)
    end

    it "accepts an ActiveSupport::TimeZone instance" do
      create(:video_viewer_time_bucket,
             video: video,
             day_of_week_utc: 0,
             hour_of_day_utc: 0)
      tz = ActiveSupport::TimeZone["Asia/Kolkata"]

      result = service.call(scope: :video, id: video.id, tz: tz)

      expect(result.keys).to eq([ [ 0, 5 ] ])
    end
  end

  describe "#call with scope: :channel" do
    it "aggregates across every video on the channel" do
      v1 = create(:video, channel: channel)
      v2 = create(:video, channel: channel)
      create(:video_viewer_time_bucket,
             video: v1, day_of_week_utc: 3, hour_of_day_utc: 14,
             view_count: 10, watch_time_seconds: 100)
      create(:video_viewer_time_bucket,
             video: v2, day_of_week_utc: 3, hour_of_day_utc: 14,
             view_count: 20, watch_time_seconds: 200)

      result = service.call(scope: :channel, id: channel.id, tz: "Etc/UTC")

      cell = result[[ 3, 14 ]]
      expect(cell.views).to eq(30)
      expect(cell.watch_time_seconds).to eq(300)
    end

    it "returns empty hash when no buckets on the channel" do
      expect(service.call(scope: :channel, id: channel.id, tz: "Etc/UTC")).to eq({})
    end

    it "ignores videos belonging to a different channel" do
      v1 = create(:video, channel: channel)
      other_channel = create(:channel)
      other_video = create(:video, channel: other_channel)
      create(:video_viewer_time_bucket, video: v1, hour_of_day_utc: 0, view_count: 5)
      create(:video_viewer_time_bucket, video: other_video, hour_of_day_utc: 0, view_count: 999)

      result = service.call(scope: :channel, id: channel.id, tz: "Etc/UTC")

      expect(result[[ 0, 0 ]].views).to eq(5)
    end
  end

  describe "#call argument validation" do
    it "raises ArgumentError on an unknown scope" do
      expect { service.call(scope: :unknown, id: 1, tz: "Etc/UTC") }
        .to raise_error(ArgumentError, /scope must be/)
    end
  end

  describe "tz coverage" do
    before do
      # One bucket at UTC Sun 00:00 — verify it lands in the right
      # local cell across multiple zones.
      create(:video_viewer_time_bucket,
             video: video,
             day_of_week_utc: 0,
             hour_of_day_utc: 0,
             view_count: 1)
    end

    {
      "Etc/UTC"             => [ 0, 0 ],
      "Asia/Kolkata"        => [ 0, 5 ],
      "Pacific/Kiritimati"  => [ 0, 14 ],
      "Pacific/Pago_Pago"   => [ 6, 13 ]
    }.each do |tz, expected|
      it "rolls UTC Sun 00:00 to #{expected.inspect} under #{tz}" do
        result = service.call(scope: :video, id: video.id, tz: tz)
        expect(result.keys.first).to eq(expected)
      end
    end
  end
end
