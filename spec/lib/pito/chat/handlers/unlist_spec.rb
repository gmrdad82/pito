# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Unlist do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  def handler_for(*words)
    described_class.new(
      message: Pito::Chat::Message.new(tool: :unlist, body_tokens: tokens(*words), kind: :new_turn, raw: "unlist #{words.join(' ')}"),
      conversation: Conversation.singleton
    )
  end

  let!(:channel) { create(:channel) }
  let!(:video)   { create(:video, channel: channel, title: "Boss Fight Compilation", privacy_status: :public) }

  it "emits a :confirmation event (not a direct update)" do
    result = handler_for("video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "does NOT update the video directly" do
    handler_for("video", video.id.to_s).call
    expect(video.reload.privacy_status).to eq("public")
  end

  it "carries command video_unlist in the confirmation payload" do
    result = handler_for("video", video.id.to_s).call
    expect(result.events.first[:payload]["command"]).to eq("video_unlist")
  end

  it "carries video_id and video_title in the confirmation payload" do
    result = handler_for("video", video.id.to_s).call
    payload = result.events.first[:payload]
    expect(payload["video_id"]).to eq(video.id)
    expect(payload["video_title"]).to eq(video.title)
  end

  it "includes the video title in the confirmation body" do
    result = handler_for("video", video.id.to_s).call
    expect(result.events.first[:payload]["body"]).to include("Boss Fight Compilation")
  end

  it "returns not-found for a title reference (id-only resolution)" do
    result = handler_for("video", "boss", "fight", "compilation").call
    expect(result.events.first[:payload]["text"]).to include("boss fight compilation")
  end

  it "resolves by bare id" do
    result = handler_for("video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "resolves by #id" do
    result = handler_for("video", "##{video.id}").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "resolves with plural noun filler 'videos'" do
    result = handler_for("videos", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "returns a witty not-found for an unknown reference" do
    result = handler_for("video", "nonexistent").call
    expect(result.events.first[:payload]["text"]).to include("nonexistent")
  end

  it "returns a usage hint when no reference is given" do
    result = handler_for.call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.unlist.needs_ref")
  end

  context "id-only resolution via real lexer/parser" do
    it "resolves by id and emits a confirmation" do
      result = Pito::Chat::Parser.call(
        Pito::Lex::Lexer.call("unlist video #{video.id}"),
        raw: "unlist video #{video.id}",
        conversation: Conversation.singleton
      )
      handler = described_class.new(message: result, conversation: Conversation.singleton)
      out = handler.call
      expect(out).to be_a(Pito::Chat::Result::Ok)
      expect(out.events.first[:kind]).to eq(:confirmation)
    end

    it "returns not-found for a title ref via real lexer/parser" do
      result = Pito::Chat::Parser.call(
        Pito::Lex::Lexer.call("unlist video Boss Fight Compilation"),
        raw: "unlist video Boss Fight Compilation",
        conversation: Conversation.singleton
      )
      handler = described_class.new(message: result, conversation: Conversation.singleton)
      out = handler.call
      expect(out).to be_a(Pito::Chat::Result::Ok)
      expect(out.events.first[:kind]).to eq(:system)
    end
  end
end
