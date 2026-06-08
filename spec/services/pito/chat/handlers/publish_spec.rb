# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Publish do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  def handler_for(*words)
    described_class.new(
      message: Pito::Chat::Message.new(verb: :publish, body_tokens: tokens(*words), kind: :new_turn, raw: "publish #{words.join(' ')}"),
      conversation: Conversation.singleton
    )
  end

  let!(:channel) { create(:channel) }
  let!(:video)   { create(:video, channel: channel, title: "My Review", privacy_status: :private, publish_at: 1.day.from_now) }

  it "emits a :confirmation event (not a direct update)" do
    result = handler_for("video", "my", "review").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "does NOT update the video directly" do
    handler_for("video", "my", "review").call
    expect(video.reload.privacy_status).to eq("private")
  end

  it "carries command video_publish in the confirmation payload" do
    result = handler_for("video", "my", "review").call
    expect(result.events.first[:payload]["command"]).to eq("video_publish")
  end

  it "carries video_id and video_title in the confirmation payload" do
    result = handler_for("video", "my", "review").call
    payload = result.events.first[:payload]
    expect(payload["video_id"]).to eq(video.id)
    expect(payload["video_title"]).to eq(video.title)
  end

  it "includes the video title in the confirmation body" do
    result = handler_for("video", "my", "review").call
    expect(result.events.first[:payload]["body"]).to include("My Review")
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
    result = handler_for("videos", "my", "review").call
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
    expect(result.message_key).to eq("pito.chat.publish.needs_ref")
  end

  context "video title with apostrophe resolved via real lexer/parser" do
    let!(:apos_video) { create(:video, channel: channel, title: "Let's Play Elden Ring", privacy_status: :private) }

    it "resolves the video and emits a confirmation" do
      result = Pito::Chat::Parser.call(
        Pito::Lex::Lexer.call("publish video Let's Play Elden Ring"),
        raw: "publish video Let's Play Elden Ring",
        conversation: Conversation.singleton
      )
      handler = described_class.new(message: result, conversation: Conversation.singleton)
      out = handler.call
      expect(out).to be_a(Pito::Chat::Result::Ok)
      expect(out.events.first[:kind]).to eq(:confirmation)
      expect(apos_video.reload.privacy_status).to eq("private")
    end
  end
end
