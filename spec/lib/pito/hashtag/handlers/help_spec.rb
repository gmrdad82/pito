# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Hashtag::Handlers::Help do
  let(:conversation) { Conversation.singleton }

  def message_for(raw = "#help")
    Pito::Hashtag::Message.new(
      handle:       :help,
      body_tokens:  [],
      raw:          raw
    )
  end

  def handler(raw = "#help")
    described_class.new(message: message_for(raw), conversation: conversation)
  end

  # ── Result shape ────────────────────────────────────────────────────────────

  it "returns a Hashtag::Result::Ok" do
    expect(handler.call).to be_a(Pito::Hashtag::Result::Ok)
  end

  it "emits exactly one event" do
    expect(handler.call.events.size).to eq(1)
  end

  it "event kind is :system" do
    expect(handler.call.events.first[:kind]).to eq(:system)
  end

  it "payload has a body string" do
    payload = handler.call.events.first[:payload]
    expect(payload["body"]).to be_a(String).and be_present
  end

  # ── Sections structure ───────────────────────────────────────────────────────

  it "payload has a non-empty sections array" do
    payload = handler.call.events.first[:payload]
    expect(payload["sections"]).to be_an(Array).and be_present
  end

  it "sections include GAME, VIDEO, and CHANNEL titles" do
    sections = handler.call.events.first[:payload]["sections"]
    titles = sections.map { |s| s["title"] }
    expect(titles).to include("GAME")
    expect(titles).to include("VIDEO")
    expect(titles).to include("CHANNEL")
  end

  it "GAME section includes game_detail with expected actions" do
    sections = handler.call.events.first[:payload]["sections"]
    game_section = sections.find { |s| s["title"] == "GAME" }
    expect(game_section).to be_present

    detail_row = game_section["rows"].find { |r| r["key"] == "game_detail" }
    expect(detail_row).to be_present
    expect(detail_row["value"]).to include("rm").or include("delete")
  end

  # ── Identical output to the `help` chat verb ─────────────────────────────────

  it "produces the same sections as the chat Help handler" do
    chat_handler = Pito::Chat::Handlers::Help.new(
      message:      Pito::Chat::Message.new(verb: :help, body_tokens: [], kind: :new_turn, raw: "help"),
      conversation: conversation
    )

    hashtag_payload = handler.call.events.first[:payload]
    chat_payload    = chat_handler.call.events.first[:payload]

    expect(hashtag_payload["sections"]).to eq(chat_payload["sections"])
  end

  # ── Dynamic — reads the live Registry ───────────────────────────────────────

  it "reflects newly registered handlers (dynamic, not hard-coded)" do
    fake_handler = Class.new do
      def self.target_id = "theme_extra"
      def self.actions   = %w[preview apply reset]
    end

    Pito::FollowUp::Registry.register(fake_handler)

    sections  = handler.call.events.first[:payload]["sections"]
    all_rows  = sections.flat_map { |s| s["rows"] }
    found     = all_rows.any? { |r| r["key"] == "theme_extra" }
    expect(found).to be(true)
  ensure
    Pito::FollowUp::Registry.instance_variable_get(:@handlers)&.delete("theme_extra")
  end

  # ── Registry wiring ──────────────────────────────────────────────────────────

  it "is registered under handle :help in the Hashtag::Registry" do
    Pito::Hashtag::Registry.register_all!
    expect(Pito::Hashtag::Registry.registered_handles).to include(:help)
  end

  # ── Dispatcher integration ───────────────────────────────────────────────────

  it "is reachable via the Hashtag::Dispatcher with input '#help'" do
    Pito::Hashtag::Registry.register_all!
    result = Pito::Hashtag::Dispatcher.call(input: "#help", conversation: conversation)
    expect(result).to be_a(Pito::Hashtag::Result::Ok)
    payload = result.events.first[:payload]
    titles = payload["sections"].map { |s| s["title"] }
    expect(titles).to include("GAME")
  end

  # ── Section title shape ──────────────────────────────────────────────────────

  it "section titles are plain strings (rendered yellow by the system component)" do
    sections = handler.call.events.first[:payload]["sections"]
    sections.each do |s|
      expect(s["title"]).to be_a(String)
    end
  end
end
