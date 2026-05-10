require "rails_helper"

RSpec.describe TopVideosWindow, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:channel) }
    it { is_expected.to belong_to(:video) }
  end

  describe "window enum" do
    it "round-trips the four window values" do
      channel = create(:channel)
      videos  = Array.new(4) { create(:video, channel: channel) }
      %w[7d 28d 90d lifetime].each_with_index do |w, idx|
        record = create(:top_videos_window,
                        channel: channel,
                        video: videos[idx],
                        window: w,
                        rank: idx + 1)
        record.reload
        expect(record.window).to eq(w)
      end
    end
  end

  describe "validations" do
    it "is invalid without rank" do
      record = build(:top_videos_window, rank: nil)
      expect(record).not_to be_valid
      expect(record.errors[:rank]).to be_present
    end

    it "is invalid with rank < 1" do
      record = build(:top_videos_window, rank: 0)
      expect(record).not_to be_valid
      expect(record.errors[:rank]).to be_present
    end

    it "is invalid with a duplicate (channel_id, window, video_id)" do
      existing = create(:top_videos_window, window: "28d", rank: 1)
      duplicate = build(:top_videos_window,
                        channel: existing.channel,
                        video: existing.video,
                        window: "28d",
                        rank: 2)
      expect(duplicate).not_to be_valid
    end

    it "is invalid with a duplicate (channel_id, window, rank)" do
      channel = create(:channel)
      v1 = create(:video, channel: channel)
      v2 = create(:video, channel: channel)
      create(:top_videos_window, channel: channel, video: v1, window: "28d", rank: 1)
      duplicate = build(:top_videos_window,
                        channel: channel, video: v2, window: "28d", rank: 1)
      expect(duplicate).not_to be_valid
    end
  end

  describe "scopes" do
    describe ".top_n" do
      it "returns the first n by rank" do
        channel = create(:channel)
        videos  = Array.new(5) { create(:video, channel: channel) }
        videos.each_with_index do |v, i|
          create(:top_videos_window,
                 channel: channel, video: v, window: "28d", rank: i + 1)
        end
        result = described_class.where(channel: channel, window: "28d").top_n(3)
        expect(result.map(&:rank)).to eq([ 1, 2, 3 ])
      end
    end

    describe ".for_window" do
      it "filters by window" do
        channel = create(:channel)
        videos  = Array.new(2) { create(:video, channel: channel) }
        seven  = create(:top_videos_window, channel: channel, video: videos[0],
                        window: "7d", rank: 1)
        twenty = create(:top_videos_window, channel: channel, video: videos[1],
                        window: "28d", rank: 1)
        expect(described_class.for_window("7d")).to include(seven)
        expect(described_class.for_window("7d")).not_to include(twenty)
      end
    end
  end

  describe "cascade" do
    it "is destroyed when its channel is destroyed" do
      channel = create(:channel)
      video   = create(:video, channel: channel)
      create(:top_videos_window, channel: channel, video: video, window: "28d", rank: 1)
      expect { channel.destroy }.to change(described_class, :count).by(-1)
    end

    it "is destroyed when its video is destroyed" do
      channel = create(:channel)
      video   = create(:video, channel: channel)
      create(:top_videos_window, channel: channel, video: video, window: "28d", rank: 1)
      expect { video.destroy }.to change(described_class, :count).by(-1)
    end
  end
end
