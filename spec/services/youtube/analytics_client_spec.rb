require "rails_helper"
require "ostruct"

# Phase 13.2 — Analytics sync engine. Spec for `Youtube::AnalyticsClient`.
# Stubs the Google service via `instance_double` (mirrors
# `Youtube::Client`'s spec strategy — exercises the wrapper logic, not
# the gem's HTTP serialization).
RSpec.describe Youtube::AnalyticsClient do
  let(:user)       { create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel)    { create(:channel, :connected, youtube_connection: connection) }
  let(:video)      { create(:video, channel: channel, youtube_video_id: "dQw4w9WgXcQ") }
  let(:today)      { Date.new(2026, 5, 10) }
  let(:from)       { today - 3 }
  let(:to)         { today - 1 }

  let(:svc) { instance_double(Google::Apis::YoutubeAnalyticsV2::YouTubeAnalyticsService) }

  before do
    allow(Google::Apis::YoutubeAnalyticsV2::YouTubeAnalyticsService).to receive(:new).and_return(svc)
    allow(svc).to receive(:authorization=)
  end

  def stub_query(headers:, rows:)
    response = OpenStruct.new(
      column_headers: headers.map { |name| OpenStruct.new(name: name) },
      rows: rows
    )
    allow(svc).to receive(:query_report).and_return(response)
  end

  def stub_query_to_raise(error)
    allow(svc).to receive(:query_report).and_raise(error)
  end

  describe "construction" do
    it "accepts a YoutubeConnection" do
      client = described_class.new(connection: connection)
      expect(client.connection).to eq(connection)
    end

    it "raises when connection is nil" do
      expect { described_class.new(connection: nil) }.to raise_error(ArgumentError)
    end
  end

  describe "happy path — channel_daily" do
    before do
      stub_query(
        headers: %w[day views estimatedMinutesWatched],
        rows: [ [ "2026-05-09", 1000, 200 ] ]
      )
    end

    it "returns parsed rows on a 200 response" do
      result = described_class.new(connection: connection).channel_daily(
        channel: channel, from: from, to: to
      )
      expect(result[:rows]).to eq([ [ "2026-05-09", 1000, 200 ] ])
      expect(result[:column_headers].map { |h| h[:name] }).to eq(%w[day views estimatedMinutesWatched])
    end

    it "writes a youtube_api_calls audit row with outcome: 'succeeded'" do
      expect {
        described_class.new(connection: connection).channel_daily(
          channel: channel, from: from, to: to
        )
      }.to change { YoutubeApiCall.unscoped.count }.by(1)

      row = YoutubeApiCall.unscoped.last
      expect(row.outcome).to eq("succeeded")
    end

    it "writes the row with client_kind: 'analytics_v2'" do
      described_class.new(connection: connection).channel_daily(
        channel: channel, from: from, to: to
      )
      row = YoutubeApiCall.unscoped.last
      expect(row.client_kind).to eq("analytics_v2")
    end

    it "writes the request's dimensions and metrics into the audit row" do
      described_class.new(connection: connection).channel_daily(
        channel: channel, from: from, to: to
      )
      row = YoutubeApiCall.unscoped.last
      payload = JSON.parse(row.error_message)
      expect(payload["dimensions"]).to eq("day")
      expect(payload["metrics"]).to include("views")
      expect(payload["metrics"]).to include("estimatedMinutesWatched")
      expect(payload["query_label"]).to eq("C1.channel_daily")
    end

    it "captures duration_ms (latency)" do
      described_class.new(connection: connection).channel_daily(
        channel: channel, from: from, to: to
      )
      row = YoutubeApiCall.unscoped.last
      expect(row.duration_ms).to be_a(Integer)
      expect(row.duration_ms).to be >= 0
    end
  end

  describe "happy path — every method" do
    before do
      stub_query(headers: %w[day views], rows: [ [ "2026-05-09", 100 ] ])
    end

    let(:client) { described_class.new(connection: connection) }

    it "channel_window_summary returns parsed rows" do
      stub_query(headers: %w[views], rows: [ [ 5000 ] ])
      result = client.channel_window_summary(channel: channel, window: "7d", today: today)
      expect(result[:rows].first).to eq([ 5000 ])
    end

    it "top_videos returns parsed rows" do
      stub_query(headers: %w[video views], rows: [ [ "abc", 100 ] ])
      result = client.top_videos(channel: channel, window: "7d", today: today)
      expect(result[:rows].first).to eq([ "abc", 100 ])
    end

    it "video_daily returns parsed rows" do
      stub_query(headers: %w[day views], rows: [ [ "2026-05-09", 100 ] ])
      result = client.video_daily(video: video, from: from, to: to)
      expect(result[:rows].first).to eq([ "2026-05-09", 100 ])
    end

    it "video_window_summary returns parsed rows" do
      stub_query(headers: %w[views], rows: [ [ 100 ] ])
      result = client.video_window_summary(video: video, window: "7d", today: today)
      expect(result[:rows].first).to eq([ 100 ])
    end

    it "video_by_country returns parsed rows" do
      stub_query(headers: %w[country views], rows: [ [ "US", 100 ] ])
      result = client.video_by_country(video: video, from: from, to: to)
      expect(result[:rows].first).to eq([ "US", 100 ])
    end

    it "video_by_device_type returns parsed rows" do
      stub_query(headers: %w[deviceType views], rows: [ [ "MOBILE", 100 ] ])
      result = client.video_by_device_type(video: video, from: from, to: to)
      expect(result[:rows].first).to eq([ "MOBILE", 100 ])
    end

    it "video_by_operating_system returns parsed rows" do
      stub_query(headers: %w[operatingSystem views], rows: [ [ "ANDROID", 100 ] ])
      result = client.video_by_operating_system(video: video, from: from, to: to)
      expect(result[:rows].first).to eq([ "ANDROID", 100 ])
    end

    it "video_by_traffic_source returns parsed rows" do
      stub_query(headers: %w[insightTrafficSourceType views], rows: [ [ "YT_SEARCH", 100 ] ])
      result = client.video_by_traffic_source(video: video, from: from, to: to)
      expect(result[:rows].first).to eq([ "YT_SEARCH", 100 ])
    end

    it "video_by_subscribed_status returns parsed rows" do
      stub_query(headers: %w[subscribedStatus views], rows: [ [ "SUBSCRIBED", 100 ] ])
      result = client.video_by_subscribed_status(video: video, from: from, to: to)
      expect(result[:rows].first).to eq([ "SUBSCRIBED", 100 ])
    end

    it "video_demographics returns parsed rows" do
      stub_query(headers: %w[ageGroup gender viewerPercentage], rows: [ [ "AGE_18_24", "MALE", 0.4 ] ])
      result = client.video_demographics(video: video, from: from, to: to)
      expect(result[:rows].first).to eq([ "AGE_18_24", "MALE", 0.4 ])
    end

    it "video_retention returns parsed rows" do
      stub_query(headers: %w[elapsedVideoTimeRatio audienceWatchRatio], rows: [ [ 0.0, 1.0 ], [ 0.01, 0.95 ] ])
      result = client.video_retention(video: video)
      expect(result[:rows].size).to eq(2)
    end
  end

  describe "no-op stubs (C4 / C5)" do
    let(:client) { described_class.new(connection: connection) }

    it "channel_geography raises NotImplementedError" do
      expect { client.channel_geography }.to raise_error(NotImplementedError)
    end

    it "channel_demographics raises NotImplementedError" do
      expect { client.channel_demographics }.to raise_error(NotImplementedError)
    end
  end

  describe "auth failure (HTTP 401)" do
    before { stub_query_to_raise(Google::Apis::AuthorizationError.new("token expired")) }

    it "raises AuthError on HTTP 401" do
      expect {
        described_class.new(connection: connection).channel_daily(
          channel: channel, from: from, to: to
        )
      }.to raise_error(Youtube::AnalyticsClient::AuthError)
    end

    it "flips connection.needs_reauth to true on AuthError" do
      expect {
        begin
          described_class.new(connection: connection).channel_daily(
            channel: channel, from: from, to: to
          )
        rescue Youtube::AnalyticsClient::AuthError
          # expected
        end
      }.to change { connection.reload.needs_reauth }.from(false).to(true)
    end

    it "writes an audit row with outcome: 'auth_failed'" do
      begin
        described_class.new(connection: connection).channel_daily(
          channel: channel, from: from, to: to
        )
      rescue Youtube::AnalyticsClient::AuthError
        # expected
      end
      row = YoutubeApiCall.unscoped.last
      expect(row.outcome).to eq("auth_failed")
    end
  end

  describe "rate limit (HTTP 429)" do
    before { stub_query_to_raise(Google::Apis::RateLimitError.new("rate limited")) }

    it "raises RateLimitError on HTTP 429" do
      expect {
        described_class.new(connection: connection).channel_daily(
          channel: channel, from: from, to: to
        )
      }.to raise_error(Youtube::AnalyticsClient::RateLimitError)
    end

    it "writes an audit row with outcome: 'rate_limited'" do
      begin
        described_class.new(connection: connection).channel_daily(
          channel: channel, from: from, to: to
        )
      rescue Youtube::AnalyticsClient::RateLimitError
        # expected
      end
      row = YoutubeApiCall.unscoped.last
      expect(row.outcome).to eq("rate_limited")
    end
  end

  describe "server error (HTTP 5xx)" do
    before { stub_query_to_raise(Google::Apis::ServerError.new("upstream 503")) }

    it "raises TransientError on HTTP 5xx" do
      expect {
        described_class.new(connection: connection).channel_daily(
          channel: channel, from: from, to: to
        )
      }.to raise_error(Youtube::AnalyticsClient::TransientError)
    end

    it "writes an audit row with outcome: 'failed'" do
      begin
        described_class.new(connection: connection).channel_daily(
          channel: channel, from: from, to: to
        )
      rescue Youtube::AnalyticsClient::TransientError
        # expected
      end
      row = YoutubeApiCall.unscoped.last
      expect(row.outcome).to eq("failed")
    end
  end

  describe "client error other than 401/429" do
    before do
      err = Google::Apis::ClientError.new("bad request", status_code: 400)
      stub_query_to_raise(err)
    end

    it "raises PermanentError on HTTP 400" do
      expect {
        described_class.new(connection: connection).channel_daily(
          channel: channel, from: from, to: to
        )
      }.to raise_error(Youtube::AnalyticsClient::PermanentError)
    end
  end

  describe "network timeout" do
    before { stub_query_to_raise(Errno::ETIMEDOUT.new("connection timed out")) }

    it "raises TransientError on Errno::ETIMEDOUT" do
      expect {
        described_class.new(connection: connection).channel_daily(
          channel: channel, from: from, to: to
        )
      }.to raise_error(Youtube::AnalyticsClient::TransientError)
    end

    it "writes an audit row with outcome: 'failed'" do
      begin
        described_class.new(connection: connection).channel_daily(
          channel: channel, from: from, to: to
        )
      rescue Youtube::AnalyticsClient::TransientError
        # expected
      end
      row = YoutubeApiCall.unscoped.last
      expect(row.outcome).to eq("failed")
    end
  end

  describe "malformed response" do
    it "raises PermanentError on a response missing the rows key" do
      bad = OpenStruct.new(column_headers: [ OpenStruct.new(name: "day") ])
      allow(svc).to receive(:query_report).and_return(bad)
      expect {
        described_class.new(connection: connection).channel_daily(
          channel: channel, from: from, to: to
        )
      }.to raise_error(Youtube::AnalyticsClient::PermanentError)
    end

    it "raises PermanentError on rows present without column_headers" do
      bad = OpenStruct.new(column_headers: [], rows: [ [ "x" ] ])
      allow(svc).to receive(:query_report).and_return(bad)
      expect {
        described_class.new(connection: connection).channel_daily(
          channel: channel, from: from, to: to
        )
      }.to raise_error(Youtube::AnalyticsClient::PermanentError)
    end
  end

  describe "Pacific Time handling" do
    before { stub_query(headers: %w[day views], rows: [ [ "2026-05-09", 1 ] ]) }

    it "formats start_date / end_date as YYYY-MM-DD against PT day boundaries" do
      pt_today = Time.now.in_time_zone("Pacific Time (US & Canada)").to_date
      from_local = pt_today - 3
      to_local   = pt_today - 1
      described_class.new(connection: connection).channel_daily(
        channel: channel, from: from_local, to: to_local
      )
      expect(svc).to have_received(:query_report).with(
        hash_including(
          start_date: from_local.strftime("%Y-%m-%d"),
          end_date: to_local.strftime("%Y-%m-%d")
        )
      )
    end
  end

  describe "token freshness" do
    let(:expired_connection) { create(:youtube_connection, :expired, user: user) }
    let(:expired_channel) { create(:channel, :connected, youtube_connection: expired_connection) }

    before do
      stub_query(headers: %w[day views], rows: [ [ "2026-05-09", 1 ] ])
      GoogleStubs.stub_refresh_success(access_token: "ya29.fresh", expires_in: 3600)
    end

    it "refreshes the token before issuing the call when access_token has expired" do
      expect(Youtube::TokenRefresher).to receive(:call).with(expired_connection).and_call_original
      described_class.new(connection: expired_connection).channel_daily(
        channel: expired_channel, from: from, to: to
      )
    end
  end
end
