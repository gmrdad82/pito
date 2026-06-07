# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Delete do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  def handler_for(*words)
    described_class.new(
      message: Pito::Chat::Message.new(verb: :delete, body_tokens: tokens(*words), kind: :new_turn, raw: "delete #{words.join(' ')}"),
      conversation: Conversation.singleton
    )
  end

  let!(:game) { create(:game, title: "Lies of P") }

  it "emits a confirmation event carrying the game_delete command + id + title" do
    result = handler_for("game", "lies", "of", "p").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    event = result.events.first
    expect(event[:kind]).to eq("confirmation")
    expect(event[:payload]["command"]).to eq("game_delete")
    expect(event[:payload]["game_id"]).to eq(game.id)
    expect(event[:payload]["game_title"]).to eq("Lies of P")
  end

  it "resolves by id and stamps the confirmation follow-up-able" do
    payload = handler_for("##{game.id}").call.events.first[:payload]
    expect(Pito::FollowUp.followupable?(payload)).to be(true)
    expect(payload["reply_target"]).to eq("confirmation")
  end

  it "does NOT delete the game yet (confirmation only)" do
    expect { handler_for("##{game.id}").call }.not_to change(Game, :count)
  end

  it "returns a witty not-found for an unknown reference" do
    result = handler_for("game", "nope").call
    expect(result.events.first[:payload][:text]).to include("nope")
  end

  it "returns a usage hint when no reference is given" do
    expect(handler_for.call).to be_a(Pito::Chat::Result::Error)
  end
end
