# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `link` (recognition only, DB mocked) ──────────────────────
#
# RULE: every kwarg combination recognised — no exception. We test what the
# handler UNDERSTANDS, not DB persistence. All DB lookups and write operations
# are stubbed; the resolver "finds" exactly what was requested.
#
# Subjects:
#   lib/pito/chat/handlers/link.rb
#   lib/pito/chat/handlers/multi_link_helpers.rb (included in Link)
#
# Free-chat (Handler#call non-follow_up branch):
#   body_tokens joined → split on \b(to|with)\b → left / right halves
#   Each half: noun discriminator (game/games | vid/vids/video/videos) + id list.
#   IDs: plain or #-prefixed numeric, comma-or-space-separated.
#
# Follow-up — detail card (singular video_id / game_id in payload):
#   Source is implied by the card's entity.
#   Targets parsed from follow_up.rest (after connector word or implicitly).
#
# Follow-up — list card (no singular id; array key in payload):
#   Source id on the LEFT of the connector; targets on the RIGHT.
#
# Result shapes:
#   Success   → Result::Ok   { events: [{ kind: :system, payload: { "text" => ... } }] }
#   Not-found → Result::Ok   { events: [{ kind: :system, ... }] }
#   Bad input → Result::Error { message_key: "pito.chat.link.usage" }
#   Follow-up bad input → Result::Error { message_key: "pito.chat.link.follow_up_usage.{detail|list}" }
RSpec.describe "Dispatch matrix — link (recognition, DB mocked)", type: :dispatch do
  VIDEO_STUB_ID = 42
  GAME_STUB_ID  =  7

  let(:video_double) { double("Video", id: VIDEO_STUB_ID, title: "Test Video") }
  let(:game_double)  { double("Game",  id: GAME_STUB_ID,  title: "Test Game") }
  let(:conversation) { double("Conversation") }

  # Build a Link handler from a body string (text AFTER the verb "link").
  # Constructs body_tokens manually — no lexer required.
  def make_handler(body, follow_up: nil)
    tokens = body.strip.split(/\s+/).each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
    msg = Pito::Chat::Message.new(
      tool:        :link,
      body_tokens: tokens,
      kind:        :new_turn,
      raw:         "link #{body}"
    )
    Pito::Chat::Handlers::Link.new(
      message:      msg,
      conversation: conversation,
      follow_up:    follow_up
    )
  end

  def call(body, follow_up: nil)
    make_handler(body, follow_up:).call
  end

  # Default stubs: every lookup returns the type-appropriate double.
  # Individual examples may tighten these to `expect` or override for nil.
  before do
    allow(::Video).to       receive(:find_by).and_return(video_double)
    allow(::Game).to        receive(:find_by).and_return(game_double)
    allow(VideoGameLink).to receive(:find_or_create_by!).and_return(double("VGL"))
  end

  # ── Free-chat: game LEFT + vid RIGHT ───────────────────────────────────────────
  #
  # resolve_sides checks left_noun ∈ GAME_NOUNS and right_noun ∈ VIDEO_NOUNS,
  # then resolves each side via resolve_records.

  describe "free-chat: game noun LEFT, vid noun RIGHT — all noun aliases × both connectors × id forms" do
    {
      # connector = "to", id-form = "#N" — all 8 noun combos (game × videos)
      "game #1 to vid #2"     => "game + vid",
      "game #1 to vids #2"    => "game + vids",
      "game #1 to video #2"   => "game + video",
      "game #1 to videos #2"  => "game + videos",
      "games #1 to vid #2"    => "games + vid",
      "games #1 to vids #2"   => "games + vids",
      "games #1 to video #2"  => "games + video",
      "games #1 to videos #2" => "games + videos",
      # "with" connector
      "game #1 with vid #2"    => "to → with connector",
      "games #1 with video #2" => "games + videos, with connector",
      # Bare integer ids (no # prefix)
      "game 1 to vid 2"        => "bare integer ids",
      "games 1 to videos 2"    => "bare ids, plural nouns",
      "game 1 with vids 2"     => "bare ids, with connector"
    }.each do |body, note|
      it "link #{body.inspect} → Result::Ok :system (#{note})" do
        expect(::Game).to        receive(:find_by).with(id: "1").and_return(game_double)
        expect(::Video).to       receive(:find_by).with(id: "2").and_return(video_double)
        expect(VideoGameLink).to receive(:find_or_create_by!).with(game: game_double, video: video_double)

        result = call(body)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["text"]).to be_a(String).and be_present
      end
    end
  end

  # ── Free-chat: vid LEFT + game RIGHT ───────────────────────────────────────────

  describe "free-chat: vid noun LEFT, game noun RIGHT — all noun aliases × connectors × id forms" do
    {
      "vid #2 to game #1"      => "vid + game",
      "vids #2 to game #1"     => "vids + game",
      "video #2 to game #1"    => "video + game",
      "videos #2 to games #1"  => "videos + games",
      "vid #2 with game #1"    => "vid + game, with connector",
      "video #2 with games #1" => "video + games, with connector",
      # Bare integer ids
      "vid 2 to game 1"        => "bare ids, vid + game",
      "video 2 with game 1"    => "bare ids, with connector"
    }.each do |body, note|
      it "link #{body.inspect} → Result::Ok :system (#{note})" do
        expect(::Video).to       receive(:find_by).with(id: "2").and_return(video_double)
        expect(::Game).to        receive(:find_by).with(id: "1").and_return(game_double)
        expect(VideoGameLink).to receive(:find_or_create_by!).with(game: game_double, video: video_double)

        result = call(body)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end
  end

  # ── Free-chat: multi-target id lists (cross-product linking) ──────────────────
  #
  # resolve_records joins ref_words and splits on /[\s,]+/ to collect all ids.
  # create_links runs games.product(videos) → one find_or_create_by! per pair.

  describe "free-chat: multi-target id lists" do
    let(:video2) { double("Video2", id: VIDEO_STUB_ID + 1, title: "Test Video 2") }
    let(:game2)  { double("Game2",  id: GAME_STUB_ID  + 1, title: "Test Game 2") }

    context "one game, multiple videos (1×N cross-product)" do
      before do
        video_calls = [ video_double, video2 ].cycle
        allow(::Video).to receive(:find_by) { video_calls.next }
      end

      it "game #1 to vid #2,#3 (comma-joined in one token) → 2 links" do
        expect(VideoGameLink).to receive(:find_or_create_by!).twice
        result = call("game #1 to vid #2,#3")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end

      it "game #1 to vid #2 #3 (space-separated ids) → 2 links" do
        expect(VideoGameLink).to receive(:find_or_create_by!).twice
        result = call("game #1 to vid #2 #3")
        expect(result).to be_a(Pito::Chat::Result::Ok)
      end

      it "game 1 to video 2, 3 (space+comma separated) → 2 links" do
        expect(VideoGameLink).to receive(:find_or_create_by!).twice
        result = call("game 1 to video 2, 3")
        expect(result).to be_a(Pito::Chat::Result::Ok)
      end
    end

    context "multiple games, one video (M×1 cross-product)" do
      before do
        game_calls = [ game_double, game2 ].cycle
        allow(::Game).to receive(:find_by) { game_calls.next }
      end

      it "game #1,#2 to vid #3 → 2 links" do
        expect(VideoGameLink).to receive(:find_or_create_by!).twice
        result = call("game #1,#2 to vid #3")
        expect(result).to be_a(Pito::Chat::Result::Ok)
      end

      it "games 1 2 to video #3 (space-separated game ids) → 2 links" do
        expect(VideoGameLink).to receive(:find_or_create_by!).twice
        result = call("games 1 2 to video #3")
        expect(result).to be_a(Pito::Chat::Result::Ok)
      end
    end

    context "vid LEFT, multiple games (N×1 cross-product)" do
      before do
        game_calls = [ game_double, game2 ].cycle
        allow(::Game).to receive(:find_by) { game_calls.next }
      end

      it "vid #2 to game #1,#8 → 2 links" do
        expect(VideoGameLink).to receive(:find_or_create_by!).twice
        result = call("vid #2 to game #1,#8")
        expect(result).to be_a(Pito::Chat::Result::Ok)
      end
    end

    context "multiple games × multiple videos (M×N cross-product)" do
      before do
        game_calls = [ game_double, game2 ].cycle
        video_calls = [ video_double, video2 ].cycle
        allow(::Game).to  receive(:find_by) { game_calls.next }
        allow(::Video).to receive(:find_by) { video_calls.next }
      end

      it "game #1,#2 to vid #3,#4 → 4 links (2×2 cross-product)" do
        expect(VideoGameLink).to receive(:find_or_create_by!).exactly(4).times
        result = call("game #1,#2 to vid #3,#4")
        expect(result).to be_a(Pito::Chat::Result::Ok)
      end
    end
  end

  # ── Free-chat: usage errors — missing connector, no noun, or no ids ────────────
  #
  # usage_hint returns Result::Error with message_key "pito.chat.link.usage".

  describe "free-chat: usage errors → Result::Error (pito.chat.link.usage)" do
    shared_examples "usage error" do |body|
      it "link #{body.inspect} → Result::Error" do
        result = call(body)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.link.usage")
      end
    end

    # Bare verb (empty body) → split returns [] → size < 2
    include_examples "usage error", ""

    # No connector word present → split returns 1 part
    include_examples "usage error", "game #1"
    include_examples "usage error", "vid #2"
    include_examples "usage error", "game #1 vid #2"   # space only, no to/with

    # No noun discriminator → resolve_sides falls to else → usage_hint
    include_examples "usage error", "#1 to #2"
    include_examples "usage error", "1 to 2"

    # Both sides the same noun class
    include_examples "usage error", "game #1 to game #2"   # game → game: unrecognised
    include_examples "usage error", "vid #1 to vid #2"     # vid → vid: unrecognised
    include_examples "usage error", "games #1 to games #2"
    include_examples "usage error", "videos #1 to videos #2"

    # Noun present but no ids → resolve_records returns usage_hint
    include_examples "usage error", "game to vid"          # empty id lists on both sides
    include_examples "usage error", "game #1 to vid"       # empty right-side ids
    include_examples "usage error", "game to video #2"     # empty left-side ids
    include_examples "usage error", "vid to game"
    include_examples "usage error", "video #2 to game"     # empty right-side ids
    include_examples "usage error", "vid to game #1"       # empty left-side ids
  end

  # ── Free-chat: not-found ───────────────────────────────────────────────────────
  #
  # resolve_records calls klass.find_by for each id; nil → not_found_for(klass, id).
  # Result is still Result::Ok (the handler returns a "not found" message event).

  describe "free-chat: not-found → Result::Ok with :system event" do
    context "game not found (Game.find_by → nil)" do
      before { allow(::Game).to receive(:find_by).and_return(nil) }

      {
        "game #99 to vid #2"    => "game LEFT, not found",
        "games #99 to video #2" => "games noun LEFT, not found",
        "vid #2 to game #99"    => "game RIGHT, not found",
        "video #2 to games #99" => "game RIGHT plural noun, not found"
      }.each do |body, note|
        it "link #{body.inspect} → Result::Ok :system event (#{note})" do
          result = call(body)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
        end
      end
    end

    context "video not found (Video.find_by → nil)" do
      before { allow(::Video).to receive(:find_by).and_return(nil) }

      {
        "game #1 to vid #99"    => "video RIGHT, not found",
        "game #1 to videos #99" => "videos noun RIGHT, not found",
        "vid #99 to game #1"    => "video LEFT, not found",
        "videos #99 to game #1" => "videos noun LEFT, not found"
      }.each do |body, note|
        it "link #{body.inspect} → Result::Ok :system event (#{note})" do
          result = call(body)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
        end
      end
    end

    context "multi-id list: first id found, second not found → still creates first link" do
      # resolve_records returns not_found_for on the FIRST missing id, so the
      # short-circuit fires immediately; no link is created for the bad id.
      it "game #1,#99 to vid #2 (second game missing) → Result::Ok :system" do
        game_calls = [ game_double, nil ].cycle
        allow(::Game).to receive(:find_by) { game_calls.next }
        # The first id resolves; resolve_records returns not_found_for on second.
        # The Result::Ok wraps a not-found message (short-circuit, no links created).
        expect(VideoGameLink).not_to receive(:find_or_create_by!)
        result = call("game #1,#99 to vid #2")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end
  end

  # ── Follow-up: video_detail context ───────────────────────────────────────────
  #
  # Payload carries `video_id` (singular) → is_detail = true.
  # Source = that Video; targets = Games parsed from follow_up.rest.
  # video_target? checks reply_target.start_with?("video") → true → source_class=::Video.

  describe "follow-up: video_detail context (source=Video, targets=Games)" do
    let(:source_event) do
      instance_double(
        Event,
        payload: { "video_id" => VIDEO_STUB_ID, "reply_target" => "video_detail" }
      )
    end

    def video_detail_handler(rest)
      ctx = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: rest)
      Pito::Chat::Handlers::Link.new(
        message:      instance_double(Pito::Chat::Message),
        conversation: conversation,
        follow_up:    ctx
      )
    end

    # All `rest` phrasings that should resolve a single game link.
    {
      # Connector present → splits on connector, targets_text = right half
      "to game #7"   => "connector + game noun + #id",
      "to games #7"  => "connector + games noun + #id",
      "to game 7"    => "connector + game noun + bare id",
      "to #7"        => "connector + no noun + #id",
      "to 7"         => "connector + no noun + bare id",
      "with game #7" => "with connector + game noun",
      "with #7"      => "with connector + no noun",
      # No connector → implicit path strips optional connector/noun words
      "game #7"      => "no connector, game noun implicit",
      "#7"           => "no connector, no noun, bare #id",
      "7"            => "no connector, no noun, bare id"
    }.each do |rest, note|
      it "rest=#{rest.inspect} (#{note}) → Result::Ok :system, one link created" do
        expect(::Video).to       receive(:find_by).with(id: VIDEO_STUB_ID).and_return(video_double)
        expect(::Game).to        receive(:find_by).and_return(game_double)
        expect(VideoGameLink).to receive(:find_or_create_by!).with(video: video_double, game: game_double)

        result = video_detail_handler(rest).call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    it "rest='to game #7,#8' (multi-target) → Result::Ok :system, two links" do
      expect(::Video).to       receive(:find_by).with(id: VIDEO_STUB_ID).and_return(video_double)
      allow(::Game).to         receive(:find_by).and_return(game_double)
      expect(VideoGameLink).to receive(:find_or_create_by!).with(video: video_double, game: game_double).twice

      result = video_detail_handler("to game #7,#8").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "rest='to game #7 #8' (multi-target space-separated) → two links" do
      expect(::Video).to       receive(:find_by).with(id: VIDEO_STUB_ID).and_return(video_double)
      allow(::Game).to         receive(:find_by).and_return(game_double)
      expect(VideoGameLink).to receive(:find_or_create_by!).twice

      result = video_detail_handler("to game #7 #8").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    it "roles are correct: VideoGameLink receives video: source, game: target" do
      allow(::Video).to receive(:find_by).and_return(video_double)
      allow(::Game).to  receive(:find_by).and_return(game_double)
      expect(VideoGameLink).to receive(:find_or_create_by!).with(video: video_double, game: game_double)

      video_detail_handler("to game #7").call
    end

    context "source video not found (Video.find_by → nil)" do
      before { allow(::Video).to receive(:find_by).and_return(nil) }

      it "rest='to game #7' → Result::Ok :system (source gone, not-found message)" do
        result = video_detail_handler("to game #7").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    context "target game not found (Game.find_by → nil for the target)" do
      before do
        allow(::Video).to receive(:find_by).and_return(video_double)
        allow(::Game).to  receive(:find_by).and_return(nil)
      end

      it "rest='to game #99' → Result::Ok :system (target gone, not-found message)" do
        result = video_detail_handler("to game #99").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    context "rest has no parseable ids" do
      before { allow(::Video).to receive(:find_by).and_return(video_double) }

      it "rest='to game' (noun only, no id) → Result::Error follow_up_usage.detail" do
        result = video_detail_handler("to game").call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.link.follow_up_usage.detail")
      end

      it "rest='to' (bare connector, no id) → Result::Error follow_up_usage.detail" do
        result = video_detail_handler("to").call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.link.follow_up_usage.detail")
      end

      it "rest='' (empty rest) → Result::Error follow_up_usage.detail" do
        result = video_detail_handler("").call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.link.follow_up_usage.detail")
      end
    end
  end

  # ── Follow-up: game_detail context ────────────────────────────────────────────
  #
  # Payload carries `game_id` (singular) → is_detail = true.
  # Source = that Game; targets = Videos parsed from follow_up.rest.
  # video_target? checks reply_target.start_with?("video") → "game_detail" → false
  # → source_class = ::Game, other_class = ::Video.

  describe "follow-up: game_detail context (source=Game, targets=Videos)" do
    let(:source_event) do
      instance_double(
        Event,
        payload: { "game_id" => GAME_STUB_ID, "reply_target" => "game_detail" }
      )
    end

    def game_detail_handler(rest)
      ctx = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: rest)
      Pito::Chat::Handlers::Link.new(
        message:      instance_double(Pito::Chat::Message),
        conversation: conversation,
        follow_up:    ctx
      )
    end

    {
      "to vid #42"     => "connector + vid noun + #id",
      "to vids #42"    => "connector + vids noun + #id",
      "to video #42"   => "connector + video noun + #id",
      "to videos #42"  => "connector + videos noun + #id",
      "to #42"         => "connector + no noun + #id",
      "to 42"          => "connector + no noun + bare id",
      "with vid #42"   => "with connector + vid noun",
      "with #42"       => "with connector + no noun",
      # No connector → implicit strip path
      "vid #42"        => "no connector, vid noun implicit",
      "#42"            => "no connector, no noun, bare #id",
      "42"             => "no connector, no noun, bare id"
    }.each do |rest, note|
      it "rest=#{rest.inspect} (#{note}) → Result::Ok :system, one link created" do
        expect(::Game).to        receive(:find_by).with(id: GAME_STUB_ID).and_return(game_double)
        expect(::Video).to       receive(:find_by).and_return(video_double)
        expect(VideoGameLink).to receive(:find_or_create_by!).with(video: video_double, game: game_double)

        result = game_detail_handler(rest).call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    it "rest='to vid #42,#43' (multi-target) → Result::Ok :system, two links" do
      expect(::Game).to        receive(:find_by).with(id: GAME_STUB_ID).and_return(game_double)
      allow(::Video).to        receive(:find_by).and_return(video_double)
      expect(VideoGameLink).to receive(:find_or_create_by!).with(video: video_double, game: game_double).twice

      result = game_detail_handler("to vid #42,#43").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    it "roles are correct: VideoGameLink receives video: target, game: source" do
      allow(::Game).to  receive(:find_by).and_return(game_double)
      allow(::Video).to receive(:find_by).and_return(video_double)
      expect(VideoGameLink).to receive(:find_or_create_by!).with(video: video_double, game: game_double)

      game_detail_handler("to video #42").call
    end

    context "source game not found (Game.find_by → nil)" do
      before { allow(::Game).to receive(:find_by).and_return(nil) }

      it "rest='to vid #42' → Result::Ok :system (source gone)" do
        result = game_detail_handler("to vid #42").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    context "target video not found (Video.find_by → nil for the target)" do
      before do
        allow(::Game).to  receive(:find_by).and_return(game_double)
        allow(::Video).to receive(:find_by).and_return(nil)
      end

      it "rest='to vid #99' → Result::Ok :system (target gone)" do
        result = game_detail_handler("to vid #99").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    context "rest has no parseable ids" do
      before { allow(::Game).to receive(:find_by).and_return(game_double) }

      it "rest='to vid' (noun only, no id) → Result::Error follow_up_usage.detail" do
        result = game_detail_handler("to vid").call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.link.follow_up_usage.detail")
      end

      it "rest='to' (bare connector, no id) → Result::Error follow_up_usage.detail" do
        result = game_detail_handler("to").call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.link.follow_up_usage.detail")
      end

      it "rest='' (empty rest) → Result::Error follow_up_usage.detail" do
        result = game_detail_handler("").call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.link.follow_up_usage.detail")
      end
    end
  end

  # ── Follow-up: video_list context ─────────────────────────────────────────────
  #
  # Payload has video_ids array but NO singular video_id → is_detail = false.
  # Source id must appear on the LEFT of the connector; targets on the RIGHT.
  # video_target? → reply_target "video_list" starts with "video" → source=::Video.

  describe "follow-up: video_list context (source id LEFT, targets RIGHT)" do
    let(:source_event) do
      instance_double(
        Event,
        payload: { "reply_target" => "video_list", "video_ids" => [ 1, 2, 3 ] }
        # No "video_id" key → is_detail = false
      )
    end

    def video_list_handler(rest)
      ctx = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: rest)
      Pito::Chat::Handlers::Link.new(
        message:      instance_double(Pito::Chat::Message),
        conversation: conversation,
        follow_up:    ctx
      )
    end

    {
      "17 to game #5"      => "bare source id + to + game noun + #id",
      "17 to games #5"     => "bare source id + to + games noun",
      "17 to #5"           => "bare source id + to + no noun + #id",
      "17 to 5"            => "bare source id + to + bare target id",
      "#17 to game #5"     => "#-prefixed source id + connector",
      "#17 to #5"          => "#-prefixed source id + no noun target",
      "vid 17 to game #5"  => "video noun filler before source id",
      "vids 17 to game #5" => "vids noun filler before source id",
      "vid 17 to #5"       => "video noun filler + no target noun",
      "17 with game #5"    => "with connector",
      "17 with #5"         => "with connector, no target noun"
    }.each do |rest, note|
      it "rest=#{rest.inspect} (#{note}) → Result::Ok :system, link created" do
        expect(::Video).to       receive(:find_by).and_return(video_double)
        expect(::Game).to        receive(:find_by).and_return(game_double)
        expect(VideoGameLink).to receive(:find_or_create_by!).at_least(:once)

        result = video_list_handler(rest).call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    it "rest='17 to game #5,#6' (multi-target) → two links" do
      allow(::Video).to        receive(:find_by).and_return(video_double)
      allow(::Game).to         receive(:find_by).and_return(game_double)
      expect(VideoGameLink).to receive(:find_or_create_by!).twice

      result = video_list_handler("17 to game #5,#6").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    context "missing connector (no to/with in rest) → Result::Error follow_up_usage.list" do
      [ "17", "#17", "vid 17" ].each do |rest|
        it "rest=#{rest.inspect} (no connector) → Result::Error" do
          result = video_list_handler(rest).call
          expect(result).to be_a(Pito::Chat::Result::Error)
          expect(result.message_key).to eq("pito.chat.link.follow_up_usage.list")
        end
      end
    end

    context "non-numeric source id → Result::Error (usage_hint)" do
      it "rest='abc to game #5' → Result::Error" do
        result = video_list_handler("abc to game #5").call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.link.usage")
      end
    end

    context "source video not found" do
      before { allow(::Video).to receive(:find_by).and_return(nil) }

      it "rest='17 to game #5' → Result::Ok :system (source gone)" do
        result = video_list_handler("17 to game #5").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    context "target game not found" do
      before do
        allow(::Video).to receive(:find_by).and_return(video_double)
        allow(::Game).to  receive(:find_by).and_return(nil)
      end

      it "rest='17 to game #99' → Result::Ok :system (target gone)" do
        result = video_list_handler("17 to game #99").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end
  end

  # ── Follow-up: game_list context ──────────────────────────────────────────────
  #
  # Payload has game_ids array but NO singular game_id → is_detail = false.
  # video_target? → reply_target "game_list" starts with "game" (not "video") →
  # source_class = ::Game, other_class = ::Video.

  describe "follow-up: game_list context (source id LEFT, targets RIGHT)" do
    let(:source_event) do
      instance_double(
        Event,
        payload: { "reply_target" => "game_list", "game_ids" => [ 1, 2, 3 ] }
        # No "game_id" key → is_detail = false
      )
    end

    def game_list_handler(rest)
      ctx = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: rest)
      Pito::Chat::Handlers::Link.new(
        message:      instance_double(Pito::Chat::Message),
        conversation: conversation,
        follow_up:    ctx
      )
    end

    {
      "7 to vid #42"       => "bare source id + to + vid noun",
      "7 to vids #42"      => "bare source id + to + vids noun",
      "7 to video #42"     => "bare source id + to + video noun",
      "7 to videos #42"    => "bare source id + to + videos noun",
      "7 to #42"           => "bare source id + to + no noun + #id",
      "7 to 42"            => "bare source id + to + bare target id",
      "#7 to vid #42"      => "#-prefixed source id",
      "#7 to #42"          => "#-prefixed source id + no noun",
      "game 7 to vid #42"  => "game noun filler before source id",
      "games 7 to vid #42" => "games noun filler before source id",
      "7 with vid #42"     => "with connector",
      "7 with #42"         => "with connector, no target noun"
    }.each do |rest, note|
      it "rest=#{rest.inspect} (#{note}) → Result::Ok :system, link created" do
        expect(::Game).to        receive(:find_by).and_return(game_double)
        expect(::Video).to       receive(:find_by).and_return(video_double)
        expect(VideoGameLink).to receive(:find_or_create_by!).at_least(:once)

        result = game_list_handler(rest).call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    it "rest='7 to vid #42,#43' (multi-target) → two links" do
      allow(::Game).to         receive(:find_by).and_return(game_double)
      allow(::Video).to        receive(:find_by).and_return(video_double)
      expect(VideoGameLink).to receive(:find_or_create_by!).twice

      result = game_list_handler("7 to vid #42,#43").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    context "missing connector → Result::Error follow_up_usage.list" do
      [ "7", "#7", "game 7" ].each do |rest|
        it "rest=#{rest.inspect} (no connector) → Result::Error" do
          result = game_list_handler(rest).call
          expect(result).to be_a(Pito::Chat::Result::Error)
          expect(result.message_key).to eq("pito.chat.link.follow_up_usage.list")
        end
      end
    end

    context "non-numeric source id → Result::Error (usage_hint)" do
      it "rest='abc to vid #42' → Result::Error" do
        result = game_list_handler("abc to vid #42").call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.link.usage")
      end
    end

    context "source game not found" do
      before { allow(::Game).to receive(:find_by).and_return(nil) }

      it "rest='7 to vid #42' → Result::Ok :system (source gone)" do
        result = game_list_handler("7 to vid #42").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    context "target video not found" do
      before do
        allow(::Game).to  receive(:find_by).and_return(game_double)
        allow(::Video).to receive(:find_by).and_return(nil)
      end

      it "rest='7 to vid #99' → Result::Ok :system (target gone)" do
        result = game_list_handler("7 to vid #99").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end
  end
end
