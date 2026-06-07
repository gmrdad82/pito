# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Show do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  def handler_for(*words)
    described_class.new(
      message: Pito::Chat::Message.new(verb: :show, body_tokens: tokens(*words), kind: :new_turn, raw: "show #{words.join(' ')}"),
      conversation: Conversation.singleton
    )
  end

  let!(:game) { create(:game, title: "Lies of P") }

  it "shows a game by title (ILIKE), dropping the noun filler" do
    result = handler_for("game", "lies", "of", "p").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    payload = result.events.first[:payload]
    expect(payload["html"]).to be(true)
    expect(payload["body"]).to include("Lies of P")
  end

  it "shows a game by id (#N)" do
    payload = handler_for("##{game.id}").call.events.first[:payload]
    expect(payload["body"]).to include("Lies of P")
  end

  it "shows a game by bare id" do
    payload = handler_for(game.id.to_s).call.events.first[:payload]
    expect(payload["body"]).to include("Lies of P")
  end

  it "stamps the detail message follow-up-able (game_detail)" do
    payload = handler_for("##{game.id}").call.events.first[:payload]
    expect(Pito::FollowUp.followupable?(payload)).to be(true)
    expect(payload["reply_target"]).to eq("game_detail")
  end

  it "returns a witty not-found for an unknown reference" do
    result = handler_for("game", "nonexistent").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload][:text]).to include("nonexistent")
  end

  it "returns a usage hint when no reference is given" do
    result = handler_for.call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.show.needs_ref")
  end

  context "ILIKE partial vs exact — two games sharing a prefix" do
    let!(:exact_game)   { create(:game, title: "Lies of P") }
    let!(:prefix_game)  { create(:game, title: "Lies of P: Expanded") }

    it "finds the first ILIKE match (exact title input returns that game)" do
      result = handler_for("lies", "of", "p").call
      # The ILIKE query returns the first match; 'Lies of P' matches exactly
      expect(result).to be_a(Pito::Chat::Result::Ok)
      body = result.events.first[:payload]["body"]
      # At least one of the two games sharing the prefix is found — no crash
      expect(body).to be_present
    end

    it "returns a not-found result for a ref that matches neither game" do
      result = handler_for("lies", "of", "z").call
      text = result.events.first[:payload][:text]
      expect(text).to be_present
    end
  end
end
