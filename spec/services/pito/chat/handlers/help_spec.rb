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

  it "payload has no table_rows key (all content is in the html body)" do
    payload = handler.call.events.first[:payload]
    expect(payload["table_rows"]).to be_nil
  end

  # ── Group headings ────────────────────────────────────────────────────────

  it "payload body contains 'GAMES' group title" do
    body = handler.call.events.first[:payload]["body"]
    expect(body).to include("GAMES")
  end

  it "payload body contains 'VIDEOS' group title" do
    body = handler.call.events.first[:payload]["body"]
    expect(body).to include("VIDEOS")
  end

  it "payload body contains 'CHANNELS' group title" do
    body = handler.call.events.first[:payload]["body"]
    expect(body).to include("CHANNELS")
  end

  it "payload body renders group titles with text-yellow font-bold classes" do
    body = handler.call.events.first[:payload]["body"]
    expect(body).to include("text-yellow")
    expect(body).to include("font-bold")
  end

  # ── GAMES verbs ───────────────────────────────────────────────────────────

  %w[list show import delete reindex link unlink footage].each do |verb|
    it "body contains GAMES verb '#{verb}'" do
      body = handler.call.events.first[:payload]["body"]
      expect(body).to include(verb)
    end
  end

  # ── VIDEOS verbs ──────────────────────────────────────────────────────────

  %w[publish unlist schedule].each do |verb|
    it "body contains VIDEOS verb '#{verb}'" do
      body = handler.call.events.first[:payload]["body"]
      expect(body).to include(verb)
    end
  end

  # ── CHANNELS verbs ────────────────────────────────────────────────────────

  it "body contains CHANNELS verb 'sync'" do
    body = handler.call.events.first[:payload]["body"]
    expect(body).to include("sync")
  end

  # ── Hint text present for every row ──────────────────────────────────────

  it "body includes 'use --help for more info' hint text" do
    body = handler.call.events.first[:payload]["body"]
    expect(body).to include("use --help for more info")
  end

  # ── `help` verb is NOT listed ─────────────────────────────────────────────

  it "body does not list 'help' as a verb row (the page IS the help)" do
    body = handler.call.events.first[:payload]["body"]
    # The word "help" appears in the hint text — assert the verb span itself
    # is not present (i.e. no <span ...>help</span> entry).
    expect(body).not_to include(">help<")
  end

  # ── Data grid structure ───────────────────────────────────────────────────

  it "body uses pito-data-grid with data-cols=2" do
    body = handler.call.events.first[:payload]["body"]
    expect(body).to include('class="pito-data-grid"')
    expect(body).to include('data-cols="2"')
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
