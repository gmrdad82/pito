# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Import do
  def handler_for(raw = "import", channel: nil)
    described_class.new(
      message: Pito::Chat::Message.new(
        verb: :import,
        body_tokens: [],
        kind: :new_turn,
        raw: raw
      ),
      conversation: Conversation.singleton,
      channel:      channel
    )
  end

  # ── bare import / import game → usage hint ───────────────────────────────────

  it "returns a Result::Error with the usage_hint key for bare import" do
    result = handler_for.call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.import.usage_hint")
  end

  it "returns the usage_hint for any non-videos import input" do
    result = handler_for("import something random").call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.import.usage_hint")
  end

  # ── import videos — @all scope ────────────────────────────────────────────────

  context "import videos" do
    let!(:connection) { create(:youtube_connection) }
    let!(:channel)    { create(:channel, handle: "@pito", youtube_connection: connection) }

    it "emits a confirmation event with command import_videos for bare 'import videos'" do
      result = handler_for("import videos").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("import_videos")
    end

    it "carries an empty channel_ids array for @all scope" do
      payload = handler_for("import videos", channel: "@all").call.events.first[:payload]
      expect(payload["channel_ids"]).to eq([])
      expect(payload["scope_label"]).to eq("all channels")
    end

    it "resolves a specific channel handle" do
      payload = handler_for("import videos", channel: "@pito").call.events.first[:payload]
      expect(payload["channel_ids"]).to eq([ channel.id ])
    end

    it "stamps the payload as follow-up-able" do
      payload = handler_for("import videos").call.events.first[:payload]
      expect(Pito::FollowUp.followupable?(payload)).to be(true)
      expect(payload["reply_target"]).to eq("confirmation")
    end

    it "returns a system error event for unknown handle" do
      result = handler_for("import videos", channel: "@unknown_xyz").call
      expect(result.events.first[:kind]).to eq(:system)
    end
  end
end
