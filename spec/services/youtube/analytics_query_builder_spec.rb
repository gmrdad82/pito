require "rails_helper"

# Phase 13.2 — Analytics sync engine. Pure-function query builder
# spec — no DB, no network. Asserts the params hash returned for
# every Note 3 query (C1..C5, V1..V8) matches the documented
# metric set / dimension / filter / sort / max_results shape.
RSpec.describe Youtube::AnalyticsQueryBuilder do
  let(:youtube_channel_id) { "UCabcdefghijklmnopqrstuv" }
  let(:youtube_video_id)   { "dQw4w9WgXcQ" }
  let(:today)              { Date.new(2026, 5, 10) }
  let(:from)               { today - 3 }
  let(:to)                 { today - 1 }

  describe ".channel_daily_params" do
    let(:params) do
      described_class.channel_daily_params(
        channel_youtube_id: youtube_channel_id, from: from, to: to
      )
    end

    it "builds C1 params with the documented daily metric set" do
      metrics = params[:metrics].split(",")
      %w[
        views estimatedMinutesWatched estimatedRedMinutesWatched
        averageViewDuration likes dislikes comments shares
        subscribersGained subscribersLost
        videosAddedToPlaylists videosRemovedFromPlaylists
        videoThumbnailImpressions cardImpressions cardClicks
        cardTeaserImpressions cardTeaserClicks engagedViews redViews
      ].each { |m| expect(metrics).to include(m) }
    end

    it "uses dimensions=day" do
      expect(params[:dimensions]).to eq("day")
    end

    it "uses ids=channel==<youtube_channel_id>" do
      expect(params[:ids]).to eq("channel==#{youtube_channel_id}")
    end

    it "formats start_date / end_date as YYYY-MM-DD" do
      expect(params[:start_date]).to eq(from.strftime("%Y-%m-%d"))
      expect(params[:end_date]).to eq(to.strftime("%Y-%m-%d"))
    end

    it "omits non-summable metrics like averageViewPercentage" do
      expect(params[:metrics].split(",")).not_to include("averageViewPercentage")
    end

    it "omits revenue metrics when monetization disabled" do
      metrics = params[:metrics].split(",")
      %w[estimatedRevenue estimatedAdRevenue estimatedRedPartnerRevenue grossRevenue
         adImpressions monetizedPlaybacks].each do |m|
        expect(metrics).not_to include(m)
      end
    end

    it "appends revenue metrics when monetization enabled" do
      enabled = described_class.channel_daily_params(
        channel_youtube_id: youtube_channel_id, from: from, to: to,
        monetization_enabled: true
      )
      metrics = enabled[:metrics].split(",")
      %w[estimatedRevenue estimatedAdRevenue estimatedRedPartnerRevenue grossRevenue
         adImpressions monetizedPlaybacks].each do |m|
        expect(metrics).to include(m)
      end
    end
  end

  describe ".channel_window_summary_params" do
    let(:params) do
      described_class.channel_window_summary_params(
        channel_youtube_id: youtube_channel_id, window: "7d", today: today
      )
    end

    it "builds C2 params with no dimensions" do
      expect(params[:dimensions]).to be_nil
    end

    it "appends the four non-summable ratios" do
      metrics = params[:metrics].split(",")
      %w[averageViewPercentage videoThumbnailImpressionsClickRate
         cardClickRate cardTeaserClickRate].each do |m|
        expect(metrics).to include(m)
      end
    end

    it "appends revenue ratios (cpm, playbackBasedCpm) when monetization enabled" do
      enabled = described_class.channel_window_summary_params(
        channel_youtube_id: youtube_channel_id, window: "7d", today: today,
        monetization_enabled: true
      )
      metrics = enabled[:metrics].split(",")
      expect(metrics).to include("cpm")
      expect(metrics).to include("playbackBasedCpm")
    end

    it "computes window_start from window value" do
      expect(described_class.window_range("7d", today)).to eq([ today - 7, today - 1 ])
      expect(described_class.window_range("28d", today)).to eq([ today - 28, today - 1 ])
      expect(described_class.window_range("90d", today)).to eq([ today - 90, today - 1 ])
      lifetime_start, lifetime_end = described_class.window_range("lifetime", today)
      expect(lifetime_start).to eq(Date.new(2005, 2, 14))
      expect(lifetime_end).to eq(today - 1)
    end

    it "rejects unknown window value" do
      expect {
        described_class.channel_window_summary_params(
          channel_youtube_id: youtube_channel_id, window: "14d", today: today
        )
      }.to raise_error(ArgumentError, /unknown window/)
    end
  end

  describe ".top_videos_params" do
    it "uses dimensions=video" do
      params = described_class.top_videos_params(
        channel_youtube_id: youtube_channel_id, window: "7d", today: today
      )
      expect(params[:dimensions]).to eq("video")
    end

    it "appends sort=-estimatedMinutesWatched" do
      params = described_class.top_videos_params(
        channel_youtube_id: youtube_channel_id, window: "7d", today: today
      )
      expect(params[:sort]).to eq("-estimatedMinutesWatched")
    end

    it "caps maxResults to 50 by default" do
      params = described_class.top_videos_params(
        channel_youtube_id: youtube_channel_id, window: "7d", today: today
      )
      expect(params[:max_results]).to eq(50)
    end

    it "respects a custom limit up to 200" do
      params = described_class.top_videos_params(
        channel_youtube_id: youtube_channel_id, window: "7d", today: today, limit: 200
      )
      expect(params[:max_results]).to eq(200)
    end

    it "rejects limit > 200" do
      expect {
        described_class.top_videos_params(
          channel_youtube_id: youtube_channel_id, window: "7d", today: today, limit: 201
        )
      }.to raise_error(ArgumentError, /limit must be between/)
    end
  end

  describe ".channel_geography_params (no-op stub today)" do
    it "builds C4 params with dimensions=country" do
      params = described_class.channel_geography_params(
        channel_youtube_id: youtube_channel_id, from: from, to: to
      )
      expect(params[:dimensions]).to eq("country")
    end

    it "uses ids=channel==<id>" do
      params = described_class.channel_geography_params(
        channel_youtube_id: youtube_channel_id, from: from, to: to
      )
      expect(params[:ids]).to eq("channel==#{youtube_channel_id}")
    end
  end

  describe ".channel_demographics_params" do
    it "builds C5 params with dimensions=ageGroup,gender" do
      params = described_class.channel_demographics_params(
        channel_youtube_id: youtube_channel_id, from: from, to: to
      )
      expect(params[:dimensions]).to eq("ageGroup,gender")
    end

    it "uses metrics=viewerPercentage" do
      params = described_class.channel_demographics_params(
        channel_youtube_id: youtube_channel_id, from: from, to: to
      )
      expect(params[:metrics]).to eq("viewerPercentage")
    end
  end

  describe ".video_daily_params" do
    let(:params) do
      described_class.video_daily_params(
        video_youtube_id: youtube_video_id, from: from, to: to
      )
    end

    it "appends filters=video==<youtube_video_id>" do
      expect(params[:filters]).to eq("video==#{youtube_video_id}")
    end

    it "shares the C1 metric / dimension shape" do
      expect(params[:dimensions]).to eq("day")
      metrics = params[:metrics].split(",")
      expect(metrics).to include("views")
      expect(metrics).to include("estimatedMinutesWatched")
      expect(metrics).not_to include("averageViewPercentage")
    end
  end

  describe ".video_window_summary_params" do
    let(:params) do
      described_class.video_window_summary_params(
        video_youtube_id: youtube_video_id, window: "28d", today: today
      )
    end

    it "appends filters=video==<id>" do
      expect(params[:filters]).to eq("video==#{youtube_video_id}")
    end

    it "shares the C2 metric shape" do
      metrics = params[:metrics].split(",")
      expect(metrics).to include("averageViewPercentage")
      expect(metrics).to include("videoThumbnailImpressionsClickRate")
    end
  end

  describe ".video_by_country_params" do
    let(:params) do
      described_class.video_by_country_params(
        video_youtube_id: youtube_video_id, from: from, to: to
      )
    end

    it "appends filters=video==<id>" do
      expect(params[:filters]).to eq("video==#{youtube_video_id}")
    end

    it "uses dimensions=country" do
      expect(params[:dimensions]).to eq("country")
    end

    it "uses metrics=views,estimatedMinutesWatched,averageViewDuration,averageViewPercentage" do
      metrics = params[:metrics].split(",")
      %w[views estimatedMinutesWatched averageViewDuration averageViewPercentage].each do |m|
        expect(metrics).to include(m)
      end
    end
  end

  describe ".video_by_device_type_params" do
    it "uses dimensions=deviceType (single)" do
      params = described_class.video_by_device_type_params(
        video_youtube_id: youtube_video_id, from: from, to: to
      )
      expect(params[:dimensions]).to eq("deviceType")
    end
  end

  describe ".video_by_operating_system_params" do
    it "uses dimensions=operatingSystem (single)" do
      params = described_class.video_by_operating_system_params(
        video_youtube_id: youtube_video_id, from: from, to: to
      )
      expect(params[:dimensions]).to eq("operatingSystem")
    end
  end

  describe ".video_by_traffic_source_params" do
    it "uses dimensions=insightTrafficSourceType" do
      params = described_class.video_by_traffic_source_params(
        video_youtube_id: youtube_video_id, from: from, to: to
      )
      expect(params[:dimensions]).to eq("insightTrafficSourceType")
    end
  end

  describe ".video_by_subscribed_status_params" do
    it "uses dimensions=subscribedStatus" do
      params = described_class.video_by_subscribed_status_params(
        video_youtube_id: youtube_video_id, from: from, to: to
      )
      expect(params[:dimensions]).to eq("subscribedStatus")
    end
  end

  describe ".video_retention_params (V7)" do
    let(:params) { described_class.video_retention_params(video_youtube_id: youtube_video_id) }

    it "uses dimensions=elapsedVideoTimeRatio" do
      expect(params[:dimensions]).to eq("elapsedVideoTimeRatio")
    end

    it "uses the documented retention metric set" do
      metrics = params[:metrics].split(",")
      %w[audienceWatchRatio relativeRetentionPerformance startedWatching stoppedWatching].each do |m|
        expect(metrics).to include(m)
      end
    end

    it "rejects multiple video IDs (array)" do
      expect {
        described_class.video_retention_params(video_youtube_id: %w[id1 id2])
      }.to raise_error(ArgumentError, /single video filter/)
    end

    it "rejects comma-joined video IDs" do
      expect {
        described_class.video_retention_params(video_youtube_id: "id1,id2")
      }.to raise_error(ArgumentError, /single video filter/)
    end
  end

  describe ".video_demographics_params (V8)" do
    let(:params) do
      described_class.video_demographics_params(
        video_youtube_id: youtube_video_id, from: from, to: to
      )
    end

    it "uses dimensions=ageGroup,gender" do
      expect(params[:dimensions]).to eq("ageGroup,gender")
    end

    it "uses metrics=viewerPercentage" do
      expect(params[:metrics]).to eq("viewerPercentage")
    end
  end

  describe ".assert_compatible! (mutual exclusion)" do
    it "raises when liveOrOnDemand + averageViewPercentage are both requested" do
      expect {
        described_class.assert_compatible!(
          metrics: "views,averageViewPercentage",
          dimensions: "day,liveOrOnDemand"
        )
      }.to raise_error(ArgumentError, /mutually exclusive/)
    end

    it "raises when day + month are both requested as time dimensions" do
      expect {
        described_class.assert_compatible!(
          metrics: "views",
          dimensions: "day,month"
        )
      }.to raise_error(ArgumentError, /mutually exclusive.*day.*month/)
    end
  end
end
