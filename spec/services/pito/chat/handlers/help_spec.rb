# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Help do
  let(:conversation) { Conversation.singleton }

  def handler
    described_class.new(
      message:      Pito::Chat::Message.new(verb: :help, body_tokens: [], kind: :new_turn, raw: "help"),
      conversation: conversation
    )
  end

  # ── Result shape ─────────────────────────────────────────────────────────────

  it "returns a Chat::Result::Ok" do
    expect(handler.call).to be_a(Pito::Chat::Result::Ok)
  end

  it "emits exactly one event" do
    expect(handler.call.events.size).to eq(1)
  end

  it "event kind is :system" do
    expect(handler.call.events.first[:kind]).to eq(:system)
  end

  # ── Payload shape — html: true, always visible ────────────────────────────

  it "payload sets html: true so content renders instantly (no expand toggle)" do
    payload = handler.call.events.first[:payload]
    expect(payload["html"]).to be(true)
  end

  it "payload has no sections key (content must be visible without expanding)" do
    payload = handler.call.events.first[:payload]
    expect(payload["sections"]).to be_nil.or be_empty
  end

  # ── GAMES group title ─────────────────────────────────────────────────────

  it "payload body contains 'GAMES' (yellow title)" do
    body = handler.call.events.first[:payload]["body"]
    expect(body).to include("GAMES")
  end

  it "payload body renders GAMES title with text-yellow font-bold classes" do
    body = handler.call.events.first[:payload]["body"]
    expect(body).to include("text-yellow")
    expect(body).to include("font-bold")
  end

  # ── list games kv row ─────────────────────────────────────────────────────

  it "payload has a table_rows array" do
    payload = handler.call.events.first[:payload]
    expect(payload["table_rows"]).to be_an(Array).and be_present
  end

  it "table_rows contains a row with key 'list games'" do
    rows = handler.call.events.first[:payload]["table_rows"]
    keys = rows.map { |r| r["key"] || r[:key] }
    expect(keys).to include("list games")
  end

  it "the 'list games' row value mentions --help" do
    rows = handler.call.events.first[:payload]["table_rows"]
    row  = rows.find { |r| (r["key"] || r[:key]) == "list games" }
    expect(row["value"] || row[:value]).to include("--help")
  end

  # ── Grammar registration ──────────────────────────────────────────────────

  it "registers as verb :help in the Chat::Registry" do
    Pito::Chat::Registry.register_all!
    expect(Pito::Chat::Registry.registered_verbs).to include(:help)
  end

  # ── Description key ───────────────────────────────────────────────────────

  it "defines a description_key" do
    expect(described_class.description_key).to eq("pito.chat.help.descriptions.help")
  end
end
