require "rails_helper"
require_relative "../../../app/mcp/tools/channel_diff_apply"

# Phase 7.5 §11i — MCP tool: channel_diff_apply.
RSpec.describe Mcp::Tools::ChannelDiffApply do
  let(:user) { Current.user }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv",
           title: "local title",
           youtube_connection: create(:youtube_connection, user: user))
  end

  let!(:diff) do
    create(:channel_diff, channel: channel, field_diffs: {
      "title" => { "pito" => "local title", "youtube" => "remote title" }
    })
  end

  it "is gated on the app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(id: channel.to_param,
                                  decisions: { "title" => "youtube" },
                                  confirm: "yes")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end

  it "returns a preview when confirm is not 'yes'" do
    result = described_class.call(id: channel.to_param,
                                  decisions: { "title" => "youtube" })
    json = JSON.parse(result.content.first[:text])
    expect(json["preview"]).to be(true)
    expect(json["channel_id"]).to eq(channel.id)
    expect(diff.reload.resolved_at).to be_nil
  end

  it "returns a preview when confirm is 'no'" do
    result = described_class.call(id: channel.to_param,
                                  decisions: { "title" => "youtube" },
                                  confirm: "no")
    json = JSON.parse(result.content.first[:text])
    expect(json["preview"]).to be(true)
  end

  it "applies youtube-wins on confirm: yes" do
    result = described_class.call(id: channel.to_param,
                                  decisions: { "title" => "youtube" },
                                  confirm: "yes")
    json = JSON.parse(result.content.first[:text])
    expect(json["ok"]).to be(true)
    expect(json["youtube_wins_fields"]).to eq([ "title" ])
    expect(channel.reload.title).to eq("remote title")
    expect(diff.reload.resolved_at).to be_present
  end

  it "returns an error when there's no open diff" do
    diff.update!(resolved_at: 1.minute.ago,
                 resolution_payload: { "title" => { "decision" => "youtube" } })
    result = described_class.call(id: channel.to_param,
                                  decisions: { "title" => "youtube" },
                                  confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to include("no open diff")
  end

  it "returns an error when the channel is not found" do
    result = described_class.call(id: "no-such-channel",
                                  decisions: { "title" => "youtube" },
                                  confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to include("channel not found")
  end

  it "surfaces apply errors from the orchestrator (stale diff)" do
    result = described_class.call(
      id: channel.to_param,
      decisions: { "title" => "youtube", "extra" => "youtube" },
      confirm: "yes"
    )
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to include("apply failed").or include("stale_diff")
  end
end
