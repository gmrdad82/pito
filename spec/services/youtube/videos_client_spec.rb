require "rails_helper"
require "ostruct"

# Phase 12 — VideosClient hits videos.update (50 units) and returns
# the parsed response. Read-modify-write semantics: pass-through any
# extra fields the reader returned that pito doesn't model.
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

  before do
    allow(Google::Apis::YoutubeV3::YouTubeService).to receive(:new).and_return(svc)
    allow(svc).to receive(:authorization=)
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
  end

  describe "401" do
    it "raises AuthRevokedError" do
      allow(svc).to receive(:update_video).and_raise(Google::Apis::AuthorizationError, "401")
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
