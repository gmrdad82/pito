# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Platform do
  let(:conversation) { Conversation.singleton }
  let!(:game)        { create(:game, title: "Tekken 7", platforms: []) }

  # Free-chat invocation: build the handler directly (resolution reads message.raw).
  def free_call(rest)
    described_class.new(
      message: Pito::Chat::Message.new(verb: :platform, body_tokens: [], kind: :new_turn, raw: "platform #{rest}".strip),
      conversation: conversation
    ).call
  end

  # Follow-up reply: route through the same VerbDelegator the UI uses, with a
  # stamped source event (game_detail carries game_id; game_list does not).
  def reply_call(reply_target, rest, **extra)
    source = instance_double(Event, payload: { "reply_target" => reply_target }.merge(extra.transform_keys(&:to_s)))
    Pito::FollowUp::VerbDelegator.call(source_event: source, rest: rest, conversation: conversation)
  end

  # ── Context 1: free chat (`platform <id> ps5`) ──────────────────────────────────

  it "sets the platform in free chat (leading id + name)" do
    result = free_call("#{game.id} ps5")

    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(game.reload.platforms).to eq([ "PlayStation 5" ])

    payload = result.events.first[:payload]
    expect(result.events.first[:kind]).to eq(:system)
    expect(payload["html"]).to be(true)
    expect(payload["body"]).to include("playstation.svg")
    expect(payload["game_id"]).to eq(game.id)
  end

  it "accepts a `#`-prefixed id and a multi-word platform name" do
    free_call("##{game.id} PlayStation 5")
    expect(game.reload.platforms).to eq([ "PlayStation 5" ])
  end

  it "tolerates the `game` noun filler before the id" do
    free_call("game #{game.id} switch")
    expect(game.reload.platforms).to eq([ "Nintendo Switch" ])
  end

  # ── Context 2: reply to `show game` (game from card, no id) ──────────────────────

  it "sets the platform via a game_detail reply (game from the card, no id typed)" do
    reply_call("game_detail", "platform ps5", game_id: game.id)
    expect(game.reload.platforms).to eq([ "PlayStation 5" ])
  end

  # ── Context 3: reply to `list games` (leading id) ───────────────────────────────

  it "sets the platform via a game_list reply (leading id + name)" do
    reply_call("game_list", "platform #{game.id} steam")
    expect(game.reload.platforms).to eq([ "PC (Steam)" ])
  end

  # ── De-dup + append ─────────────────────────────────────────────────────────────

  it "is a no-op when the normalized platform is already present (de-duped)" do
    game.update!(platforms: [ "PlayStation 5" ])
    free_call("#{game.id} PlayStation5")
    expect(game.reload.platforms).to eq([ "PlayStation 5" ])
  end

  it "appends (does not replace) existing platforms" do
    game.update!(platforms: [ "Nintendo Switch" ])
    free_call("#{game.id} ps5")
    expect(game.reload.platforms).to contain_exactly("Nintendo Switch", "PlayStation 5")
  end

  # ── set / unset subcommands (add / remove) ──────────────────────────────────────

  it "adds via an explicit `set` subcommand" do
    free_call("set #{game.id} ps5")
    expect(game.reload.platforms).to eq([ "PlayStation 5" ])
  end

  it "removes a specific platform via `unset`, preserving the others" do
    game.update!(platforms: [ "PlayStation 5", "Nintendo Switch" ])
    result = free_call("unset #{game.id} ps5")

    expect(game.reload.platforms).to eq([ "Nintendo Switch" ])
    expect(result.events.first[:payload]["body"]).to include("Removed")
  end

  it "unset is a no-op (still Ok) when the platform is not present" do
    game.update!(platforms: [ "Nintendo Switch" ])
    result = free_call("unset #{game.id} ps5")

    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(game.reload.platforms).to eq([ "Nintendo Switch" ])
  end

  it "removes via a game_detail reply (`#<handle> platform unset ps5`)" do
    game.update!(platforms: [ "PlayStation 5", "Nintendo Switch" ])
    reply_call("game_detail", "platform unset ps5", game_id: game.id)
    expect(game.reload.platforms).to eq([ "Nintendo Switch" ])
  end

  it "removes via a game_list reply (leading id)" do
    game.update!(platforms: [ "PlayStation 5", "Nintendo Switch" ])
    reply_call("game_list", "platform unset #{game.id} ps5")
    expect(game.reload.platforms).to eq([ "Nintendo Switch" ])
  end

  # ── Unknown platform: stored as text, no logo ───────────────────────────────────

  it "stores an unknown platform as text with no logo" do
    result = free_call("#{game.id} Stadia")

    expect(game.reload.platforms).to eq([ "Stadia" ])
    expect(Pito::Game::PlatformTokens.tokens(game.platforms)).to be_empty
    expect(result.events.first[:payload]["body"]).to include("Stadia")
  end

  it "stores Xbox with its logo token (Item 24)" do
    free_call("#{game.id} Xbox")

    expect(game.reload.platforms).to eq([ "Xbox" ])
    expect(Pito::Game::PlatformTokens.tokens(game.platforms)).to eq([ "xbox" ])
  end

  # ── Errors ──────────────────────────────────────────────────────────────────────

  it "returns needs_ref when no game reference is given" do
    result = free_call("")
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.platform.needs_ref")
  end

  it "returns missing_name when an id is given with no platform name" do
    result = free_call(game.id.to_s)
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.platform.missing_name")
  end

  it "returns a witty not-found for an unknown game id" do
    result = free_call("999999 ps5")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("999999")
  end
end
