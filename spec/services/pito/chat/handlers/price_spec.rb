# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Price do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  # Builds a FollowUpContext as though the user replied `#<handle> price ...`
  # to a `list games` card (game_list reply_target) — the delegation path the
  # `price` verb still serves (list-scoped set/unset), same as the platform
  # handler spec's follow-up helpers.
  def follow_up_context(rest)
    source_event = instance_double(Event, payload: { "reply_target" => "game_list" })
    Pito::Chat::FollowUpContext.new(source_event: source_event, rest: rest)
  end

  def handler_for(*words, follow_up: nil)
    described_class.new(
      message: Pito::Chat::Message.new(
        verb: :price,
        body_tokens: tokens(*words),
        kind: :new_turn,
        raw: "price #{words.join(' ')}".strip
      ),
      conversation: Conversation.singleton,
      follow_up: follow_up
    )
  end

  # Follow-up invocation: same raw text a free-chat call would build, but with
  # a FollowUpContext attached — the `follow_up?` gate reads its presence, not
  # its contents (parse_args still reads message.raw only).
  def follow_up_handler_for(*words)
    handler_for(*words, follow_up: follow_up_context(words.join(" ")))
  end

  let!(:game) { create(:game, title: "Pragmata") }

  # ── typed free chat: moved before any parsing/writes ──────────────────────────

  describe "typed free chat (no follow-up context) → moved, before parsing (no writes)" do
    def expect_moved(result)
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.update.moved")
      expect(result.message_args).to eq({ example: "update game price 12 59.99" })
    end

    it "moves `price set <id> <amount>` without writing" do
      result = handler_for("set", game.id.to_s, "59.99").call
      expect_moved(result)
      expect(game.reload.price).to be_nil
    end

    it "moves `price unset <id>` without writing" do
      game.update!(price: BigDecimal("40.00"))
      result = handler_for("unset", game.id.to_s).call
      expect_moved(result)
      expect(game.reload.price).to eq(BigDecimal("40.00"))
    end

    it "moves the implicit `price <id> <amount>` form without writing" do
      result = handler_for(game.id.to_s, "59.99").call
      expect_moved(result)
      expect(game.reload.price).to be_nil
    end

    it "moves a bare `price` with no args" do
      expect_moved(handler_for.call)
    end

    it "moves before resolving the game (unknown id doesn't change the outcome)" do
      result = handler_for("set", "999999", "9.99").call
      expect_moved(result)
    end

    it "moves before validating the amount (a non-numeric amount doesn't change the outcome)" do
      result = handler_for("set", game.id.to_s, "free").call
      expect_moved(result)
    end
  end

  # ── follow-up context (game_list reply delegation) — original set/unset behavior ──

  # ── price set <id> <amount> — success ────────────────────────────────────────

  it "sets the game's price and returns an Ok HTML confirmation showing the coin glyphs + number" do
    result = follow_up_handler_for("set", game.id.to_s, "59.99").call

    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(game.reload.price).to eq(BigDecimal("59.99"))

    event = result.events.first
    expect(event[:kind]).to eq(:system)
    expect(event[:payload]["html"]).to be(true)
    body = event[:payload]["body"]
    # Coin glyphs (Pito::Coin) + the number, NOT a bare "€59.99".
    expect(body).to include("Pragmata").and include("59.99").and include("pito-coin")
    expect(body).not_to include("€")
  end

  it "rounds the amount to two decimals" do
    follow_up_handler_for("set", game.id.to_s, "8.5").call
    expect(game.reload.price).to eq(BigDecimal("8.50"))
  end

  it "resolves the game by #id form" do
    follow_up_handler_for("set", "##{game.id}", "20.00").call
    expect(game.reload.price).to eq(BigDecimal("20.00"))
  end

  # ── price unset <id> — clears to NULL ────────────────────────────────────────

  it "clears the price on unset" do
    game.update!(price: BigDecimal("40.00"))
    result = follow_up_handler_for("unset", game.id.to_s).call

    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(game.reload.price).to be_nil
    expect(result.events.first[:payload]["text"]).to include("Pragmata")
  end

  # ── price >= 0 (0 = free) ─────────────────────────────────────────────────────

  it "sets an explicit 0 (free) and confirms it with the free star + 0.00" do
    result = follow_up_handler_for("set", game.id.to_s, "0").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(game.reload.price).to eq(0)
    body = result.events.first[:payload]["body"]
    expect(body).to include("Pragmata").and include("0.00").and include("pito-coin--free")
  end

  it "rejects a negative amount" do
    result = follow_up_handler_for("set", game.id.to_s, "-5").call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(game.reload.price).to be_nil
  end

  it "rejects a non-numeric amount" do
    result = follow_up_handler_for("set", game.id.to_s, "free").call
    expect(result).to be_a(Pito::Chat::Result::Error)
  end

  # ── usage / not-found ────────────────────────────────────────────────────────

  it "returns a usage hint for a bare price with no subcommand" do
    expect(follow_up_handler_for.call).to be_a(Pito::Chat::Result::Error)
  end

  it "sets the price via the implicit form `price <id> <amount>` (no subcommand)" do
    result = follow_up_handler_for(game.id.to_s, "59.99").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(game.reload.price).to eq(BigDecimal("59.99"))
  end

  it "treats a non-numeric implicit ref as a witty not-found (no subcommand)" do
    # `price bump 9.99` → no set/unset → implicit set on game "bump" → not found.
    expect(follow_up_handler_for("bump", "9.99").call).to be_a(Pito::Chat::Result::Ok)
  end

  it "returns a witty not-found for an unknown game id on set" do
    result = follow_up_handler_for("set", "999999", "9.99").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("999999")
  end
end
