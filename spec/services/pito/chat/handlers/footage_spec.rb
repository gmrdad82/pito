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

  # ── new canonical form: footage game <id> <path> ─────────────────────────────

  it "resolves by id with 'game' noun filler and emits a probe-command :system event" do
    result = handler_for("game", game.id.to_s, "/clips").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    event = result.events.first
    expect(event[:kind]).to eq(:system)
    expect(event[:payload]["html"]).to be(true)
    expect(event[:payload]["body"]).to include("pito:tools:probe game=#{game.id}")
  end

  it "resolves by bare numeric id (no 'game' filler) and emits the probe command" do
    result = handler_for(game.id.to_s, "/clips").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
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

  it "stamps game_id in the payload" do
    payload = handler_for("game", game.id.to_s, "/clips").call.events.first[:payload]
    expect(payload["game_id"]).to eq(game.id)
  end

  it "includes the path in the probe command" do
    payload = handler_for("game", game.id.to_s, "/mnt/clips").call.events.first[:payload]
    expect(payload["body"]).to include("path=&quot;/mnt/clips/*&quot;")
  end

  # ── --force flag ──────────────────────────────────────────────────────────────

  it "includes '-- --force' in the body when --force flag precedes the path" do
    payload = handler_for("game", game.id.to_s, "--force", "/mnt/footage").call.events.first[:payload]
    expect(payload["body"]).to include("-- --force")
  end

  it "includes '-- --force' in the body when --force flag trails the path" do
    payload = handler_for("game", game.id.to_s, "/mnt/footage", "--force").call.events.first[:payload]
    expect(payload["body"]).to include("-- --force")
  end

  it "does not include '--force' in the body when no flag is given" do
    payload = handler_for("game", game.id.to_s, "/mnt/footage").call.events.first[:payload]
    expect(payload["body"]).not_to include("--force")
    expect(payload["body"]).to include("game=#{game.id}")
    expect(payload["body"]).to include("path=")
  end

  # ── title ref no longer resolves (ILIKE dropped) ─────────────────────────────

  it "returns a witty not-found for a title-style reference (ILIKE dropped)" do
    result = handler_for("Pragmata", "/clips").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    payload = result.events.first[:payload]
    # not-found path emits a text payload, not a probe command
    expect(payload["text"]).to be_present
  end

  it "returns a witty not-found for any non-numeric reference" do
    result = handler_for("nonexistent", "/clips").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to be_present
  end

  # ── missing ref / path → usage hint ──────────────────────────────────────────

  it "returns an error with needs_ref key when no reference is given" do
    result = handler_for.call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.footage.needs_ref")
  end

  it "returns needs_ref when a reference is given but no path" do
    result = handler_for(game.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.footage.needs_ref")
  end

  it "returns needs_ref when 'game' filler is given but no id or path" do
    result = handler_for("game").call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.footage.needs_ref")
  end
end
