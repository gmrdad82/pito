require "rails_helper"
require "ostruct"

# Phase 7.5 §11a — Channel Schema + Sync Foundation.
#
# Exercises `Youtube::Client#fetch_channel(channel)` against canned
# `Google::Apis::YoutubeV3::YouTubeService#list_channels` return values
# and error shapes. The audit + retry / refresh / quota plumbing lives
# in the shared `perform` chokepoint (covered by `client_spec.rb`); this
# spec asserts (1) the normalized return shape and (2) that the same
# error-surfacing semantics apply to the new entrypoint.
RSpec.describe Youtube::Client, "#fetch_channel" do
  let(:connection) { create(:youtube_connection) }
  let(:channel)    { create(:channel, youtube_connection: connection) }
  let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }

  def stub_data_service(svc_double)
    allow(Google::Apis::YoutubeV3::YouTubeService).to receive(:new).and_return(svc_double)
    allow(svc_double).to receive(:client_options).and_return(
      Struct.new(:open_timeout_sec, :read_timeout_sec, :send_timeout_sec).new(nil, nil, nil)
    )
    allow(svc_double).to receive(:authorization=)
  end

  def full_channel_item
    OpenStruct.new(
      id: "UCabc",
      snippet: OpenStruct.new(
        title: "Main Channel",
        custom_url: "@maincreator",
        description: "Channel description",
        country: "US",
        default_language: "en",
        published_at: "2014-01-02T03:04:05Z",
        thumbnails: OpenStruct.new(
          default: OpenStruct.new(url: "https://cdn.youtube/avatar.jpg")
        )
      ),
      statistics: OpenStruct.new(
        subscriber_count: "1234",
        view_count: "5678901",
        video_count: "42",
        hidden_subscriber_count: false
      ),
      branding_settings: OpenStruct.new(
        channel: OpenStruct.new(keywords: "gaming reviews"),
        image: OpenStruct.new(
          banner_external_url: "https://cdn.youtube/banner.jpg"
        )
      ),
      content_details: OpenStruct.new(related_playlists: OpenStruct.new(uploads: "UUabc")),
      status: OpenStruct.new(privacy_status: "public")
    )
  end

  describe "happy path" do
    before do
      stub_data_service(svc)
      allow(svc).to receive(:list_channels).and_return(
        OpenStruct.new(items: [ full_channel_item ], next_page_token: nil)
      )
    end

    it "returns the normalized snake_case Hash" do
      result = described_class.new(connection).fetch_channel(channel)

      expect(result).to include(
        title: "Main Channel",
        handle: "@maincreator",
        description: "Channel description",
        country: "US",
        default_language: "en",
        keywords: "gaming reviews",
        banner_url: "https://cdn.youtube/banner.jpg",
        avatar_url: "https://cdn.youtube/avatar.jpg",
        watermark_url: nil,
        watermark_timing: nil,
        watermark_offset_ms: nil,
        links: [],
        subscriber_count: 1234,
        view_count: 5_678_901,
        video_count: 42,
        hidden_subscriber_count: false,
        published_at: "2014-01-02T03:04:05Z"
      )
    end

    it "writes one audit row with outcome=success, status=200, endpoint=channels.list" do
      expect {
        described_class.new(connection).fetch_channel(channel)
      }.to change { YoutubeApiCall.unscoped.count }.by(1)

      row = YoutubeApiCall.unscoped.last
      expect(row.endpoint).to eq("channels.list")
      expect(row.outcome).to eq("success")
      expect(row.http_status).to eq(200)
      expect(row.units).to eq(1)
    end

    it "requests the full part set (snippet + statistics + brandingSettings + contentDetails + status)" do
      described_class.new(connection).fetch_channel(channel)
      expect(svc).to have_received(:list_channels) do |parts_string, **|
        parts = parts_string.split(",")
        expect(parts).to include("snippet", "statistics", "brandingSettings", "contentDetails", "status")
      end
    end
  end

  describe "401 once → refresh → retry succeeds" do
    let(:connection) { create(:youtube_connection, :expired) }

    before do
      GoogleStubs.stub_refresh_success(access_token: "ya29.fresh", expires_in: 3600)
      stub_data_service(svc)
      allow(svc).to receive(:list_channels).and_return(
        OpenStruct.new(items: [ full_channel_item ], next_page_token: nil)
      )
    end

    it "refreshes the token, returns the normalized hash, audits a single success" do
      result = described_class.new(connection).fetch_channel(channel)
      expect(result[:title]).to eq("Main Channel")
      expect(connection.reload.access_token).to eq("ya29.fresh")
      expect(YoutubeApiCall.unscoped.last.outcome).to eq("success")
    end
  end

  describe "401 after refresh still fails → NeedsReauthError" do
    before do
      GoogleStubs.stub_refresh_success
      stub_data_service(svc)
      err = Google::Apis::AuthorizationError.new(
        "Unauthorized", status_code: 401, body: '{"error":"invalid_token"}'
      )
      allow(svc).to receive(:list_channels).and_raise(err)
    end

    it "raises NeedsReauthError and flips needs_reauth=true" do
      expect {
        described_class.new(connection).fetch_channel(channel)
      }.to raise_error(Youtube::NeedsReauthError)
      expect(connection.reload.needs_reauth?).to be(true)
    end

    it "audits outcome=auth_failed with status=401" do
      begin
        described_class.new(connection).fetch_channel(channel)
      rescue Youtube::NeedsReauthError
        # expected
      end
      row = YoutubeApiCall.unscoped.where(outcome: "auth_failed").last
      expect(row).not_to be_nil
      expect(row.http_status).to eq(401)
    end
  end

  describe "429 with retry-after → second 429 → TransientError" do
    before do
      stub_data_service(svc)
      allow_any_instance_of(described_class).to receive(:sleep)
      err = Google::Apis::RateLimitError.new(
        "Rate-limited", status_code: 429, body: '{"error":"rateLimitExceeded"}'
      )
      allow(svc).to receive(:list_channels).and_raise(err)
    end

    it "raises TransientError and audits outcome=rate_limited with status=429" do
      expect {
        described_class.new(connection).fetch_channel(channel)
      }.to raise_error(Youtube::TransientError)

      row = YoutubeApiCall.unscoped.last
      expect(row.outcome).to eq("rate_limited")
      expect(row.http_status).to eq(429)
    end
  end

  describe "403 quota exhausted → QuotaExhaustedError" do
    before do
      stub_data_service(svc)
      err = Google::Apis::ClientError.new(
        "Forbidden",
        status_code: 403,
        body: '{"error":{"code":403,"errors":[{"reason":"quotaExceeded"}]}}'
      )
      allow(svc).to receive(:list_channels).and_raise(err)
    end

    it "raises QuotaExhaustedError and audits outcome=quota_exceeded" do
      expect {
        described_class.new(connection).fetch_channel(channel)
      }.to raise_error(Youtube::QuotaExhaustedError)

      expect(YoutubeApiCall.unscoped.last.outcome).to eq("quota_exceeded")
    end
  end

  describe "5xx three times → TransientError" do
    before do
      stub_data_service(svc)
      allow_any_instance_of(described_class).to receive(:sleep)
      err = Google::Apis::ServerError.new("Server error", status_code: 503, body: "")
      allow(svc).to receive(:list_channels).and_raise(err)
    end

    it "raises TransientError after MAX_5XX_ATTEMPTS and audits outcome=server_error" do
      expect {
        described_class.new(connection).fetch_channel(channel)
      }.to raise_error(Youtube::TransientError)

      row = YoutubeApiCall.unscoped.where(outcome: "server_error").last
      expect(row).not_to be_nil
    end
  end

  describe "edge — minimal snippet (no country, no default_language, no keywords, no banner)" do
    let(:minimal_item) do
      OpenStruct.new(
        id: "UCmin",
        snippet: OpenStruct.new(
          title: "Bare Channel",
          custom_url: "@bare",
          description: "Just a title",
          published_at: "2020-01-01T00:00:00Z",
          thumbnails: OpenStruct.new(
            default: OpenStruct.new(url: "https://cdn.youtube/avatar.jpg")
          )
        ),
        statistics: OpenStruct.new(
          subscriber_count: "0",
          view_count: "0",
          video_count: "0",
          hidden_subscriber_count: false
        ),
        branding_settings: OpenStruct.new
      )
    end

    before do
      stub_data_service(svc)
      allow(svc).to receive(:list_channels).and_return(
        OpenStruct.new(items: [ minimal_item ], next_page_token: nil)
      )
    end

    it "returns nil for missing snippet keys and does not raise" do
      result = described_class.new(connection).fetch_channel(channel)
      expect(result[:title]).to eq("Bare Channel")
      expect(result[:country]).to be_nil
      expect(result[:default_language]).to be_nil
      expect(result[:keywords]).to be_nil
      expect(result[:banner_url]).to be_nil
      expect(result[:hidden_subscriber_count]).to be(false)
    end
  end

  describe "edge — hidden_subscriber_count: true" do
    let(:hidden_item) do
      OpenStruct.new(
        snippet: OpenStruct.new(title: "Private Subs"),
        statistics: OpenStruct.new(
          subscriber_count: nil,
          view_count: "0",
          video_count: "0",
          hidden_subscriber_count: true
        ),
        branding_settings: OpenStruct.new
      )
    end

    before do
      stub_data_service(svc)
      allow(svc).to receive(:list_channels).and_return(
        OpenStruct.new(items: [ hidden_item ], next_page_token: nil)
      )
    end

    it "carries hidden_subscriber_count: true and does not crash on nil subscriber_count" do
      result = described_class.new(connection).fetch_channel(channel)
      expect(result[:hidden_subscriber_count]).to be(true)
      expect(result[:subscriber_count]).to be_nil
    end
  end

  describe "edge — handle absent (custom_url unset)" do
    let(:no_handle_item) do
      OpenStruct.new(
        snippet: OpenStruct.new(
          title: "No Handle",
          custom_url: nil,
          description: ""
        ),
        statistics: OpenStruct.new(
          subscriber_count: "1",
          view_count: "2",
          video_count: "0",
          hidden_subscriber_count: false
        ),
        branding_settings: OpenStruct.new
      )
    end

    before do
      stub_data_service(svc)
      allow(svc).to receive(:list_channels).and_return(
        OpenStruct.new(items: [ no_handle_item ], next_page_token: nil)
      )
    end

    it "returns handle: nil without raising" do
      result = described_class.new(connection).fetch_channel(channel)
      expect(result[:handle]).to be_nil
    end
  end
end
