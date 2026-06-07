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

    it "lists each game with its #-prefixed ID as the row key, sorted by title" do
      rows = handler.call.events.first[:payload]["table_rows"]
      expect(rows.map { |r| { key: r[:key], value: r[:value] } }).to eq([
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
      expect(payload["body"]).to include("2")
    end
  end

  describe "#call with an empty library" do
    it "returns a witty empty-state system event" do
      result = handler.call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      payload = result.events.first[:payload]
      expect(payload["text"]).to be_present
      expect(payload[:table_rows]).to be_nil
    end
  end

  describe "#call with a non-games noun" do
    let!(:game) { create(:game, title: "Lies of P") }

    def handler_for(raw)
      described_class.new(
        message: Pito::Chat::Message.new(verb: :list, body_tokens: [], kind: :new_turn, raw:),
        conversation: Conversation.singleton
      )
    end

    it "does NOT return the games shelf for `list videos` (not listable yet)" do
      result = handler_for("list videos").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.errors.cannot_list")
      expect(result.message_args[:noun]).to eq("videos")
    end

    it "still lists games for `list games`" do
      result = handler_for("list games").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["table_rows"].first[:value2]).to be_nil
    end
  end

  describe "#call with the channels noun" do
    let!(:beta)  { create(:channel, title: "Beta Cast", handle: "@beta", youtube_channel_id: "UCb") }
    let!(:alpha) { create(:channel, title: "Alpha Tube", handle: "@alpha", youtube_channel_id: "UCa") }

    def handler_for(raw)
      described_class.new(
        message: Pito::Chat::Message.new(verb: :list, body_tokens: [], kind: :new_turn, raw:),
        conversation: Conversation.singleton
      )
    end

    it "returns an html body including each channel title" do
      body = handler_for("list channels").call.events.first[:payload]["body"]
      expect(body).to include("Alpha Tube")
      expect(body).to include("Beta Cast")
    end

    it "includes each channel @handle in the body" do
      body = handler_for("list channels").call.events.first[:payload]["body"]
      expect(body).to include("@alpha")
      expect(body).to include("@beta")
    end

    it "includes a youtube.com link with target=_blank for each channel" do
      body = handler_for("list channels").call.events.first[:payload]["body"]
      expect(body).to include("https://www.youtube.com/@alpha")
      expect(body).to include("https://www.youtube.com/@beta")
      expect(body).to include('target="_blank"')
    end

    it "includes the plain channel id (no # prefix) in the body" do
      body = handler_for("list channels").call.events.first[:payload]["body"]
      expect(body).to include(alpha.id.to_s)
      expect(body).to include(beta.id.to_s)
    end

    it "sets html: true on the payload" do
      payload = handler_for("list channels").call.events.first[:payload]
      expect(payload["html"]).to be(true)
    end

    it "renders the channels intro via Pito::Copy with the count" do
      payload = handler_for("list channels").call.events.first[:payload]
      expect(payload["body"]).to include("2")
    end

    it "is stamped follow-up-able for channel_list" do
      payload = handler_for("list channels").call.events.first[:payload]
      expect(Pito::FollowUp.followupable?(payload)).to be(true)
      expect(payload["reply_target"]).to eq("channel_list")
    end

    it "includes a reply_handle in the channel list payload" do
      payload = handler_for("list channels").call.events.first[:payload]
      expect(payload["reply_handle"]).to be_present
    end

    it "returns a witty empty-state when no channels are connected" do
      Channel.delete_all
      payload = handler_for("list channels").call.events.first[:payload]
      expect(payload["text"]).to be_present
      expect(payload[:table_rows]).to be_nil
    end
  end
end
