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
  let!(:game)       { create(:game, title: "Elden Ring") }
  let!(:video)      { create(:video, channel: channel, title: "Let's Play ER") }

  # ── Registry ──────────────────────────────────────────────────────────────────

  it "is registered in the chat registry" do
    expect(Pito::Chat::Registry.lookup(:sync)).to eq(described_class)
  end

  # ── sync game <ref> ───────────────────────────────────────────────────────────

  describe "sync game <ref>" do
    it "emits a confirmation event with command sync_game" do
      result = handler_for("game", "elden", "ring").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("sync_game")
      expect(event[:payload]["game_id"]).to eq(game.id)
      expect(event[:payload]["game_title"]).to eq("Elden Ring")
    end

    it "stamps the confirmation payload as follow-up-able" do
      payload = handler_for("game", "elden", "ring").call.events.first[:payload]
      expect(Pito::FollowUp.followupable?(payload)).to be(true)
      expect(payload["reply_target"]).to eq("confirmation")
    end

    it "carries conversation_id in the payload" do
      payload = handler_for("game", "elden", "ring").call.events.first[:payload]
      expect(payload["conversation_id"]).to eq(Conversation.singleton.id)
    end

    it "resolves game by #id" do
      result = handler_for("game", "##{game.id}").call
      expect(result.events.first[:payload]["game_id"]).to eq(game.id)
    end

    it "returns a not-found system event for unknown game" do
      result = handler_for("game", "nonexistent").call
      expect(result.events.first[:payload]["text"]).to include("nonexistent")
    end

    it "returns an error when no ref is given" do
      result = handler_for.call
      expect(result).to be_a(Pito::Chat::Result::Error)
    end
  end

  # ── sync video <ref> ──────────────────────────────────────────────────────────

  describe "sync video <ref>" do
    it "emits a confirmation event with command sync_video" do
      result = handler_for("video", "let's", "play", "er").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("sync_video")
      expect(event[:payload]["video_id"]).to eq(video.id)
      expect(event[:payload]["video_title"]).to eq("Let's Play ER")
    end

    it "stamps the confirmation payload as follow-up-able" do
      payload = handler_for("video", "##{video.id}").call.events.first[:payload]
      expect(Pito::FollowUp.followupable?(payload)).to be(true)
    end

    it "returns a not-found system event for unknown video" do
      result = handler_for("video", "nope").call
      expect(result.events.first[:payload]["text"]).to include("nope")
    end
  end

  # ── sync videos (scope: @all) ─────────────────────────────────────────────────

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
  end

  # ── sync videos (scope: @handle) ─────────────────────────────────────────────

  describe "sync videos — @pito scope" do
    it "emits a confirmation event with command sync_videos and channel_ids" do
      result = handler_for("videos", channel: "@pito").call
      event  = result.events.first
      expect(event[:payload]["command"]).to eq("sync_videos")
      expect(event[:payload]["channel_ids"]).to eq([ channel.id ])
    end
  end

  # ── sync videos — unknown handle ─────────────────────────────────────────────

  describe "sync videos — unknown handle" do
    it "returns a system error event" do
      result = handler_for("videos", channel: "@unknown_channel_xyz").call
      expect(result.events.first[:kind]).to eq(:system)
    end
  end

  # ── sync channel ─────────────────────────────────────────────────────────────

  describe "sync channel" do
    it "emits a confirmation event with command sync_channel" do
      result = handler_for("channel", channel: "@pito").call
      event  = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("sync_channel")
      expect(event[:payload]["channel_ids"]).to eq([ channel.id ])
    end

    it "carries @all scope when no specific handle given" do
      result = handler_for("channel").call
      payload = result.events.first[:payload]
      expect(payload["command"]).to eq("sync_channel")
      expect(payload["channel_ids"]).to eq([])
    end
  end

  # ── sync channel with videos ──────────────────────────────────────────────────

  describe "sync channel with videos" do
    it "emits a confirmation event with command sync_channel_videos" do
      result = handler_for("channel", "with", "videos", channel: "@pito").call
      event  = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("sync_channel_videos")
      expect(event[:payload]["channel_ids"]).to eq([ channel.id ])
    end

    it "works with @all scope" do
      result = handler_for("channel", "with", "videos").call
      expect(result.events.first[:payload]["command"]).to eq("sync_channel_videos")
      expect(result.events.first[:payload]["channel_ids"]).to eq([])
    end
  end
end
