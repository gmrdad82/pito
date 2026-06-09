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

  # ── Result shape ────────────────────────────────────────────────────────────

  it "returns a Chat::Result::Ok" do
    expect(handler.call).to be_a(Pito::Chat::Result::Ok)
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

  it "GAME section includes a row for game_detail with its actions" do
    sections = handler.call.events.first[:payload]["sections"]
    game_section = sections.find { |s| s["title"] == "GAME" }
    expect(game_section).to be_present

    detail_row = game_section["rows"].find { |r| r["key"] == "game_detail" }
    expect(detail_row).to be_present
    expect(detail_row["value"]).to include("rm").or include("delete")
  end

  # ── Dynamic — reads the live Registry ───────────────────────────────────────

  it "reads Pito::FollowUp::Registry dynamically (not hard-coded)" do
    # Register a fake handler and verify it appears in the output.
    fake_handler = Class.new do
      def self.target_id = "fake_entity_x"
      def self.actions   = %w[frobnicate]
    end

    Pito::FollowUp::Registry.register(fake_handler)

    sections = handler.call.events.first[:payload]["sections"]
    all_rows  = sections.flat_map { |s| s["rows"] }
    found     = all_rows.any? { |r| r["key"] == "fake_entity_x" }
    expect(found).to be(true)
  ensure
    Pito::FollowUp::Registry.instance_variable_get(:@handlers)&.delete("fake_entity_x")
  end

  # ── Section title CSS context ────────────────────────────────────────────────
  # The system_component renders section[:title] in `text-yellow font-bold`.
  # We verify the payload shape is correct (sections array) so the component
  # will pick up the yellow class at render time — no need for a full render.

  it "section titles are plain strings (consumed by text-yellow font-bold in the component)" do
    sections = handler.call.events.first[:payload]["sections"]
    sections.each do |s|
      expect(s["title"]).to be_a(String)
    end
  end

  # ── Grammar registration ─────────────────────────────────────────────────────

  it "registers as verb :help in the Chat::Registry" do
    Pito::Chat::Registry.register_all!
    expect(Pito::Chat::Registry.registered_verbs).to include(:help)
  end

  # ── Description key ──────────────────────────────────────────────────────────

  it "defines a description_key" do
    expect(described_class.description_key).to eq("pito.chat.help.descriptions.help")
  end
end
