require "rails_helper"
require "ostruct"

RSpec.describe Youtube::PublicClient do
  # 2026-05-11 — `Youtube::PublicClient#api_key` now reads
  # `AppSetting.youtube_api_key` FIRST, falling back to
  # `Rails.application.credentials.dig(:google_oauth, :api_key)` and
  # finally the legacy `:youtube, :public_api_key` path. The specs
  # exercise the primary path (AppSetting) and pin the resolver
  # order via a separate context that nils out AppSetting.
  describe "#configured?" do
    before { AppSetting.delete_all }

    it "is false when no AppSetting row exists and credentials are empty" do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig)
        .with(:google_oauth, :api_key).and_return(nil)
      allow(Rails.application.credentials).to receive(:dig)
        .with(:youtube, :public_api_key).and_return(nil)
      expect(described_class.new.configured?).to be(false)
    end

    it "is true when AppSetting.youtube_api_key is set" do
      AppSetting.create!(key: "max_panes", value: "5",
                         youtube_api_key: "AIzaTestKey")
      expect(described_class.new.configured?).to be(true)
    end

    it "falls back to credentials when AppSetting.youtube_api_key is blank" do
      AppSetting.delete_all
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig)
        .with(:google_oauth, :api_key).and_return("AIzaCredentialsKey")
      expect(described_class.new.configured?).to be(true)
    end
  end

  describe "#channels_list" do
    before { AppSetting.delete_all }

    context "without a configured key" do
      before do
        allow(Rails.application.credentials).to receive(:dig).and_call_original
        allow(Rails.application.credentials).to receive(:dig)
          .with(:google_oauth, :api_key).and_return(nil)
        allow(Rails.application.credentials).to receive(:dig)
          .with(:youtube, :public_api_key).and_return(nil)
      end

      it "raises NotConfiguredError" do
        expect {
          described_class.new.channels_list(ids: [ "UCabc" ])
        }.to raise_error(Youtube::NotConfiguredError)
      end
    end

    context "with a configured key on the AppSetting singleton" do
      let(:svc) { instance_double(Google::Apis::YoutubeV3::YouTubeService) }

      before do
        AppSetting.create!(key: "max_panes", value: "5",
                           youtube_api_key: "AIzaTestKey")
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

      it "passes the AppSetting-sourced key to the YouTube service" do
        described_class.new.channels_list(ids: [ "UCabc" ])
        expect(svc).to have_received(:key=).with("AIzaTestKey")
      end
    end
  end
end
