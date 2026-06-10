# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Show do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  def handler_for(*words)
    described_class.new(
      message: Pito::Chat::Message.new(verb: :show, body_tokens: tokens(*words), kind: :new_turn, raw: "show #{words.join(' ')}"),
      conversation: Conversation.singleton
    )
  end

  # Dispatch through the REAL lexer + parser (not hand-built tokens) so that
  # tokenization regressions are exercised end to end.
  def show_real(input)
    msg = Pito::Chat::Parser.call(
      Pito::Lex::Lexer.call(input), raw: input, conversation: Conversation.singleton
    )
    described_class.new(message: msg, conversation: Conversation.singleton).call
  end

  let!(:game) { create(:game, title: "Lies of P") }

  # ── Game branch — id resolution ───────────────────────────────────────────────

  it "shows a game by id (#N)" do
    payload = handler_for("##{game.id}").call.events.first[:payload]
    expect(payload["body"]).to include("Lies of P")
  end

  it "shows a game by bare id" do
    payload = handler_for(game.id.to_s).call.events.first[:payload]
    expect(payload["body"]).to include("Lies of P")
  end

  it "shows a game by id with noun filler 'game'" do
    payload = handler_for("game", game.id.to_s).call.events.first[:payload]
    expect(payload["body"]).to include("Lies of P")
  end

  it "shows a game by id with noun filler 'games'" do
    payload = handler_for("games", game.id.to_s).call.events.first[:payload]
    expect(payload["body"]).to include("Lies of P")
  end

  it "stamps the detail message follow-up-able (game_detail)" do
    payload = handler_for("##{game.id}").call.events.first[:payload]
    expect(Pito::FollowUp.followupable?(payload)).to be(true)
    expect(payload["reply_target"]).to eq("game_detail")
  end

  it "also emits the Enhanced message (kind :enhanced, not follow-up-able)" do
    events = handler_for("##{game.id}").call.events
    enhanced = events.find { |e| e[:kind] == :enhanced }
    expect(enhanced).to be_present
    expect(enhanced[:payload]["html"]).to be(true)
    expect(enhanced[:payload]["reply_handle"]).to be_blank
    expect(enhanced[:payload]["body"]).to include("pito-game-enhanced-message")
  end

  # ── Game branch — title refs are REJECTED (id-only resolution) ───────────────

  it "returns not-found when a title ref is given — NOT a detail card (id-only resolution)" do
    result = handler_for("game", "lies", "of", "p").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    # not-found text is present; no detail card
    expect(result.events.first[:payload]["text"]).to be_present
    expect(result.events.first[:payload]["game_id"]).to be_nil
  end

  it "returns not-found for a double-quoted title (id-only — quotes do not help)" do
    result = show_real('show game "Lies of P"')
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to be_present
    expect(result.events.first[:payload]["game_id"]).to be_nil
  end

  it "returns not-found for a multi-word title (no quotes)" do
    result = show_real("show game Lies of P")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to be_present
    expect(result.events.first[:payload]["game_id"]).to be_nil
  end

  it "returns a usage hint when no reference is given" do
    result = handler_for.call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.show.needs_ref")
  end

  it "resolves by numeric id through the real lexer/parser" do
    result = show_real("show game #{game.id}")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["game_id"]).to eq(game.id)
  end

  # ── Video branch ──────────────────────────────────────────────────────────────

  context "show video" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel, title: "My Gaming Highlights") }

    it "shows a video by id (#N)" do
      payload = handler_for("video", "##{video.id}").call.events.first[:payload]
      expect(payload["body"]).to include("My Gaming Highlights")
    end

    it "shows a video by bare id" do
      payload = handler_for("video", video.id.to_s).call.events.first[:payload]
      expect(payload["body"]).to include("My Gaming Highlights")
    end

    it "shows a video with plural noun filler 'videos'" do
      payload = handler_for("videos", video.id.to_s).call.events.first[:payload]
      expect(payload["body"]).to include("My Gaming Highlights")
    end

    it "stamps the detail message follow-up-able (video_detail)" do
      payload = handler_for("video", "##{video.id}").call.events.first[:payload]
      expect(Pito::FollowUp.followupable?(payload)).to be(true)
      expect(payload["reply_target"]).to eq("video_detail")
    end

    it "stamps video_id in the payload" do
      payload = handler_for("video", "##{video.id}").call.events.first[:payload]
      expect(payload["video_id"]).to eq(video.id)
    end

    it "emits two events — :system detail then :enhanced placeholder" do
      events = handler_for("video", "##{video.id}").call.events
      expect(events.map { |e| e[:kind] }).to eq([ :system, :enhanced ])
    end

    it "the :system event payload has the video title and video_id" do
      events = handler_for("video", "##{video.id}").call.events
      system_payload = events.first[:payload]
      expect(system_payload["body"]).to include("My Gaming Highlights")
      expect(system_payload["video_id"]).to eq(video.id)
    end

    it "the :enhanced event payload body includes the video title" do
      events = handler_for("video", "##{video.id}").call.events
      enhanced_payload = events.last[:payload]
      expect(enhanced_payload["body"]).to include("My Gaming Highlights")
    end

    # ── Video title refs are REJECTED (id-only resolution) ────────────────────

    it "returns not-found when a title ref is given — NOT a detail card (id-only resolution)" do
      result = handler_for("video", "my", "gaming", "highlights").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to be_present
      expect(result.events.first[:payload]["video_id"]).to be_nil
    end

    it "returns not-found for a double-quoted video title (id-only — quotes do not help)" do
      result = show_real('show video "My Gaming Highlights"')
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to be_present
      expect(result.events.first[:payload]["video_id"]).to be_nil
    end

    it "returns a usage hint when only the noun is given (no ref)" do
      result = handler_for("video").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.show.needs_ref")
    end

    it "resolves by numeric id through the real lexer/parser" do
      result = show_real("show video #{video.id}")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["video_id"]).to eq(video.id)
    end

    it "game show STILL works unchanged when no video noun present" do
      result = handler_for("game", game.id.to_s).call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      payload = result.events.first[:payload]
      expect(payload["reply_target"]).to eq("game_detail")
    end
  end
end
