require "rails_helper"
require "ostruct"

# Phase 12 — VideosReader hits videos.list (1 unit) and returns the
# parsed item Hash. Used by VideoSyncBack to build the read-modify-
# write payload.
RSpec.describe Youtube::VideosReader do
  let(:user) { User.first || create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel) { create(:channel, youtube_connection: connection) }
  let(:video) { create(:video, channel: channel, youtube_video_id: "abc123") }

  let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }

  before do
    allow(Google::Apis::YoutubeV3::YouTubeService).to receive(:new).and_return(svc)
    allow(svc).to receive(:authorization=)
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
  end

  describe "404" do
    it "raises NotFoundError when items is empty" do
      allow(svc).to receive(:list_videos).and_return(OpenStruct.new(items: []))
      expect {
        described_class.new(connection).read_video(video)
      }.to raise_error(Youtube::NotFoundError)
    end
  end

  describe "401" do
    it "raises AuthRevokedError" do
      err = Google::Apis::AuthorizationError.new("401")
      allow(svc).to receive(:list_videos).and_raise(err)
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
