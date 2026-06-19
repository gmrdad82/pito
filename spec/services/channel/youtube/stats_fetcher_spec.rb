# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channel::Youtube::StatsFetcher do
  let(:connection) { create(:youtube_connection) }
  let(:channel) do
    create(:channel,
           youtube_connection: connection,
           youtube_channel_id: "UCaaa111")
  end

  let(:data_response) do
    {
      items: [
        {
          statistics: {
            subscriber_count: "12500",
            view_count: "4800000",
            video_count: "88"
          }
        }
      ]
    }
  end

  before do
    allow_any_instance_of(Channel::Youtube::Client)
      .to receive(:channels_list).and_return(data_response)
  end

  describe ".call" do
    subject(:result) { described_class.call(channel) }

    it "returns subscriber_count from Data API" do
      expect(result[:subscriber_count]).to eq(12_500)
    end

    it "returns view_count from Data API" do
      expect(result[:view_count]).to eq(4_800_000)
    end

    it "does not return watched_hours (dropped)" do
      expect(result).not_to have_key(:watched_hours)
    end

    it "returns a last_synced_at timestamp" do
      expect(result[:last_synced_at]).to be_within(5.seconds).of(Time.current)
    end

    it "calls channels_list with the channel's youtube_channel_id" do
      expect_any_instance_of(Channel::Youtube::Client)
        .to receive(:channels_list)
        .with(ids: [ "UCaaa111" ], parts: %i[statistics])
        .and_return(data_response)

      described_class.call(channel)
    end

    context "when the Data API returns no items" do
      let(:data_response) { { items: [] } }

      it "returns nil for subscriber_count and view_count" do
        expect(result[:subscriber_count]).to be_nil
        expect(result[:view_count]).to be_nil
      end
    end
  end
end
