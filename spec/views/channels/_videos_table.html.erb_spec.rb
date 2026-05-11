require "rails_helper"

# 2026-05-11 — channel show page restructure. The videos block is
# rendered via `channels/_videos_table` and is no longer a pane. The
# partial takes three locals (channel, videos, total) so the spec
# constructs the aggregated relation the same way the controller does.
RSpec.describe "channels/_videos_table.html.erb", type: :view do
  include ActiveSupport::Testing::TimeHelpers

  let(:channel) { create(:channel) }

  before { ChannelSync.clear }

  def render_table(channel:)
    relation = channel.videos
      .left_joins(:video_stats)
      .select(
        "videos.*",
        "COALESCE(SUM(video_stats.views), 0) AS total_views",
        "COALESCE(SUM(video_stats.likes), 0) AS total_likes",
        "COALESCE(SUM(video_stats.comments), 0) AS total_comments",
        "COALESCE(CAST(SUM(video_stats.watch_time_minutes) AS BIGINT), 0) AS total_watch_time"
      )
      .group("videos.id")
      .order(Arel.sql("videos.star DESC, COALESCE(videos.published_at, videos.created_at) DESC"))
      .limit(30)
    render "channels/videos_table",
           channel: channel,
           videos: relation,
           total: channel.videos.count
  end

  context "when the channel has no videos" do
    it "renders the videos heading with a zero count" do
      render_table(channel: channel)
      expect(rendered).to include("videos (0)")
    end

    it "renders the muted no-videos caption" do
      render_table(channel: channel)
      expect(rendered).to include("no videos yet.")
    end

    it "does NOT render the [see all videos] link (count is at most 30)" do
      render_table(channel: channel)
      expect(rendered).not_to include("see all videos")
    end
  end

  context "when the channel has a single video" do
    let!(:video) { create(:video, channel: channel) }

    it "renders the videos heading with count 1" do
      render_table(channel: channel)
      expect(rendered).to include("videos (1)")
    end

    it "renders the video row" do
      render_table(channel: channel)
      expect(rendered).to include(video.youtube_video_id)
    end

    it "does NOT render the [see all videos] link" do
      render_table(channel: channel)
      expect(rendered).not_to include("see all videos")
    end
  end

  context "when the channel has exactly 30 videos" do
    before do
      30.times { create(:video, channel: channel) }
    end

    it "renders all 30 rows" do
      render_table(channel: channel)
      body_rows = rendered[/<tbody>(.*?)<\/tbody>/m, 1].to_s.scan(/<tr>/).size
      expect(body_rows).to eq(30)
    end

    it "still does NOT render the [see all videos] link (table shows everything)" do
      render_table(channel: channel)
      expect(rendered).not_to include("see all videos")
    end
  end

  context "when the channel has 31 videos (cap at 30)" do
    before do
      31.times { create(:video, channel: channel) }
    end

    it "renders only 30 video rows in the tbody" do
      render_table(channel: channel)
      body_rows = rendered[/<tbody>(.*?)<\/tbody>/m, 1].to_s.scan(/<tr>/).size
      expect(body_rows).to eq(30)
    end

    it "renders the heading with the total count (31)" do
      render_table(channel: channel)
      expect(rendered).to include("videos (31)")
    end

    it "renders the [see all videos] link with the channel slug" do
      render_table(channel: channel)
      expect(rendered).to include("see all videos")
      expect(rendered).to include("href=\"#{videos_path(channel: channel.to_param)}\"")
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
      render_table(channel: channel)
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
      render_table(channel: channel)
      recent_idx = rendered.index(plain_recent.youtube_video_id)
      older_idx = rendered.index(plain_older.youtube_video_id)
      expect(recent_idx).to be < older_idx
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
      render_table(channel: channel)
      newest_idx = rendered.index(newest.youtube_video_id)
      older_idx = rendered.index(older.youtube_video_id)
      expect(newest_idx).to be < older_idx
    end
  end

  context "table shape — mirrors /videos column conventions" do
    let!(:video) { create(:video, channel: channel, star: true, published_at: 2.days.ago) }

    it "renders the canonical column headers" do
      render_table(channel: channel)
      %w[id YouTube\ id title privacy views likes chats watch star synced].each do |label|
        expect(rendered).to include("<th") # sanity
        expect(rendered).to include(label)
      end
    end

    it "right-aligns numeric columns with class=\"num\"" do
      render_table(channel: channel)
      expect(rendered.scan(/class="num"/).size).to be >= 5
    end

    it "renders the [edit] link per row" do
      render_table(channel: channel)
      expect(rendered).to include(edit_video_path(video))
    end

    it "does NOT render a channel column (everything is the same channel)" do
      render_table(channel: channel)
      expect(rendered).not_to include("<th>channel</th>")
    end
  end
end
