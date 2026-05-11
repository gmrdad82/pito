require "rails_helper"

RSpec.describe "channels/_videos_pane.html.erb", type: :view do
  include ActiveSupport::Testing::TimeHelpers

  let(:channel) { create(:channel) }

  before { ChannelSync.clear }

  context "when the channel has no videos" do
    it "renders the videos heading with a zero count" do
      render "channels/videos_pane", channel: channel
      expect(rendered).to include("videos (0)")
    end

    it "renders the muted no-videos caption" do
      render "channels/videos_pane", channel: channel
      expect(rendered).to include("no videos yet.")
    end

    it "still renders the [see all] link (the picker page handles the empty state)" do
      render "channels/videos_pane", channel: channel
      expect(rendered).to include("see all")
      expect(rendered).to include("href=\"#{videos_path(channel: channel.to_param)}\"")
    end
  end

  context "when the channel has a single video" do
    let!(:video) { create(:video, channel: channel) }

    it "renders the videos heading with count 1" do
      render "channels/videos_pane", channel: channel
      expect(rendered).to include("videos (1)")
    end

    it "renders the video row" do
      render "channels/videos_pane", channel: channel
      expect(rendered).to include(video.youtube_video_id)
    end

    it "renders the [see all] link with the channel slug" do
      render "channels/videos_pane", channel: channel
      expect(rendered).to include("href=\"#{videos_path(channel: channel.to_param)}\"")
    end
  end

  context "when the channel has 30 videos" do
    before do
      30.times { create(:video, channel: channel) }
    end

    it "renders all 30 rows" do
      render "channels/videos_pane", channel: channel
      # 30 <tr> rows in the tbody (plus 1 in thead).
      expect(rendered.scan(/<tr>/).size).to eq(31)
    end
  end

  context "when the channel has 31 videos (cap at 30)" do
    before do
      31.times { create(:video, channel: channel) }
    end

    it "renders only 30 video rows" do
      render "channels/videos_pane", channel: channel
      expect(rendered.scan(/<tr>/).size).to eq(31) # 1 header + 30 body
    end

    it "renders the heading with the total count (31)" do
      render "channels/videos_pane", channel: channel
      expect(rendered).to include("videos (31)")
    end
  end

  context "starred-first ordering" do
    let!(:plain_recent) do
      create(:video, channel: channel, star: false, published_at: 1.day.ago)
    end
    let!(:starred_old) do
      create(:video, channel: channel, star: true, published_at: 1.year.ago)
    end
    let!(:plain_older) do
      create(:video, channel: channel, star: false, published_at: 1.month.ago)
    end

    it "renders starred videos before non-starred regardless of published_at" do
      render "channels/videos_pane", channel: channel
      starred_idx = rendered.index(starred_old.youtube_video_id)
      recent_idx = rendered.index(plain_recent.youtube_video_id)
      older_idx = rendered.index(plain_older.youtube_video_id)
      expect(starred_idx).not_to be_nil
      expect(recent_idx).not_to be_nil
      expect(older_idx).not_to be_nil
      expect(starred_idx).to be < recent_idx
      expect(starred_idx).to be < older_idx
    end

    it "orders non-starred videos by published_at DESC" do
      render "channels/videos_pane", channel: channel
      recent_idx = rendered.index(plain_recent.youtube_video_id)
      older_idx = rendered.index(plain_older.youtube_video_id)
      expect(recent_idx).to be < older_idx
    end

    it "dedupes a starred video — appears as a single table row, not two" do
      # The single ORDER BY clause arranges the whole table, so each row
      # appears exactly once. A starred recent video lands at the top
      # and does NOT also appear in the latest block. The youtube_video_id
      # string can occur twice within the same row (once as the id link
      # target, once as the YouTube id cell), so the dedup check counts
      # tbody <tr> elements rather than raw string occurrences.
      render "channels/videos_pane", channel: channel
      tbody = rendered[/<tbody>(.*?)<\/tbody>/m, 1].to_s
      rows = tbody.scan(/<tr>/).size
      expect(rows).to eq(3) # three distinct videos, no dup row
      # Each starred-row youtube_video_id appears inside exactly one
      # `<td>vid_...</td>` cell.
      cell_matches = tbody.scan(/<td>#{Regexp.escape(starred_old.youtube_video_id)}<\/td>/).size
      expect(cell_matches).to eq(1)
    end
  end

  context "video without published_at (falls back to created_at)" do
    let!(:newest) do
      travel_to(Time.zone.local(2026, 5, 10, 12, 0, 0)) do
        create(:video, channel: channel, published_at: nil)
      end
    end
    let!(:older) do
      travel_to(Time.zone.local(2025, 1, 1, 12, 0, 0)) do
        create(:video, channel: channel, published_at: nil)
      end
    end

    it "orders by created_at DESC when published_at is nil" do
      render "channels/videos_pane", channel: channel
      newest_idx = rendered.index(newest.youtube_video_id)
      older_idx = rendered.index(older.youtube_video_id)
      expect(newest_idx).to be < older_idx
    end
  end
end
