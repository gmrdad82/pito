require "rails_helper"

RSpec.describe "Per-video analytics dashboard", type: :request do
  let(:connection) { create(:youtube_connection) }
  let(:channel) { create(:channel, youtube_connection: connection) }
  let(:video) { create(:video, channel: channel) }

  describe "GET /videos/:video_id/analytics" do
    context "auth + 404" do
      it "redirects to /login when unauthenticated", :unauthenticated do
        get video_analytics_path(video)
        expect(response).to redirect_to(login_path)
      end

      it "404s on unknown video id" do
        get "/videos/999999/analytics"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "window summary cards" do
      it "renders cards from video_window_summary for the chosen window" do
        create(:video_window_summary,
               video: video, window: "28d", views: 9876)
        get video_analytics_path(video)
        expect(response.body).to include("9,876")
      end

      it "renders an empty state when no rows exist for the window" do
        get video_analytics_path(video)
        expect(response.body).to include("no data for this window")
      end
    end

    context "daily line chart" do
      it "renders the chart container" do
        create(:video_daily, video: video, date: Date.current, views: 50)
        get video_analytics_path(video)
        expect(response.body).to include("analytics-chart--video-daily")
      end

      it "renders the revision-band caption when data is present" do
        create(:video_daily, video: video, date: Date.current, views: 50)
        get video_analytics_path(video)
        expect(response.body).to include("data revises for ~48-72h after publish")
      end
    end

    context "retention curve" do
      it "renders the retention chart container when buckets exist" do
        create(:video_retention, video: video, elapsed_ratio_bucket: 0.5)
        get video_analytics_path(video)
        expect(response.body).to include("retention curve")
      end

      it "renders the [refresh retention now] empty-state button when no buckets exist" do
        get video_analytics_path(video)
        expect(response.body).to include("retention data is refreshed weekly")
        expect(response.body).to include("refresh retention now")
      end
    end

    context "by-country bar" do
      it "renders the country chart" do
        create(:video_daily_by_country, video: video, country_code: "US", date: Date.current)
        get video_analytics_path(video)
        expect(response.body).to include("by country")
      end
    end

    context "by-device donut" do
      it "renders the device chart" do
        create(:video_daily_by_device_type, video: video, device_type: "MOBILE", date: Date.current)
        get video_analytics_path(video)
        expect(response.body).to include("by device")
      end
    end

    context "by-OS donut" do
      it "renders the OS chart" do
        create(:video_daily_by_operating_system, video: video, operating_system: "ANDROID", date: Date.current)
        get video_analytics_path(video)
        expect(response.body).to include("by operating system")
      end
    end

    context "by-traffic-source bar" do
      it "renders the traffic source chart" do
        create(:video_daily_by_traffic_source, video: video, traffic_source_type: "YT_SEARCH", date: Date.current)
        get video_analytics_path(video)
        expect(response.body).to include("by traffic source")
      end
    end

    context "by-subscribed-status donut" do
      it "renders the subscribed-status chart" do
        create(:video_daily_by_subscribed_status, video: video, subscribed_status: "SUBSCRIBED", date: Date.current)
        get video_analytics_path(video)
        expect(response.body).to include("by subscribed status")
      end
    end

    context "demographics heatmap" do
      it "renders the demographics chart" do
        create(:video_daily_by_age_group_gender, video: video,
               age_group: "AGE_18_24", gender: "FEMALE",
               date: Date.current, viewer_percentage: 0.4)
        get video_analytics_path(video)
        expect(response.body).to include("demographics")
      end
    end

    context "refresh buttons" do
      it "renders both [refresh now] and [refresh retention] buttons" do
        get video_analytics_path(video)
        expect(response.body).to include("refresh now")
        expect(response.body).to include("refresh retention")
      end
    end

    # Phase 26 §01g — viewer-time heatmap.
    context "viewer-time heatmap" do
      it "renders the heatmap section header" do
        get video_analytics_path(video)
        expect(response.body).to include("viewer-time heatmap")
      end

      it "renders the empty-state copy when no buckets exist" do
        get video_analytics_path(video)
        expect(response.body).to include("no viewer-time data yet")
      end

      it "renders the grid when buckets exist" do
        create(:video_viewer_time_bucket, video: video,
               day_of_week_utc: 3, hour_of_day_utc: 14,
               view_count: 50, watch_time_seconds: 3000)
        get video_analytics_path(video)
        expect(response.body).to include("viewer-time-heatmap__grid")
      end
    end
  end
end
