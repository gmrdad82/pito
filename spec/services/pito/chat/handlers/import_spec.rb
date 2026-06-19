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

  # ── bare import → usage hint ─────────────────────────────────────────────────

  it "returns a Result::Error with the usage_hint key for bare import" do
    result = handler_for.call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.import.usage_hint")
  end

  it "returns the usage_hint for unrecognised nouns" do
    result = handler_for("import something random").call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.import.usage_hint")
  end

  # ── import game / import games ────────────────────────────────────────────────

  context "import game (sidebar path)" do
    it "returns Result::Ok for 'import game'" do
      result = handler_for("import game").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    it "emits a system event with sidebar_open: 'games_import'" do
      event = handler_for("import game").call.events.first
      payload = event[:payload]
      expect(payload[:sidebar_open] || payload["sidebar_open"]).to eq("games_import")
    end

    it "sets prefill to empty string when no title given" do
      event = handler_for("import game").call.events.first
      payload = event[:payload]
      prefill = payload[:prefill] || payload["prefill"]
      expect(prefill.to_s).to be_empty
    end

    it "sets prefill to the title when a title is given" do
      event = handler_for("import game Hollow Knight").call.events.first
      payload = event[:payload]
      prefill = payload[:prefill] || payload["prefill"]
      expect(prefill).to eq("Hollow Knight")
    end

    it "handles 'import games' (plural) with a title" do
      event = handler_for("import games Dead Cells").call.events.first
      payload = event[:payload]
      prefill = payload[:prefill] || payload["prefill"]
      expect(prefill).to eq("Dead Cells")
    end
  end

  # ── import videos — @all scope ────────────────────────────────────────────────

  context "import videos" do
    let!(:connection) { create(:youtube_connection) }
    let!(:channel)    { create(:channel, handle: "@pito", youtube_connection: connection) }

    it "emits the sync_videos confirmation for bare 'import videos' (true alias)" do
      result = handler_for("import videos").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("sync_videos")
    end

    it "carries an empty channel_ids array for @all scope" do
      payload = handler_for("import videos", channel: "@all").call.events.first[:payload]
      expect(payload["channel_ids"]).to eq([])
      expect(payload["scope_label"]).to eq("all channels")
    end

    it "accepts the canonical short noun 'import vids'" do
      event = handler_for("import vids").call.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("sync_videos")
    end

    it "accepts the singular short noun 'import vid'" do
      event = handler_for("import vid").call.events.first
      expect(event[:payload]["command"]).to eq("sync_videos")
    end

    it "scopes to the specific shift+tab channel" do
      payload = handler_for("import videos", channel: "@pito").call.events.first[:payload]
      expect(payload["channel_ids"]).to eq([ channel.id ])
    end

    it "stamps the payload as follow-up-able" do
      payload = handler_for("import videos").call.events.first[:payload]
      expect(Pito::FollowUp.followupable?(payload)).to be(true)
      expect(payload["reply_target"]).to eq("confirmation")
    end

    it "returns a system error event for unknown shift+tab handle" do
      result = handler_for("import videos", channel: "@unknown_xyz").call
      expect(result.events.first[:kind]).to eq(:system)
    end

    # ── for @handle override ──────────────────────────────────────────────────

    context "for @handle override" do
      it "overrides shift+tab @all scope with the for-handle channel" do
        payload = handler_for("import videos for @pito", channel: "@all").call.events.first[:payload]
        expect(payload["channel_ids"]).to eq([ channel.id ])
      end

      it "overrides a different shift+tab channel with the for-handle channel" do
        other_connection = create(:youtube_connection)
        other = create(:channel, handle: "@other", youtube_connection: other_connection)
        payload = handler_for("import videos for @pito", channel: "@other").call.events.first[:payload]
        expect(payload["channel_ids"]).to eq([ channel.id ])
      end

      it "scopes correctly with no shift+tab channel (blank), using for @handle" do
        payload = handler_for("import videos for @pito").call.events.first[:payload]
        expect(payload["channel_ids"]).to eq([ channel.id ])
      end

      it "returns a system error event for an unknown for-handle" do
        result = handler_for("import videos for @nobody", channel: "@all").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end
  end
end
