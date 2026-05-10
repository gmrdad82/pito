require "rails_helper"

# Phase 15 audit fix-forward — F2 (HTTP timeouts). The factory is the
# single point where Data API v3 / Analytics v2 services are
# constructed for OAuth-backed clients (`Youtube::Client`,
# `Youtube::VideosClient`, `Youtube::VideosReader`). Tests exercise
# the real Google service classes — they construct cleanly offline
# without hitting the network.
RSpec.describe Youtube::ServiceFactory do
  let(:connection) { create(:youtube_connection, access_token: "ya29.test") }

  describe ".data_service" do
    let(:svc) { described_class.data_service(connection) }

    it "returns a Google YouTube Data v3 service" do
      expect(svc).to be_a(Google::Apis::YoutubeV3::YouTubeService)
    end

    it "applies bounded HTTP timeouts" do
      expect(svc.client_options.open_timeout_sec).to eq(described_class::OPEN_TIMEOUT_SEC)
      expect(svc.client_options.read_timeout_sec).to eq(described_class::READ_TIMEOUT_SEC)
      expect(svc.client_options.send_timeout_sec).to eq(described_class::SEND_TIMEOUT_SEC)
    end

    it "wires an authorization adapter that uses the connection's current access_token" do
      headers = {}
      svc.authorization.apply!(headers)
      expect(headers["Authorization"]).to eq("Bearer ya29.test")
    end

    it "sees a token refresh applied after construction (late-binding)" do
      headers = {}
      svc.authorization.apply!(headers)
      expect(headers["Authorization"]).to eq("Bearer ya29.test")

      connection.update!(access_token: "ya29.fresh")
      headers2 = {}
      svc.authorization.apply!(headers2)
      expect(headers2["Authorization"]).to eq("Bearer ya29.fresh")
    end
  end

  describe ".analytics_service" do
    let(:svc) { described_class.analytics_service(connection) }

    it "returns a Google YouTube Analytics v2 service" do
      expect(svc).to be_a(Google::Apis::YoutubeAnalyticsV2::YouTubeAnalyticsService)
    end

    it "applies bounded HTTP timeouts" do
      expect(svc.client_options.open_timeout_sec).to eq(described_class::OPEN_TIMEOUT_SEC)
      expect(svc.client_options.read_timeout_sec).to eq(described_class::READ_TIMEOUT_SEC)
      expect(svc.client_options.send_timeout_sec).to eq(described_class::SEND_TIMEOUT_SEC)
    end

    it "wires an authorization adapter that uses the connection's current access_token" do
      headers = {}
      svc.authorization.apply!(headers)
      expect(headers["Authorization"]).to eq("Bearer ya29.test")
    end
  end
end
