# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Price do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  def handler_for(*words)
    described_class.new(
      message: Pito::Chat::Message.new(
        verb: :price,
        body_tokens: tokens(*words),
        kind: :new_turn,
        raw: "price #{words.join(' ')}".strip
      ),
      conversation: Conversation.singleton
    )
  end

  let!(:game) { create(:game, title: "Pragmata") }

  # ── price set <id> <amount> — success ────────────────────────────────────────

  it "sets the game's price and returns an Ok system confirmation showing €amount" do
    result = handler_for("set", game.id.to_s, "59.99").call

    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(game.reload.price).to eq(BigDecimal("59.99"))

    event = result.events.first
    expect(event[:kind]).to eq(:system)
    expect(event[:payload]["text"]).to include("Pragmata").and include("€59.99")
  end

  it "rounds the amount to two decimals" do
    handler_for("set", game.id.to_s, "8.5").call
    expect(game.reload.price).to eq(BigDecimal("8.50"))
  end

  it "resolves the game by #id form" do
    handler_for("set", "##{game.id}", "20.00").call
    expect(game.reload.price).to eq(BigDecimal("20.00"))
  end

  # ── price unset <id> — clears to NULL ────────────────────────────────────────

  it "clears the price on unset" do
    game.update!(price: BigDecimal("40.00"))
    result = handler_for("unset", game.id.to_s).call

    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(game.reload.price).to be_nil
    expect(result.events.first[:payload]["text"]).to include("Pragmata")
  end

  # ── price >= 0 (0 = free) ─────────────────────────────────────────────────────

  it "sets an explicit 0 (free) and confirms it as €0.00" do
    result = handler_for("set", game.id.to_s, "0").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(game.reload.price).to eq(0)
    expect(result.events.first[:payload]["text"]).to include("Pragmata").and include("€0.00")
  end

  it "rejects a negative amount" do
    result = handler_for("set", game.id.to_s, "-5").call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(game.reload.price).to be_nil
  end

  it "rejects a non-numeric amount" do
    result = handler_for("set", game.id.to_s, "free").call
    expect(result).to be_a(Pito::Chat::Result::Error)
  end

  # ── usage / not-found ────────────────────────────────────────────────────────

  it "returns a usage hint for a bare price with no subcommand" do
    expect(handler_for.call).to be_a(Pito::Chat::Result::Error)
  end

  it "returns a usage hint for an unknown subcommand" do
    expect(handler_for("bump", game.id.to_s, "9.99").call).to be_a(Pito::Chat::Result::Error)
  end

  it "returns a witty not-found for an unknown game id on set" do
    result = handler_for("set", "999999", "9.99").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("999999")
  end
end
