require "rails_helper"
require_relative "../../../app/mcp/tools/get_channel"
require_relative "../../../app/mcp/tools/get_video"
require_relative "../../../app/mcp/tools/update_channel"
require_relative "../../../app/mcp/tools/bundle_destroy"
require_relative "../../../app/mcp/tools/delete_records"
require_relative "../../../app/mcp/tools/list_videos"

# Phase 20 — friendly URLs. Cross-tool spec: every MCP tool that
# accepts a slugged-resource id at the boundary must accept either a
# slug or an integer id (as a string). The per-tool detail specs cover
# the rest of each tool's contract; this file is the slug-or-id matrix
# only.
RSpec.describe "MCP tools accept slug or integer id" do
  let(:user) { User.first || create(:user) }
  let!(:auth_token) do
    record, _plaintext = ApiToken.generate!(user: user, name: "fid-spec",
                                            scopes: [ Scopes::APP ])
    Current.token = record
    record
  end

  describe "GetChannel" do
    let!(:channel) do
      create(:channel,
             channel_url: "https://www.youtube.com/channel/UCAAAAAAAAAAAAAAAAAAAAAA")
    end

    it "resolves by slug (UC-id)" do
      result = Mcp::Tools::GetChannel.call(id: channel.to_param)
      expect(result.to_h[:isError]).to be_falsey
    end

    it "resolves by integer id (as string)" do
      result = Mcp::Tools::GetChannel.call(id: channel.id.to_s)
      expect(result.to_h[:isError]).to be_falsey
    end

    it "errors on a non-matching id" do
      result = Mcp::Tools::GetChannel.call(id: "does-not-exist")
      expect(result.to_h[:isError]).to be true
    end
  end

  describe "GetVideo" do
    let!(:video) { create(:video, youtube_video_id: "vid_abc123XYZ") }

    it "resolves by slug" do
      result = Mcp::Tools::GetVideo.call(id: video.to_param)
      expect(result.to_h[:isError]).to be_falsey
    end

    it "resolves by integer id (as string)" do
      result = Mcp::Tools::GetVideo.call(id: video.id.to_s)
      expect(result.to_h[:isError]).to be_falsey
    end
  end

  describe "UpdateChannel" do
    let!(:channel) do
      create(:channel,
             channel_url: "https://www.youtube.com/channel/UCBBBBBBBBBBBBBBBBBBBBBB")
    end

    it "accepts a slug" do
      result = Mcp::Tools::UpdateChannel.call(id: channel.to_param, star: "yes")
      expect(result.to_h[:isError]).to be_falsey
      expect(channel.reload.star).to be true
    end

    it "accepts an integer id (as string)" do
      result = Mcp::Tools::UpdateChannel.call(id: channel.id.to_s, star: "yes")
      expect(result.to_h[:isError]).to be_falsey
    end
  end

  describe "BundleDestroy" do
    let!(:bundle) { create(:bundle, name: "Friendly Bundle") }

    it "destroys by slug" do
      Mcp::Tools::BundleDestroy.call(id: bundle.to_param, confirm: "yes")
      expect(Bundle.where(id: bundle.id)).not_to exist
    end

    it "destroys by integer id (as string)" do
      bundle2 = create(:bundle, name: "Other Bundle")
      Mcp::Tools::BundleDestroy.call(id: bundle2.id.to_s, confirm: "yes")
      expect(Bundle.where(id: bundle2.id)).not_to exist
    end
  end

  describe "DeleteRecords (bulk)" do
    let!(:channel_a) do
      create(:channel,
             channel_url: "https://www.youtube.com/channel/UCDDDDDDDDDDDDDDDDDDDDDD")
    end
    let!(:channel_b) do
      create(:channel,
             channel_url: "https://www.youtube.com/channel/UCEEEEEEEEEEEEEEEEEEEEEE")
    end

    it "accepts a mix of slugs and integer-id strings" do
      result = Mcp::Tools::DeleteRecords.call(
        type: "channel",
        ids: [ channel_a.to_param, channel_b.id.to_s ],
        confirm: "no"
      )
      expect(result.to_h[:isError]).to be_falsey
      payload = JSON.parse(result.content.first[:text])
      expect(payload["total"]).to eq(2)
    end
  end

  describe "ListVideos" do
    let!(:channel) do
      create(:channel,
             channel_url: "https://www.youtube.com/channel/UCFFFFFFFFFFFFFFFFFFFFFF")
    end
    let!(:video) { create(:video, channel: channel, youtube_video_id: "vid_for_list") }

    it "filters by channel slug" do
      result = Mcp::Tools::ListVideos.call(channel_id: channel.to_param)
      payload = JSON.parse(result.content.first[:text])
      expect(payload).to be_an(Array)
      expect(payload.map { |v| v["id"] }).to include(video.id)
    end

    it "filters by channel integer-id string" do
      result = Mcp::Tools::ListVideos.call(channel_id: channel.id.to_s)
      payload = JSON.parse(result.content.first[:text])
      expect(payload).to be_an(Array)
      expect(payload.map { |v| v["id"] }).to include(video.id)
    end
  end
end
