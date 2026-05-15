require "rails_helper"
require "ostruct"

RSpec.describe Youtube::PublicClient do
  # Phase 29 — Unit A1. `Youtube::PublicClient#api_key` reads
  # `Rails.application.credentials.dig(:google_oauth, :api_key)` ONLY —
  # the AppSetting `youtube_api_key` read and the dead
  # `:youtube, :public_api_key` transitional path are both gone.
  def stub_google_oauth_api_key(value)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig)
      .with(:google_oauth, :api_key).and_return(value)
  end

  describe "#configured?" do
    it "is false when the credentials google_oauth.api_key is blank" do
      stub_google_oauth_api_key(nil)
      expect(described_class.new.configured?).to be(false)
    end

    it "is true when the credentials google_oauth.api_key is set" do
      stub_google_oauth_api_key("AIzaCredentialsKey")
      expect(described_class.new.configured?).to be(true)
    end
  end

  describe "#channels_list" do
    context "without a configured key" do
      before { stub_google_oauth_api_key(nil) }

      it "raises NotConfiguredError" do
        expect {
          described_class.new.channels_list(ids: [ "UCabc" ])
        }.to raise_error(Youtube::NotConfiguredError)
      end
    end

    context "with a configured key in credentials" do
      let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }

      before do
        stub_google_oauth_api_key("AIzaCredentialsKey")
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

      it "passes the credentials-sourced key to the YouTube service" do
        described_class.new.channels_list(ids: [ "UCabc" ])
        expect(svc).to have_received(:key=).with("AIzaCredentialsKey")
      end
    end
  end
end
