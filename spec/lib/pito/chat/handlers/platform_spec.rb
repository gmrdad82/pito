# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Platform do
  let(:conversation) { Conversation.singleton }
  let!(:game)        { create(:game, title: "Tekken 7", platforms: []) }

  # Free-chat invocation: build the handler directly (resolution reads message.raw).
  def free_call(rest)
    described_class.new(
      message: Pito::Chat::Message.new(tool: :platform, body_tokens: [], kind: :new_turn, raw: "platform #{rest}".strip),
      conversation: conversation
    ).call
  end

  # Follow-up reply: route through the same ToolDelegator the UI uses, with a
  # stamped source event (game_detail carries game_id; game_list does not).
  def reply_call(reply_target, rest, **extra)
    source = instance_double(Event, payload: { "reply_target" => reply_target }.merge(extra.transform_keys(&:to_s)))
    Pito::FollowUp::ToolDelegator.call(source_event: source, rest: rest, conversation: conversation)
  end

  # ── Typed free chat: moved (setter migrated to `update`) ────────────────────────
  #
  # `call` returns the "moved" error BEFORE resolution when there is no follow-up
  # context, for every argument shape — no lookup, no write. Reply-through-follow-up
  # invocations (below) are the only surviving path that mutates `game.platforms`.

  it "returns the moved error for the plain `<id> <name>` form, without writing" do
    result = free_call("#{game.id} ps5")

    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.update.moved")
    expect(result.message_args).to eq(example: "update game platform 12 ps5")
    expect(game.reload.platforms).to eq([])
  end

  it "returns the moved error regardless of id form or noun filler (# prefix, `game` filler)" do
    expect(free_call("##{game.id} PlayStation 5")).to be_a(Pito::Chat::Result::Error)
    expect(free_call("game #{game.id} switch")).to be_a(Pito::Chat::Result::Error)
    expect(game.reload.platforms).to eq([])
  end

  it "returns the moved error for an explicit `set` subcommand, without writing" do
    result = free_call("set #{game.id} ps5")

    expect(result.message_key).to eq("pito.chat.update.moved")
    expect(game.reload.platforms).to eq([])
  end

  it "returns the moved error for an explicit `unset` subcommand, without writing" do
    game.update!(platforms: [ "PlayStation 5" ])
    result = free_call("unset #{game.id} ps5")

    expect(result.message_key).to eq("pito.chat.update.moved")
    expect(game.reload.platforms).to eq([ "PlayStation 5" ])
  end

  it "returns the moved error with no arguments at all" do
    result = free_call("")

    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.update.moved")
  end

  it "returns the moved error when only an id is given (no platform name)" do
    result = free_call(game.id.to_s)

    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.update.moved")
  end

  it "returns the moved error for an unknown game id (no not-found lookup happens)" do
    result = free_call("999999 ps5")

    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.update.moved")
  end

  # ── Context 2: reply to `show game` (game from card, no id) ──────────────────────

  it "sets the platform via a game_detail reply (game from the card, no id typed)" do
    result = reply_call("game_detail", "platform ps5", game_id: game.id)
    expect(game.reload.platforms).to eq([ "PlayStation 5" ])

    events = result.events
    payload = events.first[:payload]
    expect(payload["html"]).to be(true)
    expect(payload["body"]).to include("playstation.svg")
    expect(payload["game_id"]).to eq(game.id)
  end

  it "enqueues GameEmbedIndexJob (platforms feed Game::EmbedText) when a platform is set" do
    expect { reply_call("game_detail", "platform ps5", game_id: game.id) }
      .to have_enqueued_job(GameEmbedIndexJob).with(game.id)
  end

  # ── Context 3: reply to `list games` (leading id) ───────────────────────────────

  it "sets the platform via a game_list reply (leading id + name)" do
    reply_call("game_list", "platform #{game.id} steam")
    expect(game.reload.platforms).to eq([ "PC (Steam)" ])
  end

  # ── De-dup + append (via follow-up — the only path that still writes) ───────────

  it "is a no-op when the normalized platform is already present (de-duped)" do
    game.update!(platforms: [ "PlayStation 5" ])
    reply_call("game_detail", "platform PlayStation5", game_id: game.id)
    expect(game.reload.platforms).to eq([ "PlayStation 5" ])
  end

  it "does not enqueue GameEmbedIndexJob on a de-duped no-op set" do
    game.update!(platforms: [ "PlayStation 5" ])

    expect { reply_call("game_detail", "platform PlayStation5", game_id: game.id) }
      .not_to have_enqueued_job(GameEmbedIndexJob)
  end

  it "appends (does not replace) existing platforms" do
    game.update!(platforms: [ "Nintendo Switch" ])
    reply_call("game_detail", "platform ps5", game_id: game.id)
    expect(game.reload.platforms).to contain_exactly("Nintendo Switch", "PlayStation 5")
  end

  # ── set / unset subcommands (add / remove) ──────────────────────────────────────

  it "adds via an explicit `set` subcommand through a follow-up reply" do
    reply_call("game_detail", "platform set ps5", game_id: game.id)
    expect(game.reload.platforms).to eq([ "PlayStation 5" ])
  end

  it "removes a specific platform via `unset`, preserving the others" do
    game.update!(platforms: [ "PlayStation 5", "Nintendo Switch" ])
    result = reply_call("game_detail", "platform unset ps5", game_id: game.id)

    expect(game.reload.platforms).to eq([ "Nintendo Switch" ])
    expect(result.events.first[:payload]["body"]).to include("Removed")
  end

  it "enqueues GameEmbedIndexJob (platforms feed Game::EmbedText) when a platform is unset" do
    game.update!(platforms: [ "PlayStation 5", "Nintendo Switch" ])

    expect { reply_call("game_detail", "platform unset ps5", game_id: game.id) }
      .to have_enqueued_job(GameEmbedIndexJob).with(game.id)
  end

  it "unset is a no-op (still Ok) when the platform is not present" do
    game.update!(platforms: [ "Nintendo Switch" ])
    result = reply_call("game_detail", "platform unset ps5", game_id: game.id)

    expect(result).to be_a(Pito::FollowUp::Result::Append)
    expect(game.reload.platforms).to eq([ "Nintendo Switch" ])
  end

  it "does not enqueue GameEmbedIndexJob when unset is a no-op (platform not present)" do
    game.update!(platforms: [ "Nintendo Switch" ])

    expect { reply_call("game_detail", "platform unset ps5", game_id: game.id) }
      .not_to have_enqueued_job(GameEmbedIndexJob)
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

  # ── Unknown platform: stored as text, no logo (via follow-up) ───────────────────

  it "stores an unknown platform as text with no logo" do
    result = reply_call("game_detail", "platform Stadia", game_id: game.id)

    expect(game.reload.platforms).to eq([ "Stadia" ])
    expect(Pito::Games::PlatformTokens.tokens(game.platforms)).to be_empty
    expect(result.events.first[:payload]["body"]).to include("Stadia")
  end

  it "stores Xbox with its logo token (Item 24)" do
    reply_call("game_detail", "platform Xbox", game_id: game.id)

    expect(game.reload.platforms).to eq([ "Xbox" ])
    expect(Pito::Games::PlatformTokens.tokens(game.platforms)).to eq([ "xbox" ])
  end

  # ── Errors (via follow-up — the only path that still resolves) ──────────────────

  it "returns needs_ref when no game reference is given in a list reply" do
    result = reply_call("game_list", "platform")
    expect(result).to be_a(Pito::FollowUp::Result::Error)
    expect(result.message_key).to eq("pito.chat.platform.needs_ref")
  end

  it "returns missing_name when a detail reply carries no platform name" do
    result = reply_call("game_detail", "platform", game_id: game.id)
    expect(result).to be_a(Pito::FollowUp::Result::Error)
    expect(result.message_key).to eq("pito.chat.platform.missing_name")
  end

  it "returns a witty not-found for an unknown game id via a list reply" do
    result = reply_call("game_list", "platform 999999 ps5")
    expect(result).to be_a(Pito::FollowUp::Result::Append)
    expect(result.events.first[:payload]["text"]).to include("999999")
  end
end
