require "rails_helper"
require "ostruct"

RSpec.describe Youtube::PublicClient do
  describe "#configured?" do
    it "is false when no public_api_key is set" do
      allow(Rails.application.credentials).to receive(:dig)
        .with(:youtube, :public_api_key).and_return(nil)
      expect(described_class.new.configured?).to be(false)
    end

    it "is true when public_api_key is set" do
      allow(Rails.application.credentials).to receive(:dig)
        .with(:youtube, :public_api_key).and_return("AIzaTestKey")
      expect(described_class.new.configured?).to be(true)
    end
  end

  describe "#channels_list" do
    context "without a configured key" do
      before do
        allow(Rails.application.credentials).to receive(:dig)
          .with(:youtube, :public_api_key).and_return(nil)
      end

      it "raises NotConfiguredError" do
        expect {
          described_class.new.channels_list(ids: [ "UCabc" ])
        }.to raise_error(Youtube::NotConfiguredError)
      end
    end

    context "with a configured key" do
      let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }

      before do
        allow(Rails.application.credentials).to receive(:dig)
          .with(:youtube, :public_api_key).and_return("AIzaTestKey")
        allow(Google::Apis::YoutubeV3::YouTubeService).to receive(:new).and_return(svc)
        allow(svc).to receive(:key=)
        allow(svc).to receive(:list_channels).and_return(
          OpenStruct.new(items: [ OpenStruct.new(id: "UCabc") ], next_page_token: nil)
        )
      end

      it "writes one audit row with client_kind=public, youtube_connection nil" do
        expect {
          described_class.new.channels_list(ids: [ "UCabc" ])
        }.to change { YoutubeApiCall.unscoped.where(client_kind: "public").count }.by(1)

        row = YoutubeApiCall.unscoped.where(client_kind: "public").last
        expect(row.youtube_connection_id).to be_nil
        expect(row.user_id).to be_nil
        expect(row.outcome).to eq("success")
      end
    end
  end
end
