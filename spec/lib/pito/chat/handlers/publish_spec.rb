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
      message: Pito::Chat::Message.new(tool: :publish, body_tokens: tokens(*words), kind: :new_turn, raw: "publish #{words.join(' ')}"),
      conversation: Conversation.singleton
    )
  end

  let!(:channel) { create(:channel) }
  let!(:video)   { create(:video, channel: channel, title: "My Review", privacy_status: :private, publish_at: 1.day.from_now) }

  it "emits a :confirmation event (not a direct update)" do
    result = handler_for("video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:kind]).to eq(:confirmation)
  end

  it "does NOT update the video directly" do
    handler_for("video", video.id.to_s).call
    expect(video.reload.privacy_status).to eq("private")
  end

  it "carries command video_publish in the confirmation payload" do
    result = handler_for("video", video.id.to_s).call
    expect(result.events.first[:payload]["command"]).to eq("video_publish")
  end

  it "carries video_id and video_title in the confirmation payload" do
    result = handler_for("video", video.id.to_s).call
    payload = result.events.first[:payload]
    expect(payload["video_id"]).to eq(video.id)
    expect(payload["video_title"]).to eq(video.title)
  end

  it "includes the video title in the confirmation body" do
    result = handler_for("video", video.id.to_s).call
    expect(result.events.first[:payload]["body"]).to include("My Review")
  end

  it "returns not-found for a title reference (id-only resolution)" do
    result = handler_for("video", "my", "review").call
    expect(result.events.first[:payload]["text"]).to include("my review")
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
    expect(result.message_key).to eq("pito.chat.publish.needs_ref")
  end

  describe "the spacing law at stage time (publish-now dry-run)" do
    it "refuses publish-now within 4 hours of another scheduled vid, naming it" do
      create(:video, channel: channel, title: "Queued Up", publish_at: 2.hours.from_now)
      result = handler_for("video", video.id.to_s).call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload]["text"]).to include("Queued Up")
    end

    it "refuses a third publish inside 24h (day cap)" do
      create(:video, :public, channel: channel, publish_at: nil, published_at: 10.hours.ago)
      create(:video, channel: channel, publish_at: 10.hours.from_now)
      result = handler_for("video", video.id.to_s).call
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["text"]).to include("third publish")
    end
  end

  context "handler does not gate on video state or connection health" do
    it "emits :confirmation for an already-public video" do
      public_video = create(:video, channel: channel, privacy_status: :public)
      result = handler_for("video", public_video.id.to_s).call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
    end

    it "emits :confirmation when the channel has no youtube_connection" do
      bare_channel = create(:channel)
      unconnected_video = create(:video, channel: bare_channel)
      result = handler_for("video", unconnected_video.id.to_s).call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
    end

    it "emits :confirmation when the channel's connection has needs_reauth: true" do
      stale_connection = create(:youtube_connection, :needs_reauth)
      stale_channel = create(:channel, youtube_connection: stale_connection)
      stale_video = create(:video, channel: stale_channel)
      result = handler_for("video", stale_video.id.to_s).call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:confirmation)
    end
  end

  context "id-only resolution via real lexer/parser" do
    it "resolves by id and emits a confirmation" do
      result = Pito::Chat::Parser.call(
        Pito::Lex::Lexer.call("publish video #{video.id}"),
        raw: "publish video #{video.id}",
        conversation: Conversation.singleton
      )
      handler = described_class.new(message: result, conversation: Conversation.singleton)
      out = handler.call
      expect(out).to be_a(Pito::Chat::Result::Ok)
      expect(out.events.first[:kind]).to eq(:confirmation)
    end

    it "returns not-found for a title ref via real lexer/parser" do
      result = Pito::Chat::Parser.call(
        Pito::Lex::Lexer.call("publish video My Review"),
        raw: "publish video My Review",
        conversation: Conversation.singleton
      )
      handler = described_class.new(message: result, conversation: Conversation.singleton)
      out = handler.call
      expect(out).to be_a(Pito::Chat::Result::Ok)
      expect(out.events.first[:kind]).to eq(:system)
    end
  end
end
