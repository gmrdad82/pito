# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Link do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  def handler_for(*words)
    described_class.new(
      message: Pito::Chat::Message.new(
        verb: :link,
        body_tokens: tokens(*words),
        kind: :new_turn,
        raw: "link #{words.join(' ')}"
      ),
      conversation: Conversation.singleton
    )
  end

  def follow_up_handler(payload:, rest:)
    ctx = Pito::Chat::FollowUpContext.new(
      source_event: instance_double(Event, payload: payload),
      rest:         rest
    )
    described_class.new(
      message:      instance_double(Pito::Chat::Message),
      conversation: Conversation.singleton,
      follow_up:    ctx
    )
  end

  let!(:game)  { create(:game,  title: "Lies of P") }
  let!(:video) { create(:video, title: "Lies of P Review") }

  it "creates a VideoGameLink when linking game to video by id" do
    expect {
      handler_for("game", game.id.to_s, "to", "video", video.id.to_s).call
    }.to change(VideoGameLink, :count).by(1)
  end

  it "creates a VideoGameLink when linking video to game by id (reversed order)" do
    expect {
      handler_for("video", video.id.to_s, "to", "game", game.id.to_s).call
    }.to change(VideoGameLink, :count).by(1)
  end

  it "returns Ok with a witty success message" do
    result = handler_for("game", game.id.to_s, "to", "video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    text = result.events.first[:payload]["text"]
    expect(text).to include("Lies of P")
    expect(text).to include("Lies of P Review")
  end

  it "is idempotent — linking an existing link does not raise" do
    create(:video_game_link, video: video, game: game)
    expect {
      handler_for("game", game.id.to_s, "to", "video", video.id.to_s).call
    }.not_to change(VideoGameLink, :count)
  end

  it "returns a not-found result for an unknown game id" do
    result = handler_for("game", "99999", "to", "video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("99999")
  end

  it "returns a not-found result for an unknown video id" do
    result = handler_for("game", game.id.to_s, "to", "video", "99999").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("99999")
  end

  it "returns a usage hint when a title ref is given instead of an id" do
    result = handler_for("game", "lies", "of", "p", "to", "video", "lies", "of", "p", "review").call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.link.usage")
  end

  it "returns a usage hint when no 'to' separator is given" do
    result = handler_for("game", game.id.to_s, "video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.link.usage")
  end

  it "returns a usage hint when body is empty" do
    result = handler_for.call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.link.usage")
  end

  it "accepts #N id form for game" do
    expect {
      handler_for("game", "##{game.id}", "to", "video", video.id.to_s).call
    }.to change(VideoGameLink, :count).by(1)
  end

  it "accepts #N id form for video" do
    expect {
      handler_for("game", game.id.to_s, "to", "video", "##{video.id}").call
    }.to change(VideoGameLink, :count).by(1)
  end

  # ── Follow-up branch ─────────────────────────────────────────────────────────

  describe "follow-up from a game_detail card" do
    let(:game_detail_payload) do
      { "reply_target" => "game_detail", "game_id" => game.id }
    end

    it "links game to video by id ref (with leading 'to video')" do
      handler = follow_up_handler(payload: game_detail_payload, rest: "to video ##{video.id}")
      expect { handler.call }.to change(VideoGameLink, :count).by(1)
    end

    it "links game to video without leading noun words" do
      handler = follow_up_handler(payload: game_detail_payload, rest: "##{video.id}")
      expect { handler.call }.to change(VideoGameLink, :count).by(1)
    end

    it "returns a usage hint when a title ref is given instead of an id" do
      handler = follow_up_handler(payload: game_detail_payload, rest: "to video lies of p review")
      result = handler.call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.link.usage")
    end

    it "returns Ok with the linked ack" do
      result = follow_up_handler(payload: game_detail_payload, rest: "to video ##{video.id}").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      text = result.events.first[:payload]["text"]
      expect(text).to include("Lies of P")
      expect(text).to include("Lies of P Review")
    end

    it "is idempotent" do
      create(:video_game_link, video: video, game: game)
      expect {
        follow_up_handler(payload: game_detail_payload, rest: "to video ##{video.id}").call
      }.not_to change(VideoGameLink, :count)
    end

    it "returns not-found when the video id is unknown" do
      result = follow_up_handler(payload: game_detail_payload, rest: "to video 99999").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("99999")
    end

    it "returns a usage hint when the ref is blank" do
      result = follow_up_handler(payload: game_detail_payload, rest: "to video").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.link.usage")
    end
  end

  describe "follow-up from a video_detail card" do
    let(:video_detail_payload) do
      { "reply_target" => "video_detail", "video_id" => video.id }
    end

    it "links video to game by id ref (with leading 'to game')" do
      handler = follow_up_handler(payload: video_detail_payload, rest: "to game ##{game.id}")
      expect { handler.call }.to change(VideoGameLink, :count).by(1)
    end

    it "links video to game without leading noun words" do
      handler = follow_up_handler(payload: video_detail_payload, rest: "##{game.id}")
      expect { handler.call }.to change(VideoGameLink, :count).by(1)
    end

    it "returns a usage hint when a title ref is given instead of an id" do
      handler = follow_up_handler(payload: video_detail_payload, rest: "to game lies of p")
      result = handler.call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.link.usage")
    end

    it "returns Ok with the linked ack" do
      result = follow_up_handler(payload: video_detail_payload, rest: "to game ##{game.id}").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      text = result.events.first[:payload]["text"]
      expect(text).to include("Lies of P")
      expect(text).to include("Lies of P Review")
    end

    it "returns not-found when the game id is unknown" do
      result = follow_up_handler(payload: video_detail_payload, rest: "to game 99999").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("99999")
    end

    it "returns a usage hint when the ref is blank" do
      result = follow_up_handler(payload: video_detail_payload, rest: "to game").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.link.usage")
    end
  end
end
