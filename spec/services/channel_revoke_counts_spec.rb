require "rails_helper"

RSpec.describe ChannelRevokeCounts, type: :service do
  let(:connection) { create(:youtube_connection) }
  let!(:channel) { create(:channel, youtube_connection: connection) }

  describe ".for" do
    context "with a bare channel (no dependents)" do
      it "returns zeros for everything except the auto-derived calendar entry" do
        # Channel#after_create_commit derives ONE calendar entry. The
        # bare-channel state is therefore (0, 0, 0, 0, 0, 0, 1) — the
        # service counts the derived entry too.
        counts = described_class.for(channel)
        expect(counts.videos).to eq(0)
        expect(counts.analytics).to eq(0)
        expect(counts.diffs).to eq(0)
        expect(counts.change_logs).to eq(0)
        expect(counts.links).to eq(0)
        expect(counts.rejected_imports).to eq(0)
        expect(counts.calendar_entries).to eq(1)
      end
    end

    context "with videos under the channel" do
      let!(:video_a) { create(:video, channel: channel) }
      let!(:video_b) { create(:video, channel: channel) }

      it "counts videos accurately" do
        counts = described_class.for(channel)
        expect(counts.videos).to eq(2)
      end

      it "counts the channel's calendar_entries (channel auto-derives one on create)" do
        # Channel#after_create_commit derives one calendar entry. Each
        # Video also derives one when public/scheduled; private videos
        # don't. The spec keeps the videos private so only the
        # channel-level entry is counted.
        counts = described_class.for(channel)
        expect(counts.calendar_entries).to be >= 1
      end

      it "counts video-level analytics rows summed across all video_* tables" do
        create(:video_daily, video: video_a, date: Date.current)
        create(:video_daily, video: video_a, date: Date.current - 1)
        create(:video_window_summary, video: video_b, window: "7d")

        counts = described_class.for(channel)
        # video_a has 2 video_dailies; video_b has 1 window_summary → 3 total
        expect(counts.analytics).to eq(3)
      end

      it "counts video change_logs" do
        create(:video_change_log, video: video_a)

        counts = described_class.for(channel)
        expect(counts.change_logs).to be >= 1
      end

      it "counts video links (video_game_links)" do
        game = create(:game)
        create(:video_game_link, video: video_a, game: game)

        counts = described_class.for(channel)
        expect(counts.links).to eq(1)
      end

      it "counts video diffs" do
        create(:video_diff, video: video_a)

        counts = described_class.for(channel)
        expect(counts.diffs).to eq(1)
      end
    end

    context "with channel-level dependents" do
      it "counts channel_change_logs" do
        create(:channel_change_log, channel: channel)
        counts = described_class.for(channel)
        expect(counts.change_logs).to be >= 1
      end

      # Unit A0 — the `channel_diffs` table was dropped; the channel is
      # a read-only mirror. The `diffs` count category is now video-side
      # only (see the "counts video diffs" example above).

      it "counts channel_dailies (analytics)" do
        create(:channel_daily, channel: channel, date: Date.current)
        counts = described_class.for(channel)
        expect(counts.analytics).to be >= 1
      end

      it "counts rejected_video_imports" do
        create(:rejected_video_import, channel: channel)
        counts = described_class.for(channel)
        expect(counts.rejected_imports).to eq(1)
      end
    end

    context "isolation — other channels' rows are not counted" do
      let!(:other_channel) { create(:channel) }
      let!(:other_video) { create(:video, channel: other_channel) }

      before do
        create(:video_daily, video: other_video, date: Date.current)
        create(:channel_daily, channel: other_channel, date: Date.current)
        create(:channel_change_log, channel: other_channel)
      end

      it "returns zero analytics for the unrelated channel under audit" do
        counts = described_class.for(channel)
        # channel itself has no video / channel daily rows.
        expect(counts.analytics).to eq(0)
        expect(counts.change_logs).to eq(0)
      end
    end
  end

  describe ".for_many" do
    let!(:second_channel) { create(:channel) }

    it "returns all-zero struct for empty array" do
      counts = described_class.for_many([])
      expect(counts.videos).to eq(0)
      expect(counts.analytics).to eq(0)
    end

    it "sums counts across N channels" do
      create(:video, channel: channel)
      create(:video, channel: second_channel)
      create(:video, channel: second_channel)

      counts = described_class.for_many([ channel, second_channel ])
      expect(counts.videos).to eq(3)
    end
  end
end
