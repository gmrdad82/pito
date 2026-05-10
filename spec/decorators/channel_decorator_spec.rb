require "rails_helper"

# Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006).
# `connected` is a derived "yes" / "no" string in the JSON wire shape
# (true when `youtube_connection_id` is set); `syncing` is dropped.
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

    it "includes the post-A2 schema keys (no tenant_id after Phase 8)" do
      expect(json).to include(
        :id, :channel_url, :star, :connected,
        :last_synced_at, :created_at, :updated_at
      )
      expect(json).not_to have_key(:syncing)
      expect(json).not_to have_key(:tenant_id)
    end

    it "exposes the boolean flags as yes/no strings (boundary convention)" do
      expect(json[:star]).to eq("yes")
      expect(json[:connected]).to eq("yes")
    end

    it "renders 'no' strings for false flags" do
      plain = create(:channel)
      plain_json = described_class.new(plain).as_summary_json
      expect(plain_json[:star]).to eq("no")
      expect(plain_json[:connected]).to eq("no")
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

    it "includes summary keys plus video_count" do
      expect(json).to include(:id, :channel_url, :star, :connected, :video_count)
      expect(json).not_to have_key(:syncing)
      expect(json).not_to have_key(:tenant_id)
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
