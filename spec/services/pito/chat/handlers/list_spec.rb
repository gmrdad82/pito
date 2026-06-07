# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::List do
  subject(:handler) do
    described_class.new(
      message: Pito::Chat::Message.new(verb: :list, body_tokens: [], kind: :new_turn, raw: "list games"),
      conversation: Conversation.singleton
    )
  end

  describe "#call with games in the library" do
    let!(:zelda) { create(:game, title: "Tears of the Kingdom") }
    let!(:lies)  { create(:game, title: "Lies of P") }

    it "returns a Result::Ok with one system event" do
      result = handler.call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.length).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "lists each game with its ID as the row key, sorted by title" do
      rows = handler.call.events.first[:payload][:table_rows]
      expect(rows).to eq([
        { key: "##{lies.id}",  value: "Lies of P" },
        { key: "##{zelda.id}", value: "Tears of the Kingdom" }
      ])
    end

    it "is stamped follow-up-able for game_list" do
      payload = handler.call.events.first[:payload]
      expect(Pito::FollowUp.followupable?(payload)).to be(true)
      expect(payload["reply_target"]).to eq("game_list")
    end

    it "renders the intro via Pito::Copy with the count" do
      payload = handler.call.events.first[:payload]
      expect(payload[:body]).to include("2")
    end
  end

  describe "#call with an empty library" do
    it "returns a witty empty-state system event" do
      result = handler.call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      payload = result.events.first[:payload]
      expect(payload[:text]).to be_present
      expect(payload[:table_rows]).to be_nil
    end
  end

  describe "#call with a non-games noun (channels / videos)" do
    let!(:game) { create(:game, title: "Lies of P") }

    def handler_for(raw)
      described_class.new(
        message: Pito::Chat::Message.new(verb: :list, body_tokens: [], kind: :new_turn, raw:),
        conversation: Conversation.singleton
      )
    end

    it "does NOT return the games shelf for `list channels`" do
      result = handler_for("list channels").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.errors.cannot_list")
      expect(result.message_args[:noun]).to eq("channels")
    end

    it "does NOT return the games shelf for `list videos`" do
      result = handler_for("list videos").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_args[:noun]).to eq("videos")
    end

    it "still lists games for `list games`" do
      expect(handler_for("list games").call).to be_a(Pito::Chat::Result::Ok)
    end
  end
end
