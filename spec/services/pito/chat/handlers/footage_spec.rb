# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Footage do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  def handler_for(*words)
    described_class.new(
      message: Pito::Chat::Message.new(
        verb: :footage,
        body_tokens: tokens(*words),
        kind: :new_turn,
        raw: "footage #{words.join(' ')}"
      ),
      conversation: Conversation.singleton
    )
  end

  let!(:game) { create(:game, title: "Pragmata") }

  it "resolves by title (ILIKE) and returns a :system event" do
    result = handler_for("Pragmata", "/clips").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    event = result.events.first
    expect(event[:kind]).to eq(:system)
    expect(event[:payload]["html"]).to be(true)
  end

  it "resolves by bare id" do
    result = handler_for(game.id.to_s, "/clips").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:system)
    payload = result.events.first[:payload]
    expect(payload["html"]).to be(true)
    expect(payload["body"]).to include("pito:tools:probe")
  end

  it "resolves by #N id form" do
    result = handler_for("##{game.id}", "/clips").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    payload = result.events.first[:payload]
    expect(payload["body"]).to include("game=#{game.id}")
  end

  it "payload body includes the pito-footage-import block" do
    payload = handler_for("Pragmata", "/clips").call.events.first[:payload]
    expect(payload["body"]).to include("pito-footage-import")
  end

  it "payload body includes the probe command for the resolved game" do
    payload = handler_for("Pragmata", "/clips").call.events.first[:payload]
    expect(payload["body"]).to include("pito:tools:probe game=#{game.id}")
  end

  it "stamps game_id in the payload" do
    payload = handler_for("Pragmata", "/clips").call.events.first[:payload]
    expect(payload["game_id"]).to eq(game.id)
  end

  it "returns a witty not-found for an unknown reference" do
    result = handler_for("nonexistent game xyz", "/clips").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("nonexistent")
  end

  it "returns an error with needs_ref key when no reference is given" do
    result = handler_for.call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.footage.needs_ref")
  end

  it "returns needs_ref when a reference is given but no path" do
    result = handler_for("Pragmata").call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.footage.needs_ref")
  end

  it "keeps a multi-word title whole and uses the trailing path in the command" do
    create(:game, title: "Ghosts n Goblins")
    payload = handler_for("Ghosts", "n", "Goblins", "/mnt/clips").call.events.first[:payload]
    expect(payload["body"]).to include("path=&quot;/mnt/clips/*&quot;")
  end
end
