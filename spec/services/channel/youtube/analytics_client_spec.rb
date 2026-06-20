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
        metrics:     "views,estimatedMinutesWatched,subscribersGained,subscribersLost",
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
end
