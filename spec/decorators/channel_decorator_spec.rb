require "rails_helper"

# Channel JSON wire shape. The derived `connected` field and the
# legacy `syncing` field are both retired — every channel is
# OAuth-linked by definition now.
RSpec.describe ChannelDecorator do
  describe "#as_summary_json" do
    let(:connection) { create(:youtube_connection) }
    let(:channel) do
      create(:channel,
             :starred,
             youtube_connection: connection,
             last_synced_at: Time.current)
    end
    let(:decorator) { described_class.new(channel) }
    let(:json) { decorator.as_summary_json }

    it "includes the post-cleanup schema keys" do
      expect(json).to include(
        :id, :channel_url, :star,
        :last_synced_at, :created_at, :updated_at
      )
      expect(json).not_to have_key(:syncing)
      expect(json).not_to have_key(:tenant_id)
      expect(json).not_to have_key(:connected)
    end

    it "exposes the star flag as a yes/no string (boundary convention)" do
      expect(json[:star]).to eq("yes")
    end

    it "renders 'no' for a false star flag" do
      plain = create(:channel)
      plain_json = described_class.new(plain).as_summary_json
      expect(plain_json[:star]).to eq("no")
    end

    it "renders timestamps in ISO 8601" do
      expect(json[:last_synced_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      expect(json[:created_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      expect(json[:updated_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end
  end

  describe "#as_detail_json" do
    let(:channel) { create(:channel) }
    let(:decorator) { described_class.new(channel) }
    let(:json) { decorator.as_detail_json }

    before { create(:video, channel: channel) }

    it "includes summary keys plus video_count and excludes the retired `connected` field" do
      expect(json).to include(:id, :channel_url, :star, :video_count)
      expect(json).not_to have_key(:syncing)
      expect(json).not_to have_key(:tenant_id)
      expect(json).not_to have_key(:connected)
    end

    it "counts associated videos" do
      expect(json[:video_count]).to eq(1)
    end
  end

  describe "schema cleanup" do
    let(:decorator) { described_class.new(create(:channel)) }

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
