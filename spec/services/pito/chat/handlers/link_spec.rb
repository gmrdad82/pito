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

  it "creates a VideoGameLink when linking game to video by title (ILIKE)" do
    expect {
      handler_for("game", "lies", "of", "p", "to", "video", "lies", "of", "p", "review").call
    }.to change(VideoGameLink, :count).by(1)
  end

  it "creates a VideoGameLink when linking video to game by title (ILIKE)" do
    expect {
      handler_for("video", "lies", "of", "p", "review", "to", "game", "lies", "of", "p").call
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

  it "returns a not-found result for an unknown game" do
    result = handler_for("game", "99999", "to", "video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("99999")
  end

  it "returns a not-found result for an unknown video" do
    result = handler_for("game", game.id.to_s, "to", "video", "99999").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("99999")
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
end
