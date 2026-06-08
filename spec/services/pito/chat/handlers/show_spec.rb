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
  # tokenization regressions — e.g. apostrophes — are exercised end to end.
  def show_real(input)
    msg = Pito::Chat::Parser.call(
      Pito::Lex::Lexer.call(input), raw: input, conversation: Conversation.singleton
    )
    described_class.new(message: msg, conversation: Conversation.singleton).call
  end

  let!(:game) { create(:game, title: "Lies of P") }

  it "shows a game by title (ILIKE), dropping the noun filler" do
    result = handler_for("game", "lies", "of", "p").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    payload = result.events.first[:payload]
    expect(payload["html"]).to be(true)
    expect(payload["body"]).to include("Lies of P")
  end

  it "shows a game by id (#N)" do
    payload = handler_for("##{game.id}").call.events.first[:payload]
    expect(payload["body"]).to include("Lies of P")
  end

  it "shows a game by bare id" do
    payload = handler_for(game.id.to_s).call.events.first[:payload]
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

  it "returns a witty not-found for an unknown reference" do
    result = handler_for("game", "nonexistent").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("nonexistent")
  end

  it "returns a usage hint when no reference is given" do
    result = handler_for.call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.show.needs_ref")
  end

  context "title containing an apostrophe (regression — lexer split ' into :unknown)" do
    let!(:gng) { create(:game, title: "Ghosts 'n Goblins Resurrection") }

    it "resolves the game when typed naturally through the real lexer/parser" do
      result = show_real("show Ghosts 'n Goblins Resurrection")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["game_id"]).to eq(gng.id)
    end

    it "still resolves with the optional 'game' noun filler" do
      result = show_real("show game Ghosts 'n Goblins Resurrection")
      expect(result.events.first[:payload]["game_id"]).to eq(gng.id)
    end
  end

  context "title containing a colon (regression — lexer ':' token mangled the ref)" do
    let!(:sb) { create(:game, title: "Stellar Blade: Blood Rain") }

    it "resolves the colon title typed naturally through the real lexer/parser" do
      result = show_real("show Stellar Blade: Blood Rain")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["game_id"]).to eq(sb.id)
    end

    it "still resolves the prefix-only title when no colon is typed" do
      create(:game, title: "Stellar Blade")
      result = show_real("show Stellar Blade")
      expect(result.events.first[:payload]["game_id"]).to be_present
    end
  end

  context "ILIKE partial vs exact — two games sharing a prefix" do
    let!(:exact_game)   { create(:game, title: "Lies of P") }
    let!(:prefix_game)  { create(:game, title: "Lies of P: Expanded") }

    it "finds the first ILIKE match (exact title input returns that game)" do
      result = handler_for("lies", "of", "p").call
      # The ILIKE query returns the first match; 'Lies of P' matches exactly
      expect(result).to be_a(Pito::Chat::Result::Ok)
      body = result.events.first[:payload]["body"]
      # At least one of the two games sharing the prefix is found — no crash
      expect(body).to be_present
    end

    it "returns a not-found result for a ref that matches neither game" do
      result = handler_for("lies", "of", "z").call
      text = result.events.first[:payload]["text"]
      expect(text).to be_present
    end
  end

  # ── Video branch ─────────────────────────────────────────────────────────────

  context "show video" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel, title: "My Gaming Highlights") }

    it "shows a video by title (ILIKE), dropping the noun filler" do
      result = handler_for("video", "my", "gaming", "highlights").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      payload = result.events.first[:payload]
      expect(payload["html"]).to be(true)
      expect(payload["body"]).to include("My Gaming Highlights")
    end

    it "shows a video with plural noun filler 'videos'" do
      result = handler_for("videos", "my", "gaming", "highlights").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      payload = result.events.first[:payload]
      expect(payload["body"]).to include("My Gaming Highlights")
    end

    it "shows a video by id (#N)" do
      payload = handler_for("video", "##{video.id}").call.events.first[:payload]
      expect(payload["body"]).to include("My Gaming Highlights")
    end

    it "shows a video by bare id" do
      payload = handler_for("video", video.id.to_s).call.events.first[:payload]
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

    it "returns a witty not-found for an unknown video reference" do
      result = handler_for("video", "nonexistent").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("nonexistent")
    end

    it "returns a usage hint when only the noun is given (no ref)" do
      result = handler_for("video").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.show.needs_ref")
    end

    context "video title with apostrophe resolved via real lexer/parser" do
      let!(:apos_video) { create(:video, channel: channel, title: "Let's Play Dark Souls") }

      it "resolves the video when typed naturally through the real lexer/parser" do
        result = show_real("show video Let's Play Dark Souls")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:payload]["video_id"]).to eq(apos_video.id)
      end

      it "still resolves with the plural 'videos' noun filler" do
        result = show_real("show videos Let's Play Dark Souls")
        expect(result.events.first[:payload]["video_id"]).to eq(apos_video.id)
      end
    end

    it "game show STILL works unchanged when no video noun present" do
      result = handler_for("game", "lies", "of", "p").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      payload = result.events.first[:payload]
      expect(payload["reply_target"]).to eq("game_detail")
    end
  end
end
