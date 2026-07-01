# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channel::Youtube::AnalyticsClient, type: :service do
  let(:connection) { create(:youtube_connection) }
  let(:client)     { described_class.new(connection) }

  # Hand-built Analytics API response object mirroring the real
  # `Google::Apis::YoutubeAnalyticsV2::QueryResponse` shape.
  def build_column_header(name)
    instance_double(
      Google::Apis::YoutubeAnalyticsV2::ResultTableColumnHeader,
      name: name
    )
  end

  def build_analytics_response(column_names, rows)
    headers = column_names.map { |n| build_column_header(n) }
    instance_double(
      Google::Apis::YoutubeAnalyticsV2::QueryResponse,
      column_headers: headers,
      rows: rows
    )
  end

  # Canonical column order: video, views, estimatedMinutesWatched,
  # subscribersGained, subscribersLost.
  let(:canonical_columns) { %w[video views estimatedMinutesWatched subscribersGained subscribersLost] }
  let(:canonical_rows) do
    [
      [ "dQw4w9WgXcQ", 5000, 12_000, 30, 5 ],
      [ "abc123xyz45", 2000,  5_000, 10, 2 ]
    ]
  end
  let(:analytics_response) { build_analytics_response(canonical_columns, canonical_rows) }

  let(:analytics_svc) { instance_double(Google::Apis::YoutubeAnalyticsV2::YouTubeAnalyticsService) }

  before do
    allow(Channel::Youtube::ServiceFactory)
      .to receive(:analytics_service)
      .with(connection)
      .and_return(analytics_svc)
    allow(analytics_svc).to receive(:query_report).and_return(analytics_response)
  end

  describe "#top_videos" do
    subject(:result) do
      client.top_videos(
        channel_id: "UCtest123",
        start_date: "2000-01-01",
        end_date:   "2026-06-20"
      )
    end

    it "returns an array of normalized hashes with snake_case keys" do
      expect(result).to be_an(Array)
      expect(result.first.keys).to contain_exactly(
        :video_id, :views, :estimated_minutes_watched,
        :subscribers_gained, :subscribers_lost
      )
    end

    it "maps the first row correctly" do
      row = result.first
      expect(row[:video_id]).to eq("dQw4w9WgXcQ")
      expect(row[:views]).to eq(5000)
      expect(row[:estimated_minutes_watched]).to eq(12_000)
      expect(row[:subscribers_gained]).to eq(30)
      expect(row[:subscribers_lost]).to eq(5)
    end

    it "returns Integer values for all metric columns" do
      result.each do |row|
        expect(row[:views]).to be_an(Integer)
        expect(row[:estimated_minutes_watched]).to be_an(Integer)
        expect(row[:subscribers_gained]).to be_an(Integer)
        expect(row[:subscribers_lost]).to be_an(Integer)
      end
    end

    it "calls query_report with the expected ids, dimensions, and metrics" do
      expect(analytics_svc).to receive(:query_report).with(
        ids:         "channel==UCtest123",
        start_date:  "2000-01-01",
        end_date:    "2026-06-20",
        dimensions:  "video",
        metrics:     "views,estimatedMinutesWatched,subscribersGained,subscribersLost,likes",
        sort:        "-views",
        max_results: 200
      ).and_return(analytics_response)

      client.top_videos(channel_id: "UCtest123", start_date: "2000-01-01", end_date: "2026-06-20")
    end

    it "forwards a custom max_results to query_report" do
      expect(analytics_svc).to receive(:query_report).with(
        hash_including(max_results: 50)
      ).and_return(analytics_response)

      client.top_videos(channel_id: "UCtest123", start_date: "2000-01-01", end_date: "2026-06-20", max_results: 50)
    end

    it "accepts Date objects for start_date / end_date" do
      expect(analytics_svc).to receive(:query_report).with(
        hash_including(start_date: "2000-01-01", end_date: "2026-06-20")
      ).and_return(analytics_response)

      client.top_videos(
        channel_id: "UCtest123",
        start_date: Date.new(2000, 1, 1),
        end_date:   Date.new(2026, 6, 20)
      )
    end

    context "when column order is shuffled" do
      # The Analytics API does not guarantee column order. Verify mapping
      # is done by header name, not by position.
      let(:shuffled_columns) { %w[subscribersLost views video estimatedMinutesWatched subscribersGained] }
      # Rows rearranged to match the shuffled column order.
      let(:shuffled_rows) do
        [
          [ 5, 5000, "dQw4w9WgXcQ", 12_000, 30 ],
          [ 2, 2000, "abc123xyz45",  5_000, 10 ]
        ]
      end
      let(:analytics_response) { build_analytics_response(shuffled_columns, shuffled_rows) }

      it "still maps columns to the correct hash keys" do
        row = result.first
        expect(row[:video_id]).to eq("dQw4w9WgXcQ")
        expect(row[:views]).to eq(5000)
        expect(row[:estimated_minutes_watched]).to eq(12_000)
        expect(row[:subscribers_gained]).to eq(30)
        expect(row[:subscribers_lost]).to eq(5)
      end
    end

    context "when the response has no rows" do
      let(:analytics_response) { build_analytics_response(canonical_columns, nil) }

      it "returns an empty array" do
        expect(result).to eq([])
      end
    end

    context "when the response has no column headers" do
      let(:analytics_response) do
        instance_double(
          Google::Apis::YoutubeAnalyticsV2::QueryResponse,
          column_headers: nil,
          rows: canonical_rows
        )
      end

      it "returns an empty array" do
        expect(result).to eq([])
      end
    end
  end

  describe "token freshness" do
    it "refreshes an expired token before calling the Analytics API" do
      connection.update_columns(
        access_token: "stale",
        expires_at:   1.hour.ago
      )

      allow(Channel::Youtube::TokenRefresher).to receive(:call).with(connection) do
        connection.update_columns(access_token: "fresh", expires_at: 1.hour.from_now)
      end

      client.top_videos(channel_id: "UCtest123", start_date: "2000-01-01", end_date: "2026-06-20")

      expect(Channel::Youtube::TokenRefresher).to have_received(:call).with(connection)
    end

    it "does not call the token refresher when the token is still valid" do
      connection.update_columns(expires_at: 1.hour.from_now)

      allow(Channel::Youtube::TokenRefresher).to receive(:call)

      client.top_videos(channel_id: "UCtest123", start_date: "2000-01-01", end_date: "2026-06-20")

      expect(Channel::Youtube::TokenRefresher).not_to have_received(:call)
    end
  end

  describe "audit row" do
    it "tracks an ApiRequest row for analytics.reports.query" do
      expect {
        client.top_videos(channel_id: "UCtest123", start_date: "2000-01-01", end_date: "2026-06-20")
      }.to change {
        ApiRequest.youtube.where(endpoint: "analytics.reports.query").count
      }.by(1)
    end
  end

  describe "#query" do
    let(:query_columns) { %w[day views estimatedMinutesWatched] }
    let(:query_rows) do
      [
        [ "2026-06-01", 1500, 6_000 ],
        [ "2026-06-02", 2000, 7_500 ]
      ]
    end
    let(:query_response) { build_analytics_response(query_columns, query_rows) }

    before do
      allow(analytics_svc).to receive(:query_report).and_return(query_response)
    end

    subject(:result) do
      client.query(
        channel_id: "UCtest123",
        start_date: "2026-05-24",
        end_date:   "2026-06-21",
        metrics:    "views,estimatedMinutesWatched",
        dimensions: "day"
      )
    end

    it "returns an array of hashes with snake_case symbol keys from column names" do
      expect(result).to be_an(Array)
      expect(result.first.keys).to contain_exactly(:day, :views, :estimated_minutes_watched)
    end

    it "maps all rows correctly" do
      expect(result.size).to eq(2)
      expect(result.first[:day]).to eq("2026-06-01")
      expect(result.first[:views]).to eq(1500)
      expect(result.first[:estimated_minutes_watched]).to eq(6_000)
    end

    it "preserves Integer values for integer metrics" do
      result.each do |row|
        expect(row[:views]).to be_an(Integer)
        expect(row[:estimated_minutes_watched]).to be_an(Integer)
      end
    end

    it "preserves Float values for float metrics" do
      float_response = build_analytics_response(
        %w[ageGroup gender viewerPercentage],
        [ [ "age18-24", "MALE", 34.5 ], [ "age25-34", "FEMALE", 22.1 ] ]
      )
      allow(analytics_svc).to receive(:query_report).and_return(float_response)

      rows = client.query(
        channel_id: "UCtest123",
        start_date: "2026-01-01",
        end_date:   "2026-06-21",
        metrics:    "viewerPercentage",
        dimensions: "ageGroup,gender"
      )
      expect(rows.first[:viewer_percentage]).to be_a(Float)
      expect(rows.first[:viewer_percentage]).to eq(34.5)
      expect(rows.first[:age_group]).to be_a(String)
    end

    it "maps columns to correct keys regardless of column order" do
      shuffled_response = build_analytics_response(
        %w[estimatedMinutesWatched day views],
        [ [ 6_000, "2026-06-01", 1500 ], [ 7_500, "2026-06-02", 2000 ] ]
      )
      allow(analytics_svc).to receive(:query_report).and_return(shuffled_response)

      rows = client.query(
        channel_id: "UCtest123",
        start_date: "2026-05-24",
        end_date:   "2026-06-21",
        metrics:    "views,estimatedMinutesWatched",
        dimensions: "day"
      )
      expect(rows.first[:day]).to eq("2026-06-01")
      expect(rows.first[:views]).to eq(1500)
      expect(rows.first[:estimated_minutes_watched]).to eq(6_000)
    end

    it "passes ids, dates, metrics, and dimensions to query_report" do
      expect(analytics_svc).to receive(:query_report).with(
        ids:        "channel==UCtest123",
        start_date: "2026-05-24",
        end_date:   "2026-06-21",
        metrics:    "views,estimatedMinutesWatched",
        dimensions: "day"
      ).and_return(query_response)

      result
    end

    it "omits nil optional params from the query_report call" do
      expect(analytics_svc).to receive(:query_report).with(
        ids:        "channel==UCtest123",
        start_date: "2026-05-24",
        end_date:   "2026-06-21",
        metrics:    "views"
      ).and_return(query_response)

      client.query(
        channel_id: "UCtest123",
        start_date: "2026-05-24",
        end_date:   "2026-06-21",
        metrics:    "views"
      )
    end

    it "forwards sort and max_results when provided" do
      expect(analytics_svc).to receive(:query_report).with(
        hash_including(sort: "-views", max_results: 10)
      ).and_return(query_response)

      client.query(
        channel_id:  "UCtest123",
        start_date:  "2026-01-01",
        end_date:    "2026-06-21",
        metrics:     "views,estimatedMinutesWatched",
        dimensions:  "country",
        sort:        "-views",
        max_results: 10
      )
    end

    it "forwards filters when provided" do
      expect(analytics_svc).to receive(:query_report).with(
        hash_including(filters: "country==US")
      ).and_return(query_response)

      client.query(
        channel_id: "UCtest123",
        start_date: "2026-01-01",
        end_date:   "2026-06-21",
        metrics:    "views",
        filters:    "country==US"
      )
    end

    context "when the response has no rows" do
      let(:query_response) { build_analytics_response(query_columns, nil) }

      it "returns an empty array" do
        expect(result).to eq([])
      end
    end

    context "when the response has no column headers" do
      let(:query_response) do
        instance_double(
          Google::Apis::YoutubeAnalyticsV2::QueryResponse,
          column_headers: nil,
          rows:           query_rows
        )
      end

      it "returns an empty array" do
        expect(result).to eq([])
      end
    end
  end

  describe "error handling" do
    context "when Google raises AuthorizationError (401)" do
      before do
        allow(analytics_svc).to receive(:query_report)
          .and_raise(Google::Apis::AuthorizationError.new("invalid credentials"))
      end

      it "attempts to refresh the token once then raises NeedsReauthError" do
        allow(Channel::Youtube::TokenRefresher).to receive(:call)
          .with(connection)
          .and_raise(Channel::Youtube::NeedsReauthError.new("invalid_grant"))

        expect {
          client.top_videos(channel_id: "UCtest123", start_date: "2000-01-01", end_date: "2026-06-20")
        }.to raise_error(Channel::Youtube::NeedsReauthError)
      end
    end

    context "when Google raises ServerError (5xx)" do
      before do
        allow(analytics_svc).to receive(:query_report)
          .and_raise(Google::Apis::ServerError.new("upstream error"))
      end

      it "raises TransientError after MAX_5XX_ATTEMPTS" do
        expect {
          client.top_videos(channel_id: "UCtest123", start_date: "2000-01-01", end_date: "2026-06-20")
        }.to raise_error(Channel::Youtube::TransientError)
      end
    end

    context "when the quota is exhausted before the call" do
      before do
        # Fill up the analytics budget with logged calls.
        allow(Channel::Youtube::Quota).to receive(:analytics_budget_remaining)
          .with(connection)
          .and_return(0)
      end

      it "raises QuotaExhaustedError without calling the Analytics API" do
        expect(analytics_svc).not_to receive(:query_report)
        expect {
          client.top_videos(channel_id: "UCtest123", start_date: "2000-01-01", end_date: "2026-06-20")
        }.to raise_error(Channel::Youtube::QuotaExhaustedError)
      end
    end
  end

  # -------------------------------------------------------------------------
  # Per-report convenience methods (all delegate to #query → query_report)
  # -------------------------------------------------------------------------

  describe "#scalars" do
    let(:scalar_columns) do
      %w[views estimatedMinutesWatched averageViewDuration averageViewPercentage
         subscribersGained subscribersLost likes dislikes comments]
    end
    let(:scalar_row) { [ 10_000, 40_000, 240, 65.5, 80, 12, 300, 5, 45 ] }
    let(:scalar_response) { build_analytics_response(scalar_columns, [ scalar_row ]) }

    before { allow(analytics_svc).to receive(:query_report).and_return(scalar_response) }

    it "calls query_report with the correct metrics and no dimensions" do
      expect(analytics_svc).to receive(:query_report).with(
        ids:        "channel==UCtest123",
        start_date: "2026-01-01",
        end_date:   "2026-06-21",
        metrics:    Channel::Youtube::AnalyticsClient::SCALAR_METRICS
      ).and_return(scalar_response)

      client.scalars(channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21")
    end

    it "returns a single Hash with snake_case symbol keys" do
      result = client.scalars(channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21")
      expect(result).to be_a(Hash)
      expect(result.keys).to contain_exactly(
        :views, :estimated_minutes_watched, :average_view_duration, :average_view_percentage,
        :subscribers_gained, :subscribers_lost, :likes, :dislikes, :comments
      )
      expect(result[:views]).to eq(10_000)
      expect(result[:average_view_percentage]).to be_a(Float)
    end

    it "returns {} when the API returns no rows" do
      allow(analytics_svc).to receive(:query_report)
        .and_return(build_analytics_response(scalar_columns, nil))

      result = client.scalars(channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21")
      expect(result).to eq({})
    end

    context "with a video list" do
      it "passes the video filter to query_report" do
        expect(analytics_svc).to receive(:query_report).with(
          hash_including(filters: "video==vid1,vid2")
        ).and_return(scalar_response)

        client.scalars(
          channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21",
          videos: %w[vid1 vid2]
        )
      end
    end

    context "with videos: nil (channel-level)" do
      it "omits the filters param from query_report" do
        expect(analytics_svc).to receive(:query_report).with(
          hash_excluding(:filters)
        ).and_return(scalar_response)

        client.scalars(channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21")
      end
    end
  end

  describe "#daily" do
    let(:daily_columns) { %w[day views estimatedMinutesWatched] }
    let(:daily_rows) do
      [ [ "2026-06-19", 800, 3_200 ], [ "2026-06-20", 950, 3_800 ] ]
    end
    let(:daily_response) { build_analytics_response(daily_columns, daily_rows) }

    before { allow(analytics_svc).to receive(:query_report).and_return(daily_response) }

    it "calls query_report with dimensions: day and the correct metrics" do
      expect(analytics_svc).to receive(:query_report).with(
        ids:        "channel==UCtest123",
        start_date: "2026-06-01",
        end_date:   "2026-06-21",
        metrics:    "views,estimatedMinutesWatched,averageViewDuration,averageViewPercentage,subscribersGained,subscribersLost,comments",
        dimensions: "day"
      ).and_return(daily_response)

      client.daily(channel_id: "UCtest123", start_date: "2026-06-01", end_date: "2026-06-21")
    end

    it "returns an Array of Hashes with :day, :views, :estimated_minutes_watched" do
      result = client.daily(channel_id: "UCtest123", start_date: "2026-06-01", end_date: "2026-06-21")
      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result.first.keys).to contain_exactly(:day, :views, :estimated_minutes_watched)
      expect(result.first[:day]).to eq("2026-06-19")
    end

    context "with a video list" do
      it "includes the video filter" do
        expect(analytics_svc).to receive(:query_report).with(
          hash_including(filters: "video==abc123")
        ).and_return(daily_response)

        client.daily(
          channel_id: "UCtest123", start_date: "2026-06-01", end_date: "2026-06-21",
          videos: [ "abc123" ]
        )
      end
    end

    context "with videos: nil" do
      it "omits filters" do
        expect(analytics_svc).to receive(:query_report).with(
          hash_excluding(:filters)
        ).and_return(daily_response)

        client.daily(channel_id: "UCtest123", start_date: "2026-06-01", end_date: "2026-06-21")
      end
    end
  end

  describe "#by_country" do
    let(:country_columns) { %w[country views estimatedMinutesWatched averageViewDuration] }
    let(:country_rows) do
      [ [ "US", 5_000, 20_000, 240 ], [ "GB", 1_200, 4_800, 200 ] ]
    end
    let(:country_response) { build_analytics_response(country_columns, country_rows) }

    before { allow(analytics_svc).to receive(:query_report).and_return(country_response) }

    it "calls query_report with correct metrics, dimensions, sort, and default max_results" do
      expect(analytics_svc).to receive(:query_report).with(
        ids:         "channel==UCtest123",
        start_date:  "2026-01-01",
        end_date:    "2026-06-21",
        metrics:     "views,estimatedMinutesWatched,averageViewDuration",
        dimensions:  "country",
        sort:        "-views",
        max_results: 10
      ).and_return(country_response)

      client.by_country(channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21")
    end

    it "returns an Array with country, views, estimated_minutes_watched, average_view_duration keys" do
      result = client.by_country(channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21")
      expect(result).to be_an(Array)
      expect(result.first.keys).to contain_exactly(
        :country, :views, :estimated_minutes_watched, :average_view_duration
      )
      expect(result.first[:country]).to eq("US")
    end

    it "forwards a custom max_results" do
      expect(analytics_svc).to receive(:query_report).with(
        hash_including(max_results: 25)
      ).and_return(country_response)

      client.by_country(
        channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21",
        max_results: 25
      )
    end

    context "with a video list" do
      it "includes the video filter" do
        expect(analytics_svc).to receive(:query_report).with(
          hash_including(filters: "video==v1,v2,v3")
        ).and_return(country_response)

        client.by_country(
          channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21",
          videos: %w[v1 v2 v3]
        )
      end
    end
  end

  describe "#by_device" do
    let(:device_columns) { %w[deviceType views estimatedMinutesWatched] }
    let(:device_rows) do
      [ [ "DESKTOP", 4_000, 16_000 ], [ "MOBILE", 6_000, 24_000 ] ]
    end
    let(:device_response) { build_analytics_response(device_columns, device_rows) }

    before { allow(analytics_svc).to receive(:query_report).and_return(device_response) }

    it "calls query_report with dimensions: deviceType and the correct metrics" do
      expect(analytics_svc).to receive(:query_report).with(
        ids:        "channel==UCtest123",
        start_date: "2026-01-01",
        end_date:   "2026-06-21",
        metrics:    "views,estimatedMinutesWatched",
        dimensions: "deviceType"
      ).and_return(device_response)

      client.by_device(channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21")
    end

    it "returns an Array with device_type, views, estimated_minutes_watched keys" do
      result = client.by_device(channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21")
      expect(result).to be_an(Array)
      expect(result.first.keys).to contain_exactly(:device_type, :views, :estimated_minutes_watched)
      expect(result.first[:device_type]).to eq("DESKTOP")
    end

    context "with videos: nil" do
      it "omits filters" do
        expect(analytics_svc).to receive(:query_report).with(
          hash_excluding(:filters)
        ).and_return(device_response)

        client.by_device(channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21")
      end
    end
  end

  describe "#by_subscribed_status" do
    let(:sub_columns) { %w[subscribedStatus views estimatedMinutesWatched] }
    let(:sub_rows) do
      [ [ "SUBSCRIBED", 8_000, 32_000 ], [ "UNSUBSCRIBED", 2_000, 8_000 ] ]
    end
    let(:sub_response) { build_analytics_response(sub_columns, sub_rows) }

    before { allow(analytics_svc).to receive(:query_report).and_return(sub_response) }

    it "calls query_report with dimensions: subscribedStatus and the correct metrics" do
      expect(analytics_svc).to receive(:query_report).with(
        ids:        "channel==UCtest123",
        start_date: "2026-01-01",
        end_date:   "2026-06-21",
        metrics:    "views,estimatedMinutesWatched",
        dimensions: "subscribedStatus"
      ).and_return(sub_response)

      client.by_subscribed_status(channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21")
    end

    it "returns an Array with subscribed_status, views, estimated_minutes_watched keys" do
      result = client.by_subscribed_status(
        channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21"
      )
      expect(result).to be_an(Array)
      expect(result.first.keys).to contain_exactly(:subscribed_status, :views, :estimated_minutes_watched)
      expect(result.first[:subscribed_status]).to eq("SUBSCRIBED")
    end

    context "with a video list" do
      it "includes the video filter" do
        expect(analytics_svc).to receive(:query_report).with(
          hash_including(filters: "video==myVid")
        ).and_return(sub_response)

        client.by_subscribed_status(
          channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21",
          videos: [ "myVid" ]
        )
      end
    end
  end

  describe "#demographics" do
    let(:demo_columns) { %w[ageGroup gender viewerPercentage] }
    let(:demo_rows) do
      [ [ "age18-24", "MALE", 28.5 ], [ "age18-24", "FEMALE", 21.3 ], [ "age25-34", "MALE", 18.7 ] ]
    end
    let(:demo_response) { build_analytics_response(demo_columns, demo_rows) }

    before { allow(analytics_svc).to receive(:query_report).and_return(demo_response) }

    it "calls query_report with dimensions: ageGroup,gender and metrics: viewerPercentage" do
      expect(analytics_svc).to receive(:query_report).with(
        ids:        "channel==UCtest123",
        start_date: "2026-01-01",
        end_date:   "2026-06-21",
        metrics:    "viewerPercentage",
        dimensions: "ageGroup,gender"
      ).and_return(demo_response)

      client.demographics(channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21")
    end

    it "returns an Array with age_group, gender, viewer_percentage keys" do
      result = client.demographics(
        channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21"
      )
      expect(result).to be_an(Array)
      expect(result.first.keys).to contain_exactly(:age_group, :gender, :viewer_percentage)
    end

    it "preserves Float values for viewer_percentage" do
      result = client.demographics(
        channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21"
      )
      expect(result.first[:viewer_percentage]).to be_a(Float)
      expect(result.first[:viewer_percentage]).to eq(28.5)
    end

    it "returns String values for dimension columns" do
      result = client.demographics(
        channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21"
      )
      expect(result.first[:age_group]).to be_a(String)
      expect(result.first[:gender]).to be_a(String)
    end

    context "with videos: nil" do
      it "omits filters" do
        expect(analytics_svc).to receive(:query_report).with(
          hash_excluding(:filters)
        ).and_return(demo_response)

        client.demographics(channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21")
      end
    end
  end

  describe "#retention" do
    let(:retention_columns) { %w[elapsedVideoTimeRatio audienceWatchRatio relativeRetentionPerformance] }
    let(:retention_rows) do
      [
        [ 0.0,  1.0,  1.2 ],
        [ 0.1,  0.85, 1.05 ],
        [ 0.5,  0.60, 0.95 ],
        [ 1.0,  0.10, 0.80 ]
      ]
    end
    let(:retention_response) { build_analytics_response(retention_columns, retention_rows) }

    before { allow(analytics_svc).to receive(:query_report).and_return(retention_response) }

    it "calls query_report with the correct metrics, dimensions, and single-video filter" do
      expect(analytics_svc).to receive(:query_report).with(
        ids:        "channel==UCtest123",
        start_date: "2026-01-01",
        end_date:   "2026-06-21",
        metrics:    "audienceWatchRatio,relativeRetentionPerformance",
        dimensions: "elapsedVideoTimeRatio",
        filters:    "video==dQw4w9WgXcQ"
      ).and_return(retention_response)

      client.retention(
        channel_id: "UCtest123",
        start_date: "2026-01-01",
        end_date:   "2026-06-21",
        video:      "dQw4w9WgXcQ"
      )
    end

    it "returns an Array of Hashes with elapsed_video_time_ratio, audience_watch_ratio, relative_retention_performance" do
      result = client.retention(
        channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21",
        video: "dQw4w9WgXcQ"
      )
      expect(result).to be_an(Array)
      expect(result.first.keys).to contain_exactly(
        :elapsed_video_time_ratio, :audience_watch_ratio, :relative_retention_performance
      )
    end

    it "preserves Float values for all three columns" do
      result = client.retention(
        channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21",
        video: "dQw4w9WgXcQ"
      )
      expect(result.first[:elapsed_video_time_ratio]).to eq(0.0)
      expect(result.first[:audience_watch_ratio]).to eq(1.0)
      expect(result.first[:relative_retention_performance]).to eq(1.2)
    end
  end

  describe "video_filter (via public interface)" do
    let(:scalar_columns) do
      %w[views estimatedMinutesWatched averageViewDuration averageViewPercentage
         subscribersGained subscribersLost likes dislikes comments]
    end
    let(:scalar_response) { build_analytics_response(scalar_columns, [ Array.new(9, 0) ]) }

    before { allow(analytics_svc).to receive(:query_report).and_return(scalar_response) }

    it "builds a comma-joined filter for multiple video IDs" do
      expect(analytics_svc).to receive(:query_report).with(
        hash_including(filters: "video==aaa,bbb,ccc")
      ).and_return(scalar_response)

      client.scalars(
        channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21",
        videos: %w[aaa bbb ccc]
      )
    end

    it "builds a single-element filter without a trailing comma" do
      expect(analytics_svc).to receive(:query_report).with(
        hash_including(filters: "video==onlyone")
      ).and_return(scalar_response)

      client.scalars(
        channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21",
        videos: [ "onlyone" ]
      )
    end

    it "omits filters entirely when videos: nil (channel-level query)" do
      expect(analytics_svc).to receive(:query_report).with(
        hash_excluding(:filters)
      ).and_return(scalar_response)

      client.scalars(
        channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21",
        videos: nil
      )
    end

    it "omits filters when videos: is an empty array" do
      expect(analytics_svc).to receive(:query_report).with(
        hash_excluding(:filters)
      ).and_return(scalar_response)

      client.scalars(
        channel_id: "UCtest123", start_date: "2026-01-01", end_date: "2026-06-21",
        videos: []
      )
    end
  end
end
