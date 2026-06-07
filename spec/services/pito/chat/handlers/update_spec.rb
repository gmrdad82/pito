# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Update do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  def handler_for(*words)
    described_class.new(
      message: Pito::Chat::Message.new(
        verb: :update,
        body_tokens: tokens(*words),
        kind: :new_turn,
        raw: "update #{words.join(' ')}"
      ),
      conversation: Conversation.singleton
    )
  end

  let!(:game) { create(:game, title: "Lies of P") }

  it "sets ownership from a simple token list" do
    result = handler_for("game", "ownership", game.id.to_s, "ps", "steam").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(GamePlatformOwnership.where(game: game).pluck(:platform_token)).to contain_exactly("ps", "steam")
  end

  it "replaces the ownership set (removes unlisted tokens)" do
    create(:game_platform_ownership, game: game, platform_token: "switch")
    handler_for("game", "ownership", game.id.to_s, "ps").call
    expect(GamePlatformOwnership.where(game: game).pluck(:platform_token)).to contain_exactly("ps")
  end

  it "accepts tolerant separators: comma+space" do
    handler_for("game", "ownership", game.id.to_s, "ps5,", "Steam").call
    expect(GamePlatformOwnership.where(game: game).pluck(:platform_token)).to contain_exactly("ps", "steam")
  end

  it "accepts tolerant separators: dot" do
    handler_for("game", "ownership", game.id.to_s, "ps5.steam").call
    expect(GamePlatformOwnership.where(game: game).pluck(:platform_token)).to contain_exactly("ps", "steam")
  end

  it "accepts tolerant separators: asterisk" do
    handler_for("game", "ownership", game.id.to_s, "ps5*steam").call
    expect(GamePlatformOwnership.where(game: game).pluck(:platform_token)).to contain_exactly("ps", "steam")
  end

  it "expands ps synonyms (ps4, ps5, playstation, sony)" do
    handler_for("game", "ownership", game.id.to_s, "ps4").call
    expect(GamePlatformOwnership.where(game: game).pluck(:platform_token)).to contain_exactly("ps")

    GamePlatformOwnership.where(game: game).destroy_all
    handler_for("game", "ownership", game.id.to_s, "playstation").call
    expect(GamePlatformOwnership.where(game: game).pluck(:platform_token)).to contain_exactly("ps")

    GamePlatformOwnership.where(game: game).destroy_all
    handler_for("game", "ownership", game.id.to_s, "sony").call
    expect(GamePlatformOwnership.where(game: game).pluck(:platform_token)).to contain_exactly("ps")
  end

  it "expands switch synonyms (switch1, switch2, nintendo)" do
    handler_for("game", "ownership", game.id.to_s, "nintendo").call
    expect(GamePlatformOwnership.where(game: game).pluck(:platform_token)).to contain_exactly("switch")

    GamePlatformOwnership.where(game: game).destroy_all
    handler_for("game", "ownership", game.id.to_s, "switch2").call
    expect(GamePlatformOwnership.where(game: game).pluck(:platform_token)).to contain_exactly("switch")
  end

  it "expands steam synonyms (gog, epic, pc)" do
    handler_for("game", "ownership", game.id.to_s, "gog").call
    expect(GamePlatformOwnership.where(game: game).pluck(:platform_token)).to contain_exactly("steam")

    GamePlatformOwnership.where(game: game).destroy_all
    handler_for("game", "ownership", game.id.to_s, "epic").call
    expect(GamePlatformOwnership.where(game: game).pluck(:platform_token)).to contain_exactly("steam")

    GamePlatformOwnership.where(game: game).destroy_all
    handler_for("game", "ownership", game.id.to_s, "pc").call
    expect(GamePlatformOwnership.where(game: game).pluck(:platform_token)).to contain_exactly("steam")
  end

  it "dedupes synonyms (ps4 + ps5 → single ps)" do
    handler_for("game", "ownership", game.id.to_s, "ps4", "ps5").call
    expect(GamePlatformOwnership.where(game: game).pluck(:platform_token)).to contain_exactly("ps")
  end

  it "returns a witty not-found for an unknown game id" do
    result = handler_for("game", "ownership", "99999", "ps").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("99999")
  end

  it "returns needs_id when the first token is not a numeric id" do
    result = handler_for("game", "ownership", "lies", "of", "p", "ps").call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.update.needs_id")
  end

  it "returns needs_id when no ref is given at all" do
    result = handler_for("game", "ownership").call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.update.needs_id")
  end

  it "returns needs_platforms when the platform list is all garbage" do
    result = handler_for("game", "ownership", game.id.to_s, "unknown_platform").call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.update.needs_platforms")
  end

  it "emits a system message containing the game title and platforms" do
    result = handler_for("game", "ownership", game.id.to_s, "ps").call
    text = result.events.first[:payload]["text"]
    expect(text).to include("Lies of P")
    expect(text).to include("PlayStation")
  end

  it "accepts a #N id form" do
    result = handler_for("game", "ownership", "##{game.id}", "switch").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(GamePlatformOwnership.where(game: game).pluck(:platform_token)).to contain_exactly("switch")
  end
end
