# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Shinies do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  def handler_for(*words, follow_up: nil)
    described_class.new(
      message:      Pito::Chat::Message.new(
        tool:         :shinies,
        body_tokens:  tokens(*words),
        kind:         :new_turn,
        raw:          "shinies #{words.join(' ')}"
      ),
      conversation: Conversation.singleton,
      follow_up:    follow_up
    )
  end

  def follow_up_for(payload, rest: "")
    source_event = instance_double("Event", payload: payload)
    Pito::Chat::FollowUpContext.new(source_event: source_event, rest: rest)
  end

  let!(:channel) { create(:channel, handle: "@pito", title: "Pito Channel") }
  let!(:video)   { create(:video,   channel: channel, title: "Boss Rush") }
  let!(:game)    { create(:game,    title: "Lies of P") }

  # ── Channel branch ─────────────────────────────────────────────────────────────

  describe "channel resolution" do
    it "resolves channel by @handle" do
      payload = handler_for("channel", "@pito").call.events.first[:payload]
      expect(payload["body"]).to include("pito-achievement-shinies")
      expect(payload["channel_id"]).to eq(channel.id)
    end

    it "resolves channel by handle without @ prefix" do
      payload = handler_for("channel", "pito").call.events.first[:payload]
      expect(payload["channel_id"]).to eq(channel.id)
    end

    it "resolves channel case-insensitively" do
      payload = handler_for("channel", "@PITO").call.events.first[:payload]
      expect(payload["channel_id"]).to eq(channel.id)
    end

    it "returns not_found for unknown channel" do
      result = handler_for("channel", "@unknown").call
      expect(result.events.first[:payload]["text"]).to include("@unknown")
    end

    it "returns a needs_ref error when no handle given" do
      result = handler_for("channel").call
      expect(result).to be_a(Pito::Chat::Result::Error)
    end

    it "does NOT stamp a follow-up handle (shinies messages are not repliable)" do
      payload = handler_for("channel", "@pito").call.events.first[:payload]
      expect(Pito::FollowUp.followupable?(payload)).to be(false)
      expect(payload["reply_handle"]).to be_nil
      expect(payload["reply_target"]).to be_nil
    end

    it "emits a single :system event" do
      events = handler_for("channel", "@pito").call.events
      expect(events.size).to eq(1)
      expect(events.first[:kind]).to eq(:system)
    end
  end

  # ── Video branch ───────────────────────────────────────────────────────────────

  describe "video resolution" do
    # A noun filler is required to route to the video branch (same as `show`).
    # Bare IDs without a noun route to the game handler.
    it "resolves video by #id with vid noun filler" do
      payload = handler_for("vid", "##{video.id}").call.events.first[:payload]
      expect(payload["body"]).to include("pito-achievement-shinies")
      expect(payload["video_id"]).to eq(video.id)
    end

    it "resolves video by bare id with vid noun filler" do
      payload = handler_for("vid", video.id.to_s).call.events.first[:payload]
      expect(payload["video_id"]).to eq(video.id)
    end

    it "resolves video by id with vid noun filler (explicit)" do
      payload = handler_for("vid", video.id.to_s).call.events.first[:payload]
      expect(payload["video_id"]).to eq(video.id)
    end

    it "resolves video by id with video noun filler" do
      payload = handler_for("video", video.id.to_s).call.events.first[:payload]
      expect(payload["video_id"]).to eq(video.id)
    end

    it "returns not_found for unknown video ref" do
      result = handler_for("vid", "99999").call
      expect(result.events.first[:payload]["text"]).to be_present
    end

    it "rejects title refs (id-only resolution)" do
      result = handler_for("vid", "Boss Rush").call
      expect(result.events.first[:payload]["text"]).to be_present
    end

    it "does NOT stamp a follow-up handle for video (shinies messages are not repliable)" do
      payload = handler_for("vid", video.id.to_s).call.events.first[:payload]
      expect(Pito::FollowUp.followupable?(payload)).to be(false)
      expect(payload["reply_handle"]).to be_nil
      expect(payload["reply_target"]).to be_nil
    end
  end

  # ── Game branch ────────────────────────────────────────────────────────────────

  describe "game resolution" do
    it "resolves game by #id" do
      payload = handler_for("##{game.id}").call.events.first[:payload]
      expect(payload["body"]).to include("pito-achievement-shinies")
      expect(payload["game_id"]).to eq(game.id)
    end

    it "resolves game by bare id" do
      payload = handler_for(game.id.to_s).call.events.first[:payload]
      expect(payload["game_id"]).to eq(game.id)
    end

    it "resolves game by id with game noun filler" do
      payload = handler_for("game", game.id.to_s).call.events.first[:payload]
      expect(payload["game_id"]).to eq(game.id)
    end

    it "rejects title refs (id-only resolution)" do
      result = handler_for("game", "Lies of P").call
      expect(result.events.first[:payload]["text"]).to be_present
    end

    it "returns a needs_ref error when no ref given" do
      result = handler_for.call
      expect(result).to be_a(Pito::Chat::Result::Error)
    end

    it "does NOT stamp a follow-up handle for game (shinies messages are not repliable)" do
      payload = handler_for("##{game.id}").call.events.first[:payload]
      expect(Pito::FollowUp.followupable?(payload)).to be(false)
      expect(payload["reply_handle"]).to be_nil
      expect(payload["reply_target"]).to be_nil
    end
  end

  # ── Reply-context resolution ───────────────────────────────────────────────────

  describe "follow-up context" do
    context "replying to a game detail" do
      it "infers game from payload game_id" do
        fu = follow_up_for({ "game_id" => game.id, "reply_target" => "game_detail" }, rest: "")
        payload = handler_for(follow_up: fu).call.events.first[:payload]
        expect(payload["game_id"]).to eq(game.id)
        expect(payload["body"]).to include("pito-achievement-shinies")
      end
    end

    context "replying to a video detail" do
      it "infers video from payload video_id" do
        fu = follow_up_for({ "video_id" => video.id, "reply_target" => "video_detail" }, rest: "")
        payload = handler_for(follow_up: fu).call.events.first[:payload]
        expect(payload["video_id"]).to eq(video.id)
        expect(payload["body"]).to include("pito-achievement-shinies")
      end
    end

    context "replying to a channel list" do
      it "resolves channel from @handle in follow_up.rest" do
        fu = follow_up_for({ "reply_target" => "channel_list" }, rest: "@pito")
        payload = handler_for(follow_up: fu).call.events.first[:payload]
        expect(payload["channel_id"]).to eq(channel.id)
      end

      it "returns needs_ref when rest is blank" do
        fu = follow_up_for({ "reply_target" => "channel_list" }, rest: "")
        result = handler_for(follow_up: fu).call
        expect(result).to be_a(Pito::Chat::Result::Error)
      end
    end

    context "replying to a game list" do
      let!(:game2) { create(:game, title: "Other Game") }

      it "resolves game from the id within follow_up.rest" do
        payload_data = {
          "reply_target" => "game_list",
          "table_rows"   => [ { "cells" => [ { "text" => "##{game.id}" } ] } ]
        }
        fu = follow_up_for(payload_data, rest: "##{game.id}")
        payload = handler_for(follow_up: fu).call.events.first[:payload]
        expect(payload["game_id"]).to eq(game.id)
      end
    end
  end

  # ── --help ────────────────────────────────────────────────────────────────────

  describe "--help" do
    it "returns man-style html for shinies --help" do
      result = Pito::Dispatch::Router.call(
        input:        "shinies --help",
        conversation: Conversation.singleton
      )
      payload = result.events.first[:payload]
      expect(payload["html"]).to be(true)
      expect(payload["body"]).to include("shinies")
    end

    it "returns noun-level help for shinies game --help" do
      result = Pito::Dispatch::Router.call(
        input:        "shinies game --help",
        conversation: Conversation.singleton
      )
      payload = result.events.first[:payload]
      expect(payload["html"]).to be(true)
      expect(payload["body"]).to include("game")
    end
  end
end
