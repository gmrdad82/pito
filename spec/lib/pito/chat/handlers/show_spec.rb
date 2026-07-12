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
      message: Pito::Chat::Message.new(tool: :show, body_tokens: tokens(*words), kind: :new_turn, raw: "show #{words.join(' ')}"),
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

  # Helpers for full-segment emission when the segment-selection word "full"
  # cannot be appended to message.raw without corrupting extract_ref_from
  # (which treats everything after the noun as the entity ref).
  #
  # Approach A (video / analytics): follow-up context — resolve_target reads
  # the entity id from the source-event payload, never from raw.
  # Approach B (channel): raw: "full" + scoped channel param — channel_ref
  # is blank so scoped_channel_handle takes over.

  def full_video_handler_for(video_record)
    source = Struct.new(:payload).new(
      { "video_id" => video_record.id, "reply_target" => "video_detail" }
    )
    fu = Pito::Chat::FollowUpContext.new(source_event: source, rest: "full")
    described_class.new(
      message: Pito::Chat::Message.new(tool: :show, body_tokens: tokens("full"), kind: :new_turn, raw: "full"),
      conversation: Conversation.singleton,
      follow_up: fu
    )
  end

  def full_linked_game_event(video_record)
    full_video_handler_for(video_record).call.events
      .find { |e| e[:payload]["reply_target"] == "game_detail" }
  end

  def full_channel_events_for(channel_handle)
    described_class.new(
      message: Pito::Chat::Message.new(tool: :show, body_tokens: tokens("channel"), kind: :new_turn, raw: "full"),
      conversation: Conversation.singleton,
      channel: channel_handle
    ).call.events
  end

  let!(:game) { create(:game, title: "Lies of P") }

  # ── Game branch — id resolution ───────────────────────────────────────────────

  # No-guess (owner 2026-06-29): in free chat a bare id with NO entity noun is no
  # longer silently treated as a game — it returns the generic `pito.copy.huh`
  # error. The positive "game by id" path now requires an explicit `game` noun
  # (covered below).
  it "bare hash id (#N, no noun) → unknown_entity error (pito.copy.huh), not a game" do
    result = handler_for("##{game.id}").call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(I18n.t("pito.copy.huh")).to include(result.message_key)
  end

  it "bare id (no noun) → unknown_entity error (pito.copy.huh), not a game" do
    result = handler_for(game.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(I18n.t("pito.copy.huh")).to include(result.message_key)
  end

  it "shows a game by id with explicit hash id + `game` noun" do
    payload = handler_for("game", "##{game.id}").call.events.first[:payload]
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
    payload = handler_for("game", "##{game.id}").call.events.first[:payload]
    expect(Pito::FollowUp.followupable?(payload)).to be(true)
    expect(payload["reply_target"]).to eq("game_detail")
  end

  it "emits the at-a-glance even for a game with no linked videos (item 5: always present)" do
    events    = handler_for("first", "game", "full").call.events
    analytics = events.find { |e| e[:payload].dig("analytics", "status") == "pending" }
    expect(analytics).not_to be_nil
  end

  it "emits two enhanced recommendations messages (SimilarGames + Channels, kind :enhanced, each follow-up-able)" do
    events = handler_for("first", "game", "full").call.events
    recs = events.select { |e| e[:payload]["body"]&.include?("pito-game-enhanced-message") }
    expect(recs.length).to eq(2)
    recs.each do |r|
      expect(r[:kind]).to eq(:enhanced)
      expect(r[:payload]["html"]).to be(true)
      expect(r[:payload]["reply_handle"]).to be_present
    end
    expect(recs.first[:payload]["reply_target"]).to eq("game_similar")
    expect(recs.last[:payload]["reply_target"]).to eq("game_channels")
  end

  it "emits events in order: detail → SimilarGames → Channels (no analytics when no linked videos)" do
    events = handler_for("first", "game", "full").call.events
    detail_idx  = events.index { |e| e[:payload]["reply_target"] == "game_detail" }
    recs        = events.each_with_index.select { |e, _| e[:payload]["body"]&.include?("pito-game-enhanced-message") }
    similar_idx = recs.first&.last
    chans_idx   = recs.last&.last

    expect(detail_idx).to be < similar_idx
    expect(similar_idx).to be < chans_idx
  end

  # ── Game branch — linked videos list ─────────────────────────────────────────

  context "linked videos" do
    def linked_videos_event(*words)
      handler_for(*words).call.events.find { |e| e[:payload]["reply_target"] == "game_linked_videos" }
    end

    context "when the game has linked videos" do
      let!(:channel) { create(:channel, handle: "@bossarena") }
      let!(:video)   { create(:video, channel: channel, title: "Boss Fight") }
      let!(:vgl)     { create(:video_game_link, video: video, game: game) }

      it "emits an :enhanced linked-videos list message after detail and SimilarGames" do
        events = handler_for("first", "game", "full").call.events
        list_index   = events.index { |e| e[:payload]["reply_target"] == "game_linked_videos" }
        detail_index = events.index { |e| e[:payload]["reply_target"] == "game_detail" }
        expect(list_index).to be_present
        expect(events[list_index][:kind]).to eq(:enhanced)
        # detail → SimilarGames → LinkedVideos, so linked videos are at detail_index + 2
        expect(list_index).to eq(detail_index + 2)
      end

      it "emits events in order: detail → SimilarGames → linked-videos → Channels → analytics" do
        events = handler_for("first", "game", "full").call.events
        detail_idx    = events.index { |e| e[:payload]["reply_target"] == "game_detail" }
        videos_idx    = events.index { |e| e[:payload]["reply_target"] == "game_linked_videos" }
        recs          = events.each_with_index.select { |e, _| e[:payload]["body"]&.include?("pito-game-enhanced-message") }
        similar_idx   = recs.first&.last
        chans_idx     = recs.last&.last
        analytics_idx = events.index { |e| e[:payload].dig("analytics", "status") == "pending" }

        expect(detail_idx).to be < similar_idx
        expect(similar_idx).to be < videos_idx
        expect(videos_idx).to be < chans_idx
        expect(chans_idx).to be < analytics_idx
      end

      it "emits an analytics pending event for the game (kind :enhanced, scope_type Game)" do
        events    = handler_for("first", "game", "full").call.events
        analytics = events.find { |e| e[:payload].dig("analytics", "status") == "pending" }

        expect(analytics).to be_present
        expect(analytics[:kind]).to eq(:enhanced)
        expect(analytics[:payload]["html"]).to be(true)
        expect(analytics[:payload].dig("analytics", "scope_type")).to eq("Game")
        expect(analytics[:payload].dig("analytics", "scope_id")).to eq(game.id)
      end

      it "is repliable via the game_linked_videos follow-up target (game context for unlink)" do
        payload = linked_videos_event("first", "game", "full")[:payload]
        expect(Pito::FollowUp.followupable?(payload)).to be(true)
        expect(payload["reply_target"]).to eq("game_linked_videos")
        expect(payload["game_id"]).to eq(game.id)
      end

      it "lists the linked video as a table row" do
        payload = linked_videos_event("first", "game", "full")[:payload]
        expect(payload["table_rows"].size).to eq(1)
        expect(payload["video_ids"]).to eq([ video.id ])
      end

      it "names the channel the game appears on in the intro body (witty channels line)" do
        payload = linked_videos_event("first", "game", "full")[:payload]
        expect(payload["body"]).to include(channel.handle)
      end
    end

    context "when the game has no linked videos" do
      it "emits no linked-videos (video_list) message" do
        expect(linked_videos_event("game", "##{game.id}")).to be_nil
      end
    end
  end

  # ── Game branch — segment alias: similars → similar ──────────────────────────

  context "segment alias 'similars'" do
    it "'show game N with similars' emits the similar (game_similar) enhanced event" do
      result = show_real("show game #{game.id} with similars")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      similar_event = result.events.find { |e| e[:payload]["reply_target"] == "game_similar" }
      expect(similar_event).to be_present
      expect(similar_event[:kind]).to eq(:enhanced)
    end

    it "'show game N with similars' does not report similars as unknown (no error event)" do
      result = show_real("show game #{game.id} with similars")
      expect(result.events.map { |e| e[:payload]["reply_target"] }).not_to include("error")
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

  # No-guess (owner 2026-06-29): a bare `show` (no entity noun at all) is not the
  # game picker — it returns the generic `pito.copy.huh` error.
  it "bare `show` (no entity) → unknown_entity error (pito.copy.huh)" do
    result = handler_for.call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(I18n.t("pito.copy.huh")).to include(result.message_key)
  end

  # ── not-found is a soft Ok: consume: false so a `#<handle>` reply can retry ──────
  it "returns a not-found game with consume: false (reply source stays repliable)" do
    result = show_real("show game #{game.id + 999}")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.consume).to be(false)
  end

  it "returns a not-found vid with consume: false (reply source stays repliable)" do
    result = show_real("show vid 999999")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.consume).to be(false)
  end

  it "a successful show consumes by default (consume: true)" do
    result = show_real("show game #{game.id}")
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.consume).to be(true)
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
      events = full_video_handler_for(video).call.events
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
      events    = full_video_handler_for(video).call.events
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
          events    = full_video_handler_for(video).call.events
          card_index   = events.index { |e| e[:payload]["reply_target"] == "game_detail" }
          detail_index = events.index { |e| e[:payload]["reply_target"] == "video_detail" }
          last_index   = events.size - 1

          expect(card_index).to be > detail_index
          expect(card_index).to be < last_index
          expect(events[card_index][:kind]).to eq(:enhanced)
        end

        it "renders the linked game's title in the card" do
          payload = full_linked_game_event(video)[:payload]
          expect(payload["body"]).to include("Lies of P")
        end

        it "is repliable via the game_detail follow-up target" do
          payload = full_linked_game_event(video)[:payload]
          expect(Pito::FollowUp.followupable?(payload)).to be(true)
          expect(payload["reply_target"]).to eq("game_detail")
        end

        it "stamps the linked game's id in the card payload" do
          payload = full_linked_game_event(video)[:payload]
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

  # ── Analytics period resolution ────────────────────────────────────────────

  context "analytics period resolution" do
    let!(:channel_for_period) { create(:channel) }
    let!(:video_for_period)   { create(:video, channel: channel_for_period, title: "Period Test") }

    def handler_with(period:, conversation: Conversation.singleton)
      # Use a follow-up context so the video is resolved from the payload
      # and raw: "full" drives parse_selection without corrupting the ref.
      source = Struct.new(:payload).new(
        { "video_id" => video_for_period.id, "reply_target" => "video_detail" }
      )
      fu = Pito::Chat::FollowUpContext.new(source_event: source, rest: "full")
      msg = Pito::Chat::Message.new(tool: :show, body_tokens: tokens("full"), kind: :new_turn, raw: "full")
      described_class.new(message: msg, conversation: conversation, period: period, follow_up: fu)
    end

    def analytics_period_from(events)
      event = events.find { |e| e[:payload].dig("analytics", "status") == "pending" }
      event&.dig(:payload, "analytics", "period")
    end

    # The at-a-glance is LOCKED to lifetime (item 5) — every metric is an all-time
    # total — so the glance pending payload ALWAYS carries "lifetime", ignoring both
    # an explicit period param and the conversation's stats_period (those still drive
    # the `analyze` verb, not the glance).
    it "forces the glance pending payload to lifetime, ignoring an explicit period param" do
      events = handler_with(period: "28d").call.events
      expect(analytics_period_from(events)).to eq("lifetime")
    end

    it "forces lifetime even when the conversation has a non-default stats_period" do
      conv = Conversation.singleton
      conv.update!(stats_period: "3m")
      events = handler_with(period: nil, conversation: conv).call.events
      expect(analytics_period_from(events)).to eq("lifetime")
    end

    it "at-a-glance over multiple vid ids → ONE combined glance (scope_ids, '2 vids')" do
      ch = create(:channel)
      v1 = create(:video, channel: ch, title: "A")
      v2 = create(:video, channel: ch, title: "B")

      result = Pito::Dispatch::Router.call(
        input: "at-a-glance videos #{v1.id},#{v2.id}",
        conversation: Conversation.singleton, channel: "@all", period: nil, viewport_width: 900
      )
      glance = result.events.find { |e| e[:payload]["analytics"] }
      expect(glance[:payload].dig("analytics", "scope_ids")).to match_array([ v1.id, v2.id ])
      expect(glance[:payload].dig("analytics", "scope_id")).to be_nil
      expect(glance[:payload]["body"]).to include("2 vids")
    end
  end

  # ── Channel branch — @handle resolution ───────────────────────────────────────

  describe "show channel @handle" do
    let!(:show_channel) { create(:channel, handle: "gmrdad82", title: "GMR Dad", description: "Stories.") }

    it "resolves a channel by @handle and emits a :system detail card" do
      result = show_real("show channel @gmrdad82")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload]["html"]).to be(true)
      expect(event[:payload]["body"]).to include("GMR Dad").and include("@gmrdad82")
    end

    it "resolves @-agnostic + case-insensitively (show channel GMRDAD82)" do
      event = show_real("show channel GMRDAD82").events.first
      expect(event[:payload]["body"]).to include("GMR Dad")
    end

    # Regression for #6: a bare handle with no leading @ must resolve.
    it "resolves a bare handle with no @ (show channel gmrdad82)" do
      event = show_real("show channel gmrdad82").events.first
      expect(event[:payload]["body"]).to include("GMR Dad").and include("@gmrdad82")
    end

    # #7: a fuzzy/partial handle resolves via pg_trgm.
    it "fuzzy-resolves a partial handle (show channel gmrdad)" do
      event = show_real("show channel gmrdad").events.first
      expect(event[:payload]["body"]).to include("GMR Dad")
    end

    it "renders the description in the card" do
      event = show_real("show channel @gmrdad82").events.first
      expect(event[:payload]["body"]).to include("Stories.")
    end

    it "returns a witty not-found for an unknown handle (does NOT consume)" do
      result = show_real("show channel @nope")
      expect(result.consume).to be(false)
      expect(result.events.first[:payload].to_s).to include("nope")
    end

    # Regression (owner 2026-06-29): a bare `show channel` must read as a CHANNEL,
    # never fall through to the game picker ("Which game?"). The 2nd token is the
    # entity — no guessing.
    context "bare `show channel` (regression: channel, never the game picker)" do
      def show_scoped(input, scope)
        msg = Pito::Chat::Parser.call(Pito::Lex::Lexer.call(input), raw: input, conversation: Conversation.singleton)
        described_class.new(message: msg, conversation: Conversation.singleton, channel: scope).call
      end

      def body_text(result)
        pl = result.events.first[:payload]
        (pl["text"] || pl["body"]).to_s
      end

      it "with NO channel scope → asks which CHANNEL (not 'Which game?')" do
        result = show_scoped("show channel", nil)
        expect(body_text(result)).to include("Which channel")
        expect(body_text(result)).not_to include("Which game")
      end

      it "with the @all scope → still asks which channel, not which game" do
        result = show_scoped("show channel", "@all")
        expect(body_text(result)).to include("Which channel")
        expect(body_text(result)).not_to include("Which game")
      end

      it "with a specific shift+tab channel scope → resolves THAT channel's detail card" do
        result = show_scoped("show channel", "@gmrdad82")
        event = result.events.first
        expect(event[:kind]).to eq(:system)
        expect(event[:payload]["body"]).to include("GMR Dad")
      end
    end

    it "emits :system detail + the :enhanced channel analytics glance when the channel has no videos" do
      events = full_channel_events_for("@gmrdad82")
      expect(events.map { |e| e[:kind] }).to eq([ :system, :enhanced ])
      glance = events.last[:payload]
      expect(glance.dig("analytics", "status")).to eq("pending")
      expect(glance.dig("analytics", "scope_type")).to eq("Channel")
      expect(glance.dig("analytics", "scope_id")).to eq(show_channel.id)
    end

    context "with videos" do
      let!(:vids) { create_list(:video, 2, channel: show_channel) }

      it "emits :system detail, a repliable :enhanced vids list, then the :enhanced analytics glance" do
        events = full_channel_events_for("@gmrdad82")
        expect(events.map { |e| e[:kind] }).to eq([ :system, :enhanced, :enhanced ])

        list = events[1][:payload]
        expect(list["reply_target"]).to eq("video_list")
        expect(Pito::FollowUp.followupable?(list)).to be(true)
        expect(list["video_ids"]).to match_array(vids.map(&:id))

        glance = events.last[:payload]
        expect(glance.dig("analytics", "scope_type")).to eq("Channel")
      end
    end
  end

  # ── Ordinal selectors: show first|last game (Phase FL) ────────────────────────

  describe "show first|last game — ordinal resolution" do
    # Helper: creates a game with a fully specified release_date (derived from
    # year/month/day by the before_save callback).
    def game_with_date(year, month, day, **attrs)
      create(:game, release_year: year, release_month: month, release_day: day, **attrs)
    end

    # Convenience: invoke the real lexer + parser + handler with an optional
    # channel param (mirrors the shift+tab channel scope).
    def show_real_channel(input, channel: nil)
      msg = Pito::Chat::Parser.call(
        Pito::Lex::Lexer.call(input), raw: input, conversation: Conversation.singleton
      )
      described_class.new(message: msg, conversation: Conversation.singleton, channel: channel).call
    end

    let!(:old_game) { game_with_date(2018, 1, 1,  title: "Old Game") }
    let!(:new_game) { game_with_date(2023, 12, 25, title: "New Game") }

    it "show first game → game_detail for the earliest-released game" do
      result = show_real("show first game")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["body"]).to include("Old Game")
    end

    it "show last game → game_detail for the latest-released game" do
      result = show_real("show last game")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["body"]).to include("New Game")
    end

    it "show first game emits :system detail as the first event (kind :system)" do
      result = show_real("show first game")
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["reply_target"]).to eq("game_detail")
    end

    it "show last game is follow-up-able (reply_target: game_detail)" do
      result = show_real("show last game")
      payload = result.events.first[:payload]
      expect(Pito::FollowUp.followupable?(payload)).to be(true)
      expect(payload["reply_target"]).to eq("game_detail")
    end

    it "show last game → not-found (consume: false) when no game matches the genre filter" do
      # old_game and new_game have no genres — RPG filter returns nothing
      result = show_real("show last rpg game")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.consume).to be(false)
    end

    context "with genre filter" do
      let!(:rpg_genre) { create(:genre, name: "Role-playing") }
      let!(:rpg_game)  { game_with_date(2021, 6, 1, title: "RPG Game") }

      before { create(:game_genre, game: rpg_game, genre: rpg_genre, position: 1) }

      it "show last rpg game → game_detail for the latest RPG (genre alias resolved)" do
        result = show_real("show last rpg game")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:payload]["body"]).to include("RPG Game")
      end

      it "show first rpg game → game_detail for the earliest RPG" do
        result = show_real("show first rpg game")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:payload]["body"]).to include("RPG Game")
      end
    end

    context "with channel scope (shift+tab @handle)" do
      let!(:ch)          { create(:channel, handle: "@ordinalchan") }
      let!(:ch_vid)      { create(:video, channel: ch) }
      let!(:linked_game) { game_with_date(2022, 4, 20, title: "Linked To Chan") }

      before { create(:video_game_link, video: ch_vid, game: linked_game) }

      it "show last game scoped to @ordinalchan returns only the channel's game" do
        # old_game and new_game have no channel links; linked_game does
        result = show_real_channel("show last game", channel: "@ordinalchan")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:payload]["body"]).to include("Linked To Chan")
      end

      it "show last game with @all channel scope returns the global latest game" do
        result = show_real_channel("show last game", channel: "@all")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:payload]["body"]).to include("New Game")
      end

      it "show last game with unknown channel → not-found (consume: false)" do
        result = show_real_channel("show last game", channel: "@nope")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.consume).to be(false)
      end
    end

    # Regression: ID-based resolution still works after the ordinal branch was added.
    it "show game <id> still resolves by id (ordinal branch does not fire for numeric refs)" do
      result = show_real("show game #{new_game.id}")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["game_id"]).to eq(new_game.id)
    end
  end

  # ── Ordinal selectors: show first|last vid (Phase FL) ─────────────────────────

  describe "show first|last vid — ordinal resolution" do
    def show_real_channel(input, channel: nil)
      msg = Pito::Chat::Parser.call(
        Pito::Lex::Lexer.call(input), raw: input, conversation: Conversation.singleton
      )
      described_class.new(message: msg, conversation: Conversation.singleton, channel: channel).call
    end

    let!(:vid_channel)  { create(:channel, handle: "@vidchan") }
    let!(:vid_old)      { create(:video, :public, channel: vid_channel, title: "Old Vid", published_at: 2.years.ago) }
    let!(:vid_new)      { create(:video, :public, channel: vid_channel, title: "New Vid", published_at: 1.day.ago) }
    let!(:vid_unlisted) { create(:video, :unlisted, channel: vid_channel, title: "Unlisted Vid") }

    it "show last vid → video_detail for the latest published video (alias: last published vid)" do
      result = show_real("show last vid")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["body"]).to include("New Vid")
    end

    it "show first vid → video_detail for the earliest published video" do
      result = show_real("show first vid")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["body"]).to include("Old Vid")
    end

    it "show last published vid → same result as show last vid (alias confirmed)" do
      result_alias  = show_real("show last vid")
      result_explicit = show_real("show last published vid")
      # Both should resolve to the same video (vid_new — the latest public vid)
      expect(result_alias.events.first[:payload]["video_id"]).to(
        eq(result_explicit.events.first[:payload]["video_id"])
      )
    end

    it "show last unlisted vid → video_detail for the latest unlisted video" do
      result = show_real("show last unlisted vid")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["body"]).to include("Unlisted Vid")
    end

    it "show last vid emits :system detail as the first event" do
      result = show_real("show last vid")
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["reply_target"]).to eq("video_detail")
    end

    it "show last vid is follow-up-able (reply_target: video_detail)" do
      payload = show_real("show last vid").events.first[:payload]
      expect(Pito::FollowUp.followupable?(payload)).to be(true)
    end

    it "show last private vid → not-found (consume: false) when no private video exists" do
      result = show_real("show last private vid")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.consume).to be(false)
    end

    context "with channel scope (shift+tab @handle)" do
      let!(:other_chan)    { create(:channel, handle: "@othervid") }
      let!(:other_vid_pub) { create(:video, :public, channel: other_chan, title: "Other Chan Vid", published_at: 3.days.ago) }

      it "show last vid scoped to @vidchan returns that channel's latest published video" do
        result = show_real_channel("show last vid", channel: "@vidchan")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:payload]["body"]).to include("New Vid")
      end

      it "show last vid with @all channel scope returns the global latest published video" do
        result = show_real_channel("show last vid", channel: "@all")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        # vid_new (1.day.ago) is more recent than other_vid_pub (3.days.ago)
        expect(result.events.first[:payload]["body"]).to include("New Vid")
      end

      it "show last vid with unknown channel → not-found (consume: false)" do
        result = show_real_channel("show last vid", channel: "@nope")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.consume).to be(false)
      end
    end

    # Regression: ID-based resolution still works after the ordinal branch was added.
    it "show vid <id> still resolves by id (ordinal branch does not fire for numeric refs)" do
      result = show_real("show vid #{vid_new.id}")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["video_id"]).to eq(vid_new.id)
    end

    # Regression: video not-found path unchanged.
    it "show vid 999999 still returns not-found (consume: false)" do
      result = show_real("show vid 999999")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.consume).to be(false)
    end
  end

  # ── Segment selection ──────────────────────────────────────────────────────────
  #
  # Covers the SegmentSelection grammar wired into the show handler.
  # Assertions use event shape (kinds, reply_target, analytics hash) —
  # never copy text (50-variant dictionaries).

  describe "segment selection" do
    # ── Game entity — full coverage ──────────────────────────────────────────────

    context "game entity" do
      # Uses the outer game fixture (only game in DB for these examples).
      # Ordinal form "first game" resolves via OrdinalResolver — this keeps
      # the segment-selection keyword out of the entity-ref extraction path
      # (extract_ref_from treats everything after the noun as the ref).

      it "bare → emits only the detail segment (:system, no :enhanced)" do
        # Bare id-based form — the default selection emits detail only.
        events = handler_for("game", "##{game.id}").call.events
        expect(events.map { |e| e[:kind] }).to eq([ :system ])
        expect(events.first[:payload]["reply_target"]).to eq("game_detail")
      end

      # Regression (found 2026-07-03): a selection clause after a DIRECT id/handle
      # ref must not leak into reference extraction — `show game 5 full` used to
      # yield ref "5 full" and fail the numeric check (not-found). The handler now
      # strips the clause via SegmentSelection.strip before resolution.
      it "direct id + full → resolves the ref and emits all segments" do
        events = handler_for("game", "##{game.id}", "full").call.events
        expect(events.first[:kind]).to eq(:system)
        expect(events.first[:payload]["reply_target"]).to eq("game_detail")
        expect(events.size).to be > 1
      end

      it "direct bare id + only at-a-glance → resolves the ref, emits exactly at-a-glance" do
        events = handler_for("game", game.id.to_s, "only", "at-a-glance").call.events
        expect(events.map { |e| e[:kind] }).to eq([ :enhanced ])
        expect(events.first[:payload].dig("analytics", "status")).to eq("pending")
      end

      it "full → emits all segments in table order; linked-videos absent when game has none" do
        # detail(:system) + similar(:enhanced) + channels(:enhanced) + at-a-glance(:enhanced)
        events = handler_for("first", "game", "full").call.events
        expect(events.map { |e| e[:kind] }).to eq([ :system, :enhanced, :enhanced, :enhanced ])
        expect(events.first[:payload]["reply_target"]).to eq("game_detail")
        expect(events.none? { |e| e[:payload]["reply_target"] == "game_linked_videos" }).to be(true)
      end

      it "with at-a-glance → emits detail then at-a-glance (table order)" do
        events = handler_for("first", "game", "with", "at-a-glance").call.events
        expect(events.size).to eq(2)
        expect(events.first[:payload]["reply_target"]).to eq("game_detail")
        expect(events.last[:payload].dig("analytics", "status")).to eq("pending")
      end

      it "only at-a-glance → emits exactly at-a-glance (:enhanced, no :system event)" do
        events = handler_for("first", "game", "only", "at-a-glance").call.events
        expect(events.map { |e| e[:kind] }).to eq([ :enhanced ])
        expect(events.first[:payload].dig("analytics", "status")).to eq("pending")
      end

      it "only channels,similar (reversed input) → emits in TABLE order: similar then channels" do
        events = handler_for("first", "game", "only", "channels,similar").call.events
        expect(events.size).to eq(2)
        expect(events.first[:payload]["reply_target"]).to eq("game_similar")
        expect(events.last[:payload]["reply_target"]).to eq("game_channels")
      end

      it "unknown token → returns an error Result" do
        result = handler_for("first", "game", "only", "bogus").call
        expect(result).to be_a(Pito::Chat::Result::Error)
      end

      it "full with detail (multiple introducers) → returns a conflict error Result" do
        result = handler_for("first", "game", "full", "with", "detail").call
        expect(result).to be_a(Pito::Chat::Result::Error)
      end

      it "without channels → Ok result; channels segment absent from emitted events" do
        result = show_real("show game #{game.id} without channels")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        reply_targets = result.events.map { |e| e[:payload]["reply_target"] }
        expect(reply_targets).not_to include("game_channels")
        expect(reply_targets).to include("game_detail")
      end

      it "without at-a-glance,similar → Ok result; emits detail (and linked-videos + channels when present)" do
        result = show_real("show game #{game.id} without at-a-glance,similar")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        reply_targets = result.events.map { |e| e[:payload]["reply_target"] }
        expect(reply_targets).to include("game_detail")
        expect(reply_targets).not_to include("game_similar")
        expect(reply_targets).not_to include("analytics_glance")
      end

      it "without + with (conflict) → Error result" do
        result = show_real("show game #{game.id} without channels with detail")
        expect(result).to be_a(Pito::Chat::Result::Error)
      end
    end

    # ── Channel entity — bare (cheaper single example) ───────────────────────────

    context "channel entity" do
      let!(:sel_channel) { create(:channel, handle: "@selchan", title: "Sel Chan") }

      it "bare → emits only the detail segment (:system)" do
        result = show_real("show channel @selchan")
        expect(result.events.map { |e| e[:kind] }).to eq([ :system ])
      end
    end

    # ── Vid entity — bare (cheaper single example) ───────────────────────────────

    context "vid entity" do
      let!(:sel_vid_channel) { create(:channel) }
      let!(:sel_video)       { create(:video, channel: sel_vid_channel, title: "Sel Vid") }

      it "bare → emits only the detail segment (:system)" do
        events = handler_for("video", "##{sel_video.id}").call.events
        expect(events.map { |e| e[:kind] }).to eq([ :system ])
      end
    end
  end

  # ── D18: segments footer on the first emitted message ──────────────────────────

  context "segments footer (D18)" do
    # Bare `show game` → only detail in selection, so 4 addable and 1 removable.
    it "bare show game: first event has list_footer with the 4 addable segment names" do
      payload = handler_for("game", "##{game.id}").call.events.first[:payload]
      footer  = payload["list_footer"].to_s
      expect(footer).to include("similar")
      expect(footer).to include("videos")
      expect(footer).to include("channels")
      expect(footer).to include("at-a-glance")
    end

    # full → all 5 in selection, so 0 addable and 5 removable (footer shows "nothing" addable + lists removable).
    it "full show game: first event has list_footer with all 5 removable segment names" do
      events  = handler_for("first", "game", "full").call.events
      payload = events.first[:payload]
      footer  = payload["list_footer"].to_s
      expect(footer).to include("detail")
      expect(footer).to include("at-a-glance")
      expect(footer).to include("nothing")
    end

    # segments noun appears in the footer
    it "footer uses 'segments' as the noun" do
      payload = handler_for("game", "##{game.id}").call.events.first[:payload]
      expect(payload["list_footer"].to_s).to include("segments")
    end
  end
end
