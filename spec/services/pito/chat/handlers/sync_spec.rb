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

  # ── sync vids / vid — canonical + short alias ─────────────────────────────────

  describe "sync vids / vid (canonical short forms)" do
    it "routes `sync vids` to the videos form" do
      result = handler_for("vids", channel: "@all").call
      event  = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("sync_videos")
    end

    it "routes the singular `sync vid` to the videos form" do
      result = handler_for("vid", channel: "@all").call
      expect(result.events.first[:payload]["command"]).to eq("sync_videos")
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

  # ── sync vids #id (targeted — ids win over shift+tab scope) ───────────────────

  describe "sync vids #id (targeted)" do
    let!(:video2) { create(:video, channel: channel, title: "Boss Fight") }

    it "targets the single #id video" do
      payload = handler_for("vids", "##{video.id}", channel: "@all").call.events.first[:payload]
      expect(payload["command"]).to eq("sync_videos")
      expect(payload["video_ids"]).to eq([ video.id ])
    end

    it "parses a comma-separated #id list" do
      payload = handler_for("vids", "##{video.id},##{video2.id}", channel: "@all").call.events.first[:payload]
      expect(payload["video_ids"]).to eq([ video.id, video2.id ])
    end

    it "ids win — ignores the shift+tab channel scope (channel_ids empty)" do
      payload = handler_for("vids", "##{video.id}", channel: "@pito").call.events.first[:payload]
      expect(payload["video_ids"]).to eq([ video.id ])
      expect(payload["channel_ids"]).to eq([])
    end

    it "names the targeted vids in the confirmation body (not 'all vids')" do
      body = handler_for("vids", "##{video.id}", channel: "@all").call.events.first[:payload]["body"]
      expect(body).to include("##{video.id}")
    end

    %w[vid video videos].each do |noun|
      it "recognizes the `#{noun}` alias with #id" do
        payload = handler_for(noun, "##{video.id}", channel: "@all").call.events.first[:payload]
        expect(payload["video_ids"]).to eq([ video.id ])
      end
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

    it "accepts the `with vids` short alias" do
      payload = handler_for("channels", "with", "vids", channel: "@pito").call.events.first[:payload]
      expect(payload["command"]).to eq("sync_channel_videos")
    end
  end

  # ── sync channels with videos,<unknown> — unknown tokens dropped ──────────────
  # `analytics` was removed from WITH_ITEMS_VOCAB in 0.7.5 (revisited in 0.8.0);
  # it's now just an unknown token, silently dropped like any other.

  describe "sync channels with videos,analytics (analytics now unknown)" do
    it "parses without error" do
      result = handler_for("channels", "with", "videos,analytics").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    it "keeps only the known item (videos); drops analytics" do
      payload = handler_for("channels", "with", "videos,analytics").call.events.first[:payload]
      expect(payload["with_items"]).to include("videos")
      expect(payload["with_items"]).not_to include("analytics")
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

  # ── Follow-up: `#<handle> sync` on a detail card → sync that entity ────────────

  describe "sync — follow-up reply on a detail card" do
    let!(:game) { create(:game, title: "Hollow Knight") }

    def follow_up_handler(source_payload, rest: "")
      source_event = instance_double(Event, payload: source_payload)
      ctx = Pito::Chat::FollowUpContext.new(source_event:, rest:)
      described_class.new(
        message:      instance_double(Pito::Chat::Message),
        conversation: Conversation.singleton,
        follow_up:    ctx
      )
    end

    it "syncs the source video on a video_detail reply" do
      payload = follow_up_handler({ "video_id" => video.id, "reply_target" => "video_detail" }).call.events.first[:payload]
      expect(payload["command"]).to eq("sync_videos")
      expect(payload["video_ids"]).to eq([ video.id ])
      expect(payload["channel_ids"]).to eq([])
    end

    it "syncs the source channel on a channel_detail reply" do
      payload = follow_up_handler({ "channel_id" => channel.id, "reply_target" => "channel_detail" }).call.events.first[:payload]
      expect(payload["command"]).to eq("sync_channel")
      expect(payload["channel_ids"]).to eq([ channel.id ])
    end

    it "syncs the source game on a game_detail reply" do
      payload = follow_up_handler({ "game_id" => game.id, "reply_target" => "game_detail" }).call.events.first[:payload]
      expect(payload["command"]).to eq("sync_game")
      expect(payload["game_id"]).to eq(game.id)
    end

    it "ignores trailing args — still targets the source video" do
      payload = follow_up_handler({ "video_id" => video.id, "reply_target" => "video_detail" }, rest: "whatever").call.events.first[:payload]
      expect(payload["command"]).to eq("sync_videos")
      expect(payload["video_ids"]).to eq([ video.id ])
    end

    it "returns a needs_ref error for an unknown reply_target" do
      result = follow_up_handler({ "reply_target" => "something_else" }).call
      expect(result).to be_a(Pito::Chat::Result::Error)
    end
  end
end
