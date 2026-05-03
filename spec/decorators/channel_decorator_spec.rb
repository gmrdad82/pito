require "rails_helper"

RSpec.describe ChannelDecorator do
  let(:channel) { create(:channel, :fully_loaded) }
  let(:decorator) { described_class.new(channel) }

  describe "#as_summary_json" do
    let(:json) { decorator.as_summary_json }

    it "includes the new schema keys" do
      expect(json).to include(
        :id, :tenant_id, :channel_url, :star, :connected, :syncing,
        :last_synced_at, :created_at, :updated_at
      )
    end

    it "exposes tenant_id (required by the pito-sh Channel struct)" do
      expect(json[:tenant_id]).to eq(channel.tenant_id)
      expect(json[:tenant_id]).to be_a(Integer)
    end

    it "exposes the boolean flags as yes/no strings (boundary convention)" do
      expect(json[:star]).to eq("yes")
      expect(json[:connected]).to eq("yes")
      expect(json[:syncing]).to eq("yes")
    end

    it "renders 'no' strings for false flags" do
      plain = create(:channel)
      plain_json = described_class.new(plain).as_summary_json
      expect(plain_json[:star]).to eq("no")
      expect(plain_json[:connected]).to eq("no")
      expect(plain_json[:syncing]).to eq("no")
    end

    it "renders timestamps in ISO 8601" do
      expect(json[:last_synced_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      expect(json[:created_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      expect(json[:updated_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end
  end

  describe "#as_detail_json" do
    before { create(:video, channel: channel) }

    let(:json) { decorator.as_detail_json }

    it "includes summary keys plus video_count" do
      expect(json).to include(:id, :tenant_id, :channel_url, :star, :connected, :syncing, :video_count)
    end

    it "counts associated videos" do
      expect(json[:video_count]).to eq(1)
    end
  end

  describe "schema cleanup" do
    it "no longer responds to formatted_subscriber_count" do
      expect(decorator).not_to respond_to(:formatted_subscriber_count)
    end

    it "no longer responds to formatted_view_count" do
      expect(decorator).not_to respond_to(:formatted_view_count)
    end

    it "no longer responds to formatted_video_count" do
      expect(decorator).not_to respond_to(:formatted_video_count)
    end
  end
end
