require "rails_helper"

RSpec.describe "Per-channel analytics dashboard", type: :request do
  let(:connection) { create(:youtube_connection) }
  let(:channel) { create(:channel, youtube_connection: connection) }

  describe "GET /channels/:channel_id/analytics" do
    context "auth + 404" do
      it "redirects to /login when unauthenticated", :unauthenticated do
        get channel_analytics_path(channel)
        expect(response).to redirect_to(login_path)
      end

      it "404s on unknown channel id" do
        get "/channels/999999/analytics"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "window summary cards" do
      it "renders cards from channel_window_summary for the chosen window" do
        create(:channel_window_summary,
               channel: channel,
               window: "28d",
               views: 4242,
               estimated_minutes_watched: 808)
        get channel_analytics_path(channel)
        expect(response.body).to include("4,242")
        expect(response.body).to include("808")
      end

      it "renders an empty state when channel_window_summary has no rows for the window" do
        get channel_analytics_path(channel)
        expect(response.body).to include("no data for this window")
      end
    end

    context "channel daily line chart" do
      it "renders the line chart container" do
        create(:channel_daily, channel: channel, date: Date.current, views: 100)
        get channel_analytics_path(channel)
        expect(response.body).to include("analytics-chart--channel-daily")
      end

      it "renders the 3-day revision-band caption when data is present" do
        create(:channel_daily, channel: channel, date: Date.current, views: 100)
        get channel_analytics_path(channel)
        expect(response.body).to include("data revises for ~48-72h after publish")
      end

      it "filters to the chosen window's date range" do
        create(:channel_daily, channel: channel, date: Date.current, views: 100)
        create(:channel_daily, channel: channel, date: 60.days.ago.to_date, views: 999)
        get channel_analytics_path(channel, window: "7d")
        expect(response.body).to include("100")
      end
    end

    context "top videos leaderboard" do
      it "renders the table from top_videos_window for the chosen window" do
        video = create(:video, channel: channel)
        create(:top_videos_window,
               host_channel: channel,
               video: video,
               window: "28d",
               rank: 1,
               views: 1234)
        get channel_analytics_path(channel)
        expect(response.body).to include("top videos")
        expect(response.body).to include("1,234")
      end

      it "respects rank ordering" do
        video1 = create(:video, channel: channel, title: "first")
        video2 = create(:video, channel: channel, title: "second")
        create(:top_videos_window, host_channel: channel, video: video2, window: "28d", rank: 2)
        create(:top_videos_window, host_channel: channel, video: video1, window: "28d", rank: 1)
        get channel_analytics_path(channel)
        first_index  = response.body.index("first")
        second_index = response.body.index("second")
        expect(first_index).to be < second_index
      end
    end

    context "channel geography (caveat)" do
      it "renders the geography chart with the Q15 caveat caption when data exists" do
        video = create(:video, channel: channel)
        create(:video_daily_by_country,
               video: video, country_code: "US",
               date: Date.current, views: 100)
        get channel_analytics_path(channel)
        expect(response.body).to include("by country")
        expect(response.body).to include("summed from per-video data")
      end

      it "sums views from video_daily_by_country across the channel's videos" do
        v1 = create(:video, channel: channel)
        v2 = create(:video, channel: channel)
        create(:video_daily_by_country, video: v1, country_code: "US", date: Date.current, views: 60)
        create(:video_daily_by_country, video: v2, country_code: "US", date: Date.current, views: 90)
        get channel_analytics_path(channel)
        expect(response.body).to include("150")
      end
    end

    context "channel demographics (caveat)" do
      it "renders the demographics chart with the Q15 caveat caption when data exists" do
        video = create(:video, channel: channel)
        create(:video_daily_by_age_group_gender,
               video: video, age_group: "AGE_18_24", gender: "MALE",
               date: Date.current, viewer_percentage: 0.5)
        get channel_analytics_path(channel)
        expect(response.body).to include("demographics")
        expect(response.body).to include("summed from per-video data")
      end
    end

    context "refresh button" do
      it "renders the [refresh now] button when a connection is present" do
        get channel_analytics_path(channel)
        expect(response.body).to include("refresh now")
      end
    end

    context "needs_reauth banner" do
      it "renders the banner when the connection needs reauth" do
        connection.update!(needs_reauth: true)
        get channel_analytics_path(channel)
        expect(response.body).to include("re-authorize this channel")
      end
    end

    # Phase 26 §01g — viewer-time heatmap (channel-aggregate).
    context "viewer-time heatmap" do
      it "renders the heatmap section header" do
        get channel_analytics_path(channel)
        expect(response.body).to include("viewer-time heatmap")
      end

      it "renders the empty-state copy when no buckets exist for the channel" do
        get channel_analytics_path(channel)
        expect(response.body).to include("no viewer-time data yet")
      end

      it "renders the grid when at least one video on the channel has buckets" do
        video = create(:video, channel: channel)
        create(:video_viewer_time_bucket, video: video,
               day_of_week_utc: 3, hour_of_day_utc: 14, view_count: 5)
        get channel_analytics_path(channel)
        expect(response.body).to include("viewer-time-heatmap__grid")
      end
    end
  end
end
