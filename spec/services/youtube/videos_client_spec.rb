require "rails_helper"
require "ostruct"

# Phase 12 — VideosClient hits videos.update (50 units) and returns
# the parsed response. Read-modify-write semantics: pass-through any
# extra fields the reader returned that pito doesn't model.
#
# Phase 15 audit fix-forward — F1 (token refresh) and F2 (HTTP timeouts)
# coverage added.
RSpec.describe Youtube::VideosClient do
  let(:user) { User.first || create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel) { create(:channel, youtube_connection: connection) }
  let(:video) do
    create(:video,
           channel: channel,
           title: "new title",
           description: "fresh",
           tags: [ "halo" ],
           category_id: "20",
           privacy_status: :private,
           publish_at: nil,
           self_declared_made_for_kids: false,
           contains_synthetic_media: false)
  end

  let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }
  let(:client_options) { Struct.new(:open_timeout_sec, :read_timeout_sec, :send_timeout_sec).new(nil, nil, nil) }

  before do
    allow(Google::Apis::YoutubeV3::YouTubeService).to receive(:new).and_return(svc)
    allow(svc).to receive(:authorization=)
    # Phase 15 F2 — the factory sets timeouts on `client_options`. The
    # double has to expose a settable struct so the spec exercises the
    # real construction path without mocking the factory itself.
    allow(svc).to receive(:client_options).and_return(client_options)
  end

  describe "happy path" do
    it "returns the parsed API response and writes a 50-unit audit row" do
      allow(svc).to receive(:update_video).and_return(
        OpenStruct.new(
          id: video.youtube_video_id,
          etag: "etag-after",
          snippet: OpenStruct.new(title: "new title"),
          status: OpenStruct.new(made_for_kids: false)
        )
      )

      fresh = { snippet: { default_language: "en" }, status: { license: "youtube" } }

      expect {
        described_class.new(connection).update_video(video, fresh: fresh)
      }.to change { YoutubeApiCall.unscoped.count }.by(1)

      row = YoutubeApiCall.unscoped.last
      expect(row.endpoint).to eq("videos.update")
      expect(row.units).to eq(50)
      expect(row.outcome).to eq("success")
    end

    it "merges fresh.snippet pass-through fields into the payload" do
      allow(svc).to receive(:update_video).and_return(OpenStruct.new(id: video.youtube_video_id))
      fresh = { snippet: { default_language: "en" }, status: {} }

      client = described_class.new(connection)
      client.update_video(video, fresh: fresh)
      expect(client.last_payload[:snippet][:default_language]).to eq("en")
      expect(client.last_payload[:snippet][:title]).to eq("new title")
    end

    it "overrides title/description/tags/category from local Video" do
      allow(svc).to receive(:update_video).and_return(OpenStruct.new(id: video.youtube_video_id))
      fresh = { snippet: { title: "API stale title" }, status: {} }

      client = described_class.new(connection)
      client.update_video(video, fresh: fresh)
      expect(client.last_payload[:snippet][:title]).to eq("new title")
      expect(client.last_payload[:snippet][:tags]).to eq([ "halo" ])
      expect(client.last_payload[:snippet][:categoryId]).to eq("20")
    end

    it "sets status.privacyStatus from local privacy_status" do
      allow(svc).to receive(:update_video).and_return(OpenStruct.new(id: video.youtube_video_id))
      client = described_class.new(connection)
      client.update_video(video, fresh: { snippet: {}, status: {} })
      expect(client.last_payload[:status][:privacyStatus]).to eq("private")
    end

    # Phase 15 F2 — every Google service constructed via the factory
    # carries bounded HTTP timeouts so a hung upstream cannot wedge a
    # worker indefinitely.
    it "configures the underlying service with bounded HTTP timeouts" do
      allow(svc).to receive(:update_video).and_return(OpenStruct.new(id: video.youtube_video_id))
      described_class.new(connection).update_video(video, fresh: { snippet: {}, status: {} })

      expect(client_options.open_timeout_sec).to eq(Youtube::ServiceFactory::OPEN_TIMEOUT_SEC)
      expect(client_options.read_timeout_sec).to eq(Youtube::ServiceFactory::READ_TIMEOUT_SEC)
      expect(client_options.send_timeout_sec).to eq(Youtube::ServiceFactory::SEND_TIMEOUT_SEC)
    end
  end

  # Phase 15 F1 — token-freshness contract.
  describe "token refresh" do
    it "proactively refreshes a stale token before issuing the call" do
      connection.update!(expires_at: 5.minutes.ago)
      GoogleStubs.stub_refresh_success(access_token: "ya29.fresh", expires_in: 3600)

      allow(svc).to receive(:update_video).and_return(OpenStruct.new(id: video.youtube_video_id))

      described_class.new(connection).update_video(video, fresh: { snippet: {}, status: {} })

      expect(connection.reload.access_token).to eq("ya29.fresh")
    end

    it "retries once after a 401 by refreshing the token, then succeeds" do
      GoogleStubs.stub_refresh_success(access_token: "ya29.refreshed", expires_in: 3600)

      err = Google::Apis::AuthorizationError.new("401")
      call_count = 0
      allow(svc).to receive(:update_video) do
        call_count += 1
        raise err if call_count == 1
        OpenStruct.new(id: video.youtube_video_id)
      end

      expect {
        described_class.new(connection).update_video(video, fresh: { snippet: {}, status: {} })
      }.not_to raise_error

      expect(call_count).to eq(2)
      expect(connection.reload.access_token).to eq("ya29.refreshed")
      expect(connection.reload.needs_reauth?).to be(false)
      expect(YoutubeApiCall.unscoped.last.outcome).to eq("success")
    end

    it "raises AuthRevokedError when refresh succeeds but the retry still 401s" do
      GoogleStubs.stub_refresh_success
      err = Google::Apis::AuthorizationError.new("401")
      allow(svc).to receive(:update_video).and_raise(err)

      expect {
        described_class.new(connection).update_video(video, fresh: { snippet: {}, status: {} })
      }.to raise_error(Youtube::AuthRevokedError)

      expect(YoutubeApiCall.unscoped.last.outcome).to eq("auth_failed")
    end

    it "raises AuthRevokedError when the refresh itself reports invalid_grant" do
      GoogleStubs.stub_refresh_invalid_grant
      err = Google::Apis::AuthorizationError.new("401")
      allow(svc).to receive(:update_video).and_raise(err)

      expect {
        described_class.new(connection).update_video(video, fresh: { snippet: {}, status: {} })
      }.to raise_error(Youtube::AuthRevokedError)

      expect(connection.reload.needs_reauth?).to be(true)
    end

    it "surfaces a stale-token + invalid_grant pre-call refresh as AuthRevokedError" do
      connection.update!(expires_at: 5.minutes.ago)
      GoogleStubs.stub_refresh_invalid_grant

      expect {
        described_class.new(connection).update_video(video, fresh: { snippet: {}, status: {} })
      }.to raise_error(Youtube::AuthRevokedError)
    end
  end

  describe "quota exhausted" do
    it "raises QuotaExhaustedError on rate limit" do
      err = Google::Apis::RateLimitError.new("rate-limited")
      allow(svc).to receive(:update_video).and_raise(err)
      expect {
        described_class.new(connection).update_video(video, fresh: { snippet: {}, status: {} })
      }.to raise_error(Youtube::QuotaExhaustedError)
    end
  end

  describe "validation error (400)" do
    it "raises ValidationError" do
      err = Google::Apis::ClientError.new("title invalid")
      allow(err).to receive(:status_code).and_return(400)
      allow(svc).to receive(:update_video).and_raise(err)
      expect {
        described_class.new(connection).update_video(video, fresh: { snippet: {}, status: {} })
      }.to raise_error(Youtube::ValidationError)
    end
  end

  describe "5xx" do
    it "raises ServerError" do
      err = Google::Apis::ServerError.new("500")
      allow(svc).to receive(:update_video).and_raise(err)
      expect {
        described_class.new(connection).update_video(video, fresh: { snippet: {}, status: {} })
      }.to raise_error(Youtube::ServerError)
    end
  end
end
