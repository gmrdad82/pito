# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Sync do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  def handler_for(*words, channel: nil)
    raw = "sync #{words.join(' ')}".strip
    described_class.new(
      message:      Pito::Chat::Message.new(
        verb: :sync, body_tokens: tokens(*words), kind: :new_turn, raw: raw
      ),
      conversation: Conversation.singleton,
      channel:      channel
    )
  end

  let!(:connection) { create(:youtube_connection) }
  let!(:channel)    { create(:channel, handle: "@pito", youtube_connection: connection) }
  let!(:video)      { create(:video, channel: channel, title: "Let's Play ER") }

  # ── Registry ──────────────────────────────────────────────────────────────────

  it "is registered in the chat registry" do
    expect(Pito::Chat::Registry.lookup(:sync)).to eq(described_class)
  end

  # ── needs_ref fallback ────────────────────────────────────────────────────────

  describe "unknown/missing noun" do
    it "returns an error when no noun is given" do
      result = handler_for.call
      expect(result).to be_a(Pito::Chat::Result::Error)
    end

    it "returns an error for an unrecognised noun" do
      result = handler_for("game", "elden", "ring").call
      expect(result).to be_a(Pito::Chat::Result::Error)
    end
  end

  # ── sync videos — @all scope ──────────────────────────────────────────────────

  describe "sync videos — @all scope" do
    it "emits a confirmation event with command sync_videos" do
      result = handler_for("videos", channel: "@all").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("sync_videos")
    end

    it "carries an empty channel_ids array for @all" do
      payload = handler_for("videos", channel: "@all").call.events.first[:payload]
      expect(payload["channel_ids"]).to eq([])
    end

    it "carries an empty video_ids array when no only clause" do
      payload = handler_for("videos", channel: "@all").call.events.first[:payload]
      expect(payload["video_ids"]).to eq([])
    end

    it "stamps the payload as follow-up-able" do
      payload = handler_for("videos", channel: "@all").call.events.first[:payload]
      expect(Pito::FollowUp.followupable?(payload)).to be(true)
      expect(payload["reply_target"]).to eq("confirmation")
    end

    it "carries conversation_id in the payload" do
      payload = handler_for("videos", channel: "@all").call.events.first[:payload]
      expect(payload["conversation_id"]).to eq(Conversation.singleton.id)
    end
  end

  # ── sync videos — @handle scope ───────────────────────────────────────────────

  describe "sync videos — @pito scope" do
    it "emits sync_videos with the resolved channel_ids" do
      result = handler_for("videos", channel: "@pito").call
      event  = result.events.first
      expect(event[:payload]["command"]).to eq("sync_videos")
      expect(event[:payload]["channel_ids"]).to eq([ channel.id ])
    end
  end

  # ── sync videos only <ids> ────────────────────────────────────────────────────

  describe "sync videos only <ids>" do
    it "carries the parsed video_ids in the payload" do
      payload = handler_for("videos", "only", "#{video.id}", channel: "@all").call.events.first[:payload]
      expect(payload["video_ids"]).to eq([ video.id ])
    end

    it "parses a comma-separated list of ids" do
      payload = handler_for("videos", "only", "1,2,3", channel: "@all").call.events.first[:payload]
      expect(payload["video_ids"]).to eq([ 1, 2, 3 ])
    end

    it "still emits sync_videos command" do
      payload = handler_for("videos", "only", "1", channel: "@all").call.events.first[:payload]
      expect(payload["command"]).to eq("sync_videos")
    end
  end

  # ── sync videos — unknown handle ──────────────────────────────────────────────

  describe "sync videos — unknown handle" do
    it "returns a system error event" do
      result = handler_for("videos", channel: "@unknown_channel_xyz").call
      expect(result.events.first[:kind]).to eq(:system)
    end
  end

  # ── sync channels — @all scope ────────────────────────────────────────────────

  describe "sync channels — @all scope" do
    it "emits a confirmation event with command sync_channel" do
      result = handler_for("channels").call
      event  = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("sync_channel")
    end

    it "carries an empty channel_ids array for @all" do
      payload = handler_for("channels").call.events.first[:payload]
      expect(payload["channel_ids"]).to eq([])
    end

    it "carries an empty with_items array when no with clause" do
      payload = handler_for("channels").call.events.first[:payload]
      expect(payload["with_items"]).to eq([])
    end
  end

  # ── sync channels — @handle scope ─────────────────────────────────────────────

  describe "sync channels — @pito scope" do
    it "emits sync_channel with the resolved channel_ids" do
      result  = handler_for("channels", channel: "@pito").call
      payload = result.events.first[:payload]
      expect(payload["command"]).to eq("sync_channel")
      expect(payload["channel_ids"]).to eq([ channel.id ])
    end
  end

  # ── sync channels with videos ─────────────────────────────────────────────────

  describe "sync channels with videos" do
    it "emits a confirmation event with command sync_channel_videos" do
      result  = handler_for("channels", "with", "videos", channel: "@pito").call
      payload = result.events.first[:payload]
      expect(payload["command"]).to eq("sync_channel_videos")
      expect(payload["channel_ids"]).to eq([ channel.id ])
    end

    it "works with @all scope" do
      result = handler_for("channels", "with", "videos").call
      expect(result.events.first[:payload]["command"]).to eq("sync_channel_videos")
      expect(result.events.first[:payload]["channel_ids"]).to eq([])
    end

    it "carries with_items including :videos as string" do
      payload = handler_for("channels", "with", "videos").call.events.first[:payload]
      expect(payload["with_items"]).to include("videos")
    end
  end

  # ── sync channels with videos,analytics (future extension) ────────────────────

  describe "sync channels with videos,analytics" do
    it "parses both items without error" do
      result = handler_for("channels", "with", "videos,analytics").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    it "carries both items in with_items" do
      payload = handler_for("channels", "with", "videos,analytics").call.events.first[:payload]
      expect(payload["with_items"]).to include("videos", "analytics")
    end

    it "still emits sync_channel_videos (videos is present)" do
      payload = handler_for("channels", "with", "videos,analytics").call.events.first[:payload]
      expect(payload["command"]).to eq("sync_channel_videos")
    end
  end

  # ── sync channels — unknown handle ────────────────────────────────────────────

  describe "sync channels — unknown handle" do
    it "returns a system error event" do
      result = handler_for("channels", channel: "@unknown_xyz").call
      expect(result.events.first[:kind]).to eq(:system)
    end
  end

  # ── dash-prefixed flags are NOT valid nouns ────────────────────────────────────

  describe "sync --videos (flag, not a noun)" do
    it "returns a needs_ref error, not a sync_videos confirmation" do
      result = handler_for("--videos").call
      expect(result).to be_a(Pito::Chat::Result::Error)
    end

    it "does not enqueue SyncVideosJob" do
      allow(SyncVideosJob).to receive(:perform_later)
      handler_for("--videos").call
      expect(SyncVideosJob).not_to have_received(:perform_later)
    end
  end

  describe "sync --channels (flag, not a noun)" do
    it "returns a needs_ref error, not a sync_channel confirmation" do
      result = handler_for("--channels").call
      expect(result).to be_a(Pito::Chat::Result::Error)
    end

    it "does not enqueue SyncChannelJob" do
      allow(SyncChannelJob).to receive(:perform_later)
      handler_for("--channels").call
      expect(SyncChannelJob).not_to have_received(:perform_later)
    end
  end
end
