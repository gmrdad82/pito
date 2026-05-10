require "rails_helper"
require_relative "../../../app/mcp/tools/pre_publish_check_video"

RSpec.describe Mcp::Tools::PrePublishCheckVideo do
  let!(:channel) { create(:channel) }

  it "applies all four booleans + stamps timestamp with confirm=yes" do
    v = create(:video, channel: channel)
    described_class.call(
      id: v.id,
      game_ok: "yes", age_ok: "yes",
      paid_promotion_ok: "yes", end_screen_ok: "yes",
      confirm: "yes"
    )
    v.reload
    expect(v.pre_publish_game_ok).to be(true)
    expect(v.pre_publish_age_ok).to be(true)
    expect(v.pre_publish_paid_promotion_ok).to be(true)
    expect(v.pre_publish_end_screen_ok).to be(true)
    expect(v.pre_publish_checked_at).to be_within(2.seconds).of(Time.current)
  end

  it "returns dry-run preview when confirm=no" do
    v = create(:video, channel: channel)
    result = described_class.call(
      id: v.id,
      game_ok: "yes", age_ok: "yes",
      paid_promotion_ok: "yes", end_screen_ok: "yes",
      confirm: "no"
    )
    expect(result.content.first[:text]).to include("proposed")
    v.reload
    expect(v.pre_publish_game_ok).to be(false)
    expect(v.pre_publish_checked_at).to be_nil
  end

  it "rejects raw booleans (must be yes/no)" do
    v = create(:video, channel: channel)
    result = described_class.call(
      id: v.id,
      game_ok: true, age_ok: "yes",
      paid_promotion_ok: "yes", end_screen_ok: "yes",
      confirm: "yes"
    )
    expect(result.to_h[:isError]).to be true
  end

  it "returns error for missing video" do
    result = described_class.call(
      id: 99999,
      game_ok: "yes", age_ok: "yes",
      paid_promotion_ok: "yes", end_screen_ok: "yes",
      confirm: "yes"
    )
    expect(result.to_h[:isError]).to be true
  end

  describe "scope gate" do
    it "returns insufficient_scope when token lacks `app`" do
      record, _plaintext = ApiToken.generate!(
        user: User.first || create(:user),
        name: "dev-only",
        scopes: [ Scopes::DEV ]
      )
      Current.token = record

      v = create(:video, channel: channel)
      result = described_class.call(
        id: v.id,
        game_ok: "yes", age_ok: "yes",
        paid_promotion_ok: "yes", end_screen_ok: "yes",
        confirm: "yes"
      )
      expect(result.to_h[:isError]).to be true
    end
  end
end
