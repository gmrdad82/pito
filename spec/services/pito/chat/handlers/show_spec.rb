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

  it "does not emit an analytics message for a game with no linked videos" do
    events    = handler_for("##{game.id}").call.events
    analytics = events.find { |e| e[:payload].dig("analytics", "status") == "pending" }
    expect(analytics).to be_nil
  end

  it "also emits the Enhanced recommendations message (kind :enhanced, not follow-up-able)" do
    events = handler_for("##{game.id}").call.events
    enhanced = events.find { |e| e[:payload]["body"]&.include?("pito-game-enhanced-message") }
    expect(enhanced).to be_present
    expect(enhanced[:kind]).to eq(:enhanced)
    expect(enhanced[:payload]["html"]).to be(true)
    expect(enhanced[:payload]["reply_handle"]).to be_blank
  end

  it "emits events in order: detail → recommendations (no analytics when no linked videos)" do
    events = handler_for("##{game.id}").call.events
    detail_idx = events.index { |e| e[:payload]["reply_target"] == "game_detail" }
    recs_idx   = events.index { |e| e[:payload]["body"]&.include?("pito-game-enhanced-message") }

    expect(detail_idx).to be < recs_idx
  end

  # ── Game branch — linked videos list ─────────────────────────────────────────

  context "linked videos" do
    def linked_videos_event(*words)
      handler_for(*words).call.events.find { |e| e[:payload]["reply_target"] == "video_list" }
    end

    context "when the game has linked videos" do
      let!(:channel) { create(:channel, handle: "@bossarena") }
      let!(:video)   { create(:video, channel: channel, title: "Boss Fight") }
      let!(:vgl)     { create(:video_game_link, video: video, game: game) }

      it "emits an :enhanced linked-videos list message after the detail" do
        events = handler_for("##{game.id}").call.events
        list_index   = events.index { |e| e[:payload]["reply_target"] == "video_list" }
        detail_index = events.index { |e| e[:payload]["reply_target"] == "game_detail" }
        expect(list_index).to be_present
        expect(events[list_index][:kind]).to eq(:enhanced)
        expect(list_index).to eq(detail_index + 1)
      end

      it "emits events in order: detail → linked-videos → recommendations → analytics" do
        events = handler_for("##{game.id}").call.events
        detail_idx    = events.index { |e| e[:payload]["reply_target"] == "game_detail" }
        videos_idx    = events.index { |e| e[:payload]["reply_target"] == "video_list" }
        recs_idx      = events.index { |e| e[:payload]["body"]&.include?("pito-game-enhanced-message") }
        analytics_idx = events.index { |e| e[:payload].dig("analytics", "status") == "pending" }

        expect(detail_idx).to be < videos_idx
        expect(videos_idx).to be < recs_idx
        expect(recs_idx).to be < analytics_idx
      end

      it "emits an analytics pending event for the game (kind :enhanced, scope_type Game)" do
        events    = handler_for("##{game.id}").call.events
        analytics = events.find { |e| e[:payload].dig("analytics", "status") == "pending" }

        expect(analytics).to be_present
        expect(analytics[:kind]).to eq(:enhanced)
        expect(analytics[:payload]["html"]).to be(true)
        expect(analytics[:payload].dig("analytics", "scope_type")).to eq("Game")
        expect(analytics[:payload].dig("analytics", "scope_id")).to eq(game.id)
      end

      it "is repliable via the video_list follow-up target" do
        payload = linked_videos_event("##{game.id}")[:payload]
        expect(Pito::FollowUp.followupable?(payload)).to be(true)
        expect(payload["reply_target"]).to eq("video_list")
      end

      it "lists the linked video as a table row" do
        payload = linked_videos_event("##{game.id}")[:payload]
        expect(payload["table_rows"].size).to eq(1)
        expect(payload["video_ids"]).to eq([ video.id ])
      end

      it "names the channel the game appears on in the intro body (witty channels line)" do
        payload = linked_videos_event("##{game.id}")[:payload]
        expect(payload["body"]).to include(channel.handle)
      end
    end

    context "when the game has no linked videos" do
      it "emits no linked-videos (video_list) message" do
        expect(linked_videos_event("##{game.id}")).to be_nil
      end
    end
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

    it "shows a video with the canonical short noun 'vids'" do
      payload = handler_for("vids", video.id.to_s).call.events.first[:payload]
      expect(payload["body"]).to include("My Gaming Highlights")
    end

    it "shows a video with the singular short noun 'vid'" do
      payload = handler_for("vid", video.id.to_s).call.events.first[:payload]
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

    it "emits an analytics pending event for the video (kind :enhanced, scope_type Video)" do
      events    = handler_for("video", "##{video.id}").call.events
      analytics = events.find { |e| e[:payload].dig("analytics", "status") == "pending" }

      expect(analytics).to be_present
      expect(analytics[:kind]).to eq(:enhanced)
      expect(analytics[:payload]["html"]).to be(true)
      expect(analytics[:payload].dig("analytics", "scope_type")).to eq("Video")
      expect(analytics[:payload].dig("analytics", "scope_id")).to eq(video.id)
    end

    # ── Linked-game card ──────────────────────────────────────────────────────

    context "linked game" do
      def linked_game_event(*words)
        handler_for(*words).call.events.find { |e| e[:payload]["reply_target"] == "game_detail" }
      end

      context "when the video has a linked game" do
        let!(:game) { create(:game, title: "Lies of P") }
        let!(:vgl)  { create(:video_game_link, video: video, game: game) }

        it "emits the slim linked-game card between the detail and the enhanced placeholder" do
          events    = handler_for("video", "##{video.id}").call.events
          card_index   = events.index { |e| e[:payload]["reply_target"] == "game_detail" }
          detail_index = events.index { |e| e[:payload]["reply_target"] == "video_detail" }
          last_index   = events.size - 1

          expect(card_index).to be > detail_index
          expect(card_index).to be < last_index
          expect(events[card_index][:kind]).to eq(:enhanced)
        end

        it "renders the linked game's title in the card" do
          payload = linked_game_event("video", "##{video.id}")[:payload]
          expect(payload["body"]).to include("Lies of P")
        end

        it "is repliable via the game_detail follow-up target" do
          payload = linked_game_event("video", "##{video.id}")[:payload]
          expect(Pito::FollowUp.followupable?(payload)).to be(true)
          expect(payload["reply_target"]).to eq("game_detail")
        end

        it "stamps the linked game's id in the card payload" do
          payload = linked_game_event("video", "##{video.id}")[:payload]
          expect(payload["game_id"]).to eq(game.id)
        end
      end

      context "when the video has no linked game" do
        it "emits no linked-game (game_detail) card" do
          expect(linked_game_event("video", "##{video.id}")).to be_nil
        end
      end
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
