# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channel::Youtube::VideosClient, type: :service do
  describe "#delete_video" do
    let(:connection) { create(:youtube_connection) }
    let!(:channel)   { create(:channel, youtube_connection: connection) }
    let(:video)      { create(:video, channel: channel, youtube_video_id: "yt_del_1") }
    let(:svc)        { instance_double(Google::Apis::YoutubeV3::YouTubeService) }

    subject(:client) { described_class.new(connection) }

    before do
      allow(Channel::Youtube::ServiceFactory).to receive(:data_service).with(connection).and_return(svc)
      allow(svc).to receive(:delete_video)
    end

    it "issues videos.delete with the youtube id" do
      client.delete_video(video)
      expect(svc).to have_received(:delete_video).with("yt_del_1")
    end

    it "tracks a videos.delete audit request" do
      expect {
        client.delete_video(video)
      }.to change {
        ApiRequest.youtube.where(endpoint: "videos.delete").count
      }.by(1)
    end

    it "maps a 5xx into ServerError" do
      allow(svc).to receive(:delete_video).and_raise(Google::Apis::ServerError.new("boom"))
      expect { client.delete_video(video) }.to raise_error(Channel::Youtube::ServerError)
    end
  end
end
