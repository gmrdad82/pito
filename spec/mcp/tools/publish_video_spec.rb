require "rails_helper"
require_relative "../../../app/mcp/tools/publish_video"

RSpec.describe Mcp::Tools::PublishVideo do
  let!(:channel) { create(:channel) }

  it "publishes a pre-checked private video to public" do
    v = create(:video, :pre_publish_complete, channel: channel, title: "ok", category_id: "20")
    described_class.call(id: v.id, target: "public", confirm: "yes")
    expect(v.reload.privacy_public?).to be(true)
  end

  it "publishes a pre-checked private video to unlisted" do
    v = create(:video, :pre_publish_complete, channel: channel, title: "ok", category_id: "20")
    described_class.call(id: v.id, target: "unlisted", confirm: "yes")
    expect(v.reload.privacy_unlisted?).to be(true)
  end

  it "schedules with target=scheduled + future publish_at" do
    v = create(:video, :pre_publish_complete, channel: channel, title: "ok", category_id: "20")
    future = 1.day.from_now
    described_class.call(id: v.id, target: "scheduled", publish_at: future.iso8601, confirm: "yes")
    v.reload
    expect(v.privacy_private?).to be(true)
    expect(v.publish_at).to be_within(2.seconds).of(future)
  end

  it "rejects target=scheduled without publish_at" do
    v = create(:video, :pre_publish_complete, channel: channel, title: "ok", category_id: "20")
    result = described_class.call(id: v.id, target: "scheduled", confirm: "yes")
    expect(result.to_h[:isError]).to be true
  end

  it "rejects target=scheduled with past publish_at" do
    v = create(:video, :pre_publish_complete, channel: channel, title: "ok", category_id: "20")
    result = described_class.call(id: v.id, target: "scheduled", publish_at: 1.day.ago.iso8601, confirm: "yes")
    expect(result.to_h[:isError]).to be true
  end

  it "rejects when pre-publish is incomplete (lists missing checks)" do
    v = create(:video, channel: channel, title: "ok", category_id: "20") # NOT :pre_publish_complete
    result = described_class.call(id: v.id, target: "public", confirm: "yes")
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("game_ok")
  end

  it "rejects unknown target" do
    v = create(:video, :pre_publish_complete, channel: channel, title: "ok", category_id: "20")
    result = described_class.call(id: v.id, target: "evil", confirm: "yes")
    expect(result.to_h[:isError]).to be true
  end

  it "rejects when video is already public" do
    v = create(:video, :public, channel: channel, title: "ok", category_id: "20")
    result = described_class.call(id: v.id, target: "public", confirm: "yes")
    expect(result.to_h[:isError]).to be true
  end

  it "returns dry-run preview when confirm=no" do
    v = create(:video, :pre_publish_complete, channel: channel, title: "ok", category_id: "20")
    result = described_class.call(id: v.id, target: "public", confirm: "no")
    expect(result.content.first[:text]).to include("proposed")
    expect(v.reload.privacy_private?).to be(true)
  end

  it "returns error for missing video" do
    result = described_class.call(id: 99999, target: "public", confirm: "yes")
    expect(result.to_h[:isError]).to be true
  end

  describe "scope gate" do
    it "rejects dev-only token" do
      record, _plaintext = ApiToken.generate!(
        user: User.first || create(:user),
        name: "dev-only",
        scopes: [ Scopes::DEV ]
      )
      Current.token = record

      v = create(:video, :pre_publish_complete, channel: channel, title: "ok", category_id: "20")
      result = described_class.call(id: v.id, target: "public", confirm: "yes")
      expect(result.to_h[:isError]).to be true
      expect(result.content.first[:text]).to include("insufficient_scope")
    end
  end
end
