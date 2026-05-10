require "rails_helper"
require "ostruct"

# Phase 12 — VideosReader hits videos.list (1 unit) and returns the
# parsed item Hash. Used by VideoSyncBack to build the read-modify-
# write payload.
#
# Phase 15 audit fix-forward — F1 (token refresh) and F2 (HTTP timeouts)
# coverage added.
RSpec.describe Youtube::VideosReader do
  let(:user) { User.first || create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel) { create(:channel, youtube_connection: connection) }
  let(:video) { create(:video, channel: channel, youtube_video_id: "abc123") }

  let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }
  let(:client_options) { Struct.new(:open_timeout_sec, :read_timeout_sec, :send_timeout_sec).new(nil, nil, nil) }

  before do
    allow(Google::Apis::YoutubeV3::YouTubeService).to receive(:new).and_return(svc)
    allow(svc).to receive(:authorization=)
    # Phase 15 F2 — factory needs `client_options` to set timeouts.
    allow(svc).to receive(:client_options).and_return(client_options)
  end

  describe "happy path" do
    it "returns the parsed first item" do
      allow(svc).to receive(:list_videos).with(
        "snippet,status,contentDetails",
        id: "abc123"
      ).and_return(
        OpenStruct.new(
          items: [
            OpenStruct.new(
              id: "abc123",
              etag: "etag-1",
              snippet: OpenStruct.new(title: "old", description: "d", tags: [ "x" ], category_id: "20"),
              status: OpenStruct.new(privacy_status: "private", made_for_kids: false)
            )
          ]
        )
      )

      result = described_class.new(connection).read_video(video)
      expect(result).to be_a(Hash)
      expect(result[:id]).to eq("abc123")
      expect(result[:snippet][:title]).to eq("old")
    end

    it "writes one audit row with endpoint=videos.list" do
      allow(svc).to receive(:list_videos).and_return(
        OpenStruct.new(items: [ OpenStruct.new(id: "abc123") ])
      )

      expect {
        described_class.new(connection).read_video(video)
      }.to change { YoutubeApiCall.unscoped.count }.by(1)

      row = YoutubeApiCall.unscoped.last
      expect(row.endpoint).to eq("videos.list")
      expect(row.units).to eq(1)
      expect(row.outcome).to eq("success")
      expect(row.youtube_connection_id).to eq(connection.id)
    end

    it "configures the underlying service with bounded HTTP timeouts" do
      allow(svc).to receive(:list_videos).and_return(
        OpenStruct.new(items: [ OpenStruct.new(id: "abc123") ])
      )

      described_class.new(connection).read_video(video)

      expect(client_options.open_timeout_sec).to eq(Youtube::ServiceFactory::OPEN_TIMEOUT_SEC)
      expect(client_options.read_timeout_sec).to eq(Youtube::ServiceFactory::READ_TIMEOUT_SEC)
      expect(client_options.send_timeout_sec).to eq(Youtube::ServiceFactory::SEND_TIMEOUT_SEC)
    end
  end

  describe "404" do
    it "raises NotFoundError when items is empty" do
      allow(svc).to receive(:list_videos).and_return(OpenStruct.new(items: []))
      expect {
        described_class.new(connection).read_video(video)
      }.to raise_error(Youtube::NotFoundError)
    end
  end

  # Phase 15 F1 — token-freshness contract.
  describe "token refresh" do
    it "proactively refreshes a stale token before issuing the call" do
      connection.update!(expires_at: 5.minutes.ago)
      GoogleStubs.stub_refresh_success(access_token: "ya29.fresh", expires_in: 3600)

      allow(svc).to receive(:list_videos).and_return(
        OpenStruct.new(items: [ OpenStruct.new(id: "abc123") ])
      )

      described_class.new(connection).read_video(video)

      expect(connection.reload.access_token).to eq("ya29.fresh")
    end

    it "retries once after a 401 by refreshing the token, then succeeds" do
      GoogleStubs.stub_refresh_success(access_token: "ya29.refreshed", expires_in: 3600)

      err = Google::Apis::AuthorizationError.new("401")
      call_count = 0
      allow(svc).to receive(:list_videos) do
        call_count += 1
        raise err if call_count == 1
        OpenStruct.new(items: [ OpenStruct.new(id: "abc123") ])
      end

      expect {
        described_class.new(connection).read_video(video)
      }.not_to raise_error

      expect(call_count).to eq(2)
      expect(connection.reload.access_token).to eq("ya29.refreshed")
      expect(connection.reload.needs_reauth?).to be(false)
      expect(YoutubeApiCall.unscoped.last.outcome).to eq("success")
    end

    it "raises AuthRevokedError when refresh succeeds but the retry still 401s" do
      GoogleStubs.stub_refresh_success
      err = Google::Apis::AuthorizationError.new("401")
      allow(svc).to receive(:list_videos).and_raise(err)

      expect {
        described_class.new(connection).read_video(video)
      }.to raise_error(Youtube::AuthRevokedError)

      expect(YoutubeApiCall.unscoped.last.outcome).to eq("auth_failed")
    end

    it "raises AuthRevokedError when refresh itself reports invalid_grant" do
      GoogleStubs.stub_refresh_invalid_grant
      err = Google::Apis::AuthorizationError.new("401")
      allow(svc).to receive(:list_videos).and_raise(err)

      expect {
        described_class.new(connection).read_video(video)
      }.to raise_error(Youtube::AuthRevokedError)

      expect(connection.reload.needs_reauth?).to be(true)
    end

    it "surfaces a stale-token + invalid_grant pre-call refresh as AuthRevokedError" do
      connection.update!(expires_at: 5.minutes.ago)
      GoogleStubs.stub_refresh_invalid_grant

      expect {
        described_class.new(connection).read_video(video)
      }.to raise_error(Youtube::AuthRevokedError)
    end
  end

  describe "5xx" do
    it "raises ServerError" do
      err = Google::Apis::ServerError.new("500")
      allow(svc).to receive(:list_videos).and_raise(err)
      expect {
        described_class.new(connection).read_video(video)
      }.to raise_error(Youtube::ServerError)
    end
  end
end
