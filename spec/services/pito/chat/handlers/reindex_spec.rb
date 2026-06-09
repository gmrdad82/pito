# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Reindex do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  def handler_for(*words)
    described_class.new(
      message: Pito::Chat::Message.new(verb: :reindex, body_tokens: tokens(*words), kind: :new_turn, raw: "reindex #{words.join(' ')}"),
      conversation: Conversation.singleton
    )
  end

  # ── Game branch ───────────────────────────────────────────────────────────────

  let!(:game) { create(:game, title: "Lies of P") }

  it "emits a confirmation event carrying the game_reindex command + id + title" do
    result = handler_for("game", "lies", "of", "p").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    event = result.events.first
    expect(event[:kind]).to eq(:confirmation)
    expect(event[:payload]["command"]).to eq("game_reindex")
    expect(event[:payload]["game_id"]).to eq(game.id)
    expect(event[:payload]["game_title"]).to eq("Lies of P")
  end

  it "resolves by id and stamps the confirmation follow-up-able" do
    payload = handler_for("##{game.id}").call.events.first[:payload]
    expect(Pito::FollowUp.followupable?(payload)).to be(true)
    expect(payload["reply_target"]).to eq("confirmation")
  end

  it "does NOT re-index the game yet (confirmation only)" do
    expect { handler_for("##{game.id}").call }.not_to change(Game, :count)
  end

  it "returns a witty not-found for an unknown game reference" do
    result = handler_for("game", "nope").call
    expect(result.events.first[:payload]["text"]).to include("nope")
  end

  it "returns a usage hint when no reference is given" do
    expect(handler_for.call).to be_a(Pito::Chat::Result::Error)
    expect(handler_for.call.message_key).to eq("pito.chat.reindex.needs_ref")
  end

  # ── Video branch ──────────────────────────────────────────────────────────────

  context "reindex video" do
    let!(:channel) { create(:channel) }
    let!(:video)   { create(:video, channel: channel, title: "Let's Play Elden Ring") }

    it "emits a confirmation event carrying the video_reindex command + id + title" do
      result = handler_for("video", "let's", "play", "elden", "ring").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("video_reindex")
      expect(event[:payload]["video_id"]).to eq(video.id)
      expect(event[:payload]["video_title"]).to eq("Let's Play Elden Ring")
    end

    it "resolves video by #id and stamps follow-up-able (reply_target: confirmation)" do
      payload = handler_for("video", "##{video.id}").call.events.first[:payload]
      expect(Pito::FollowUp.followupable?(payload)).to be(true)
      expect(payload["reply_target"]).to eq("confirmation")
    end

    it "resolves video by bare id" do
      result = handler_for("video", video.id.to_s).call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["video_id"]).to eq(video.id)
    end

    it "resolves by plural noun filler 'videos'" do
      result = handler_for("videos", video.id.to_s).call
      expect(result.events.first[:payload]["video_id"]).to eq(video.id)
    end

    it "returns a witty not-found for an unknown video reference" do
      result = handler_for("video", "nope").call
      expect(result.events.first[:payload]["text"]).to include("nope")
    end

    it "returns a usage hint when only the noun is given (no ref)" do
      result = handler_for("video").call
      expect(result).to be_a(Pito::Chat::Result::Error)
    end

    it "game reindex STILL works unchanged when the video noun is absent" do
      result = handler_for("game", "lies", "of", "p").call
      expect(result.events.first[:payload]["command"]).to eq("game_reindex")
    end

    context "video title with apostrophe resolved via real lexer/parser" do
      it "resolves via real lexer/parser" do
        result = Pito::Chat::Parser.call(
          Pito::Lex::Lexer.call("reindex video Let's Play Elden Ring"),
          raw: "reindex video Let's Play Elden Ring",
          conversation: Conversation.singleton
        )
        handler = described_class.new(message: result, conversation: Conversation.singleton)
        out = handler.call
        expect(out).to be_a(Pito::Chat::Result::Ok)
        expect(out.events.first[:payload]["video_id"]).to eq(video.id)
      end
    end
  end

  # ── Follow-up detail-context — game ──────────────────────────────────────────

  context "follow-up detail context — game" do
    let!(:game) { create(:game, title: "Lies of P") }

    it "emits a game_reindex confirmation when invoked from a game_detail follow-up context" do
      source_event = instance_double(
        Event,
        payload: { "game_id" => game.id, "reply_target" => "game_detail" }
      )
      ctx     = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "")
      handler = described_class.new(
        message:      instance_double(Pito::Chat::Message),
        conversation: Conversation.singleton,
        follow_up:    ctx
      )
      result = handler.call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("game_reindex")
      expect(event[:payload]["game_id"]).to eq(game.id)
    end
  end

  # ── Follow-up detail-context — video ─────────────────────────────────────────

  context "follow-up detail context — video" do
    let!(:channel) { create(:channel) }
    let!(:video)   { create(:video, channel: channel, title: "Let's Play Elden Ring") }

    it "emits a video_reindex confirmation when invoked from a video_detail follow-up context" do
      source_event = instance_double(
        Event,
        payload: { "video_id" => video.id, "reply_target" => "video_detail" }
      )
      ctx     = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "")
      handler = described_class.new(
        message:      instance_double(Pito::Chat::Message),
        conversation: Conversation.singleton,
        follow_up:    ctx
      )
      result = handler.call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("video_reindex")
      expect(event[:payload]["video_id"]).to eq(video.id)
    end
  end

  # ── Follow-up detail-context — game_enhanced ─────────────────────────────────

  context "follow-up detail context — game_enhanced" do
    let!(:game) { create(:game, title: "Elden Ring") }

    it "emits a game_reindex confirmation when invoked from a game_enhanced follow-up context" do
      source_event = instance_double(
        Event,
        payload: { "game_id" => game.id, "reply_target" => "game_enhanced" }
      )
      ctx     = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "")
      handler = described_class.new(
        message:      instance_double(Pito::Chat::Message),
        conversation: Conversation.singleton,
        follow_up:    ctx
      )
      result = handler.call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("game_reindex")
      expect(event[:payload]["game_id"]).to eq(game.id)
    end
  end
end
