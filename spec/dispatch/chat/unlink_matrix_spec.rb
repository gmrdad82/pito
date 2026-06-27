# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `unlink` (recognition only, DB mocked) ────────────────────
#
# RULE: every kwarg combination recognised — no exception. We test what the
# handler UNDERSTANDS, not DB state. All DB lookups and write operations are
# stubbed; records "exist" unless the example says otherwise.
#
# Subjects:
#   app/services/pito/chat/handlers/unlink.rb
#   app/services/pito/chat/handlers/multi_link_helpers.rb (follow-up branch)
#
# Free-chat (Handler#call non-follow_up branch):
#   body_tokens joined → split on \bfrom\b → left / right halves.
#   Each half: noun discriminator (game/games | vid/vids/video/videos) + ONE id.
#   IDs: plain or #-prefixed numeric.
#   IMPORTANT: multi-id is NOT supported in free-chat — resolve_game /
#   resolve_video join ref_words and require a single /\A\d+\z/ match.
#
# Follow-up — detail card (singular video_id / game_id in payload):
#   Source implied by the card entity; targets parsed from follow_up.rest.
#   Connector word = "from". Multi-target supported.
#
# Follow-up — list card (video_ids / game_ids in payload):
#   Source id on the LEFT of "from"; targets on the RIGHT.
#
# Result shapes:
#   Link found + destroyed   → Result::Ok  { events: [{ kind: :system, payload: { "text" => ... } }] }
#   Link absent (idempotent) → Result::Ok  { events: [{ kind: :system, ... }] }  ("not_linked" message)
#   Record not found         → Result::Ok  { events: [{ kind: :system, ... }] }  ("not_found" message)
#   Bad input (free-chat)    → Result::Error { message_key: "pito.chat.unlink.usage" }
#   Follow-up bad input      → Result::Error { message_key: "pito.chat.unlink.follow_up_usage.{detail|list}" }
#
# Follow-up contexts that declare :unlink (verified via FollowUp::Registry):
#   video_detail, game_detail, video_list, game_list — all four.
RSpec.describe "Dispatch matrix — unlink (recognition, DB mocked)", type: :dispatch do
  UNLINK_VIDEO_STUB_ID = 42
  UNLINK_GAME_STUB_ID  =  7

  let(:video_double) { double("Video", id: UNLINK_VIDEO_STUB_ID, title: "Test Video") }
  let(:game_double)  { double("Game",  id: UNLINK_GAME_STUB_ID,  title: "Test Game") }
  # Free-chat destroy_link calls link.destroy! (bang).
  # Follow-up multi_link_helpers calls link&.destroy (no bang).
  let(:link_double)  { double("VGL", destroy!: true, destroy: true) }
  let(:conversation) { double("Conversation") }

  # Build an Unlink handler from a body string (text AFTER the verb "unlink").
  def make_handler(body, follow_up: nil)
    tokens = body.strip.split(/\s+/).each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
    msg = Pito::Chat::Message.new(
      verb:        :unlink,
      body_tokens: tokens,
      kind:        :new_turn,
      raw:         "unlink #{body}"
    )
    Pito::Chat::Handlers::Unlink.new(
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
    allow(VideoGameLink).to receive(:find_by).and_return(link_double)
  end

  # ── Free-chat: game LEFT + vid RIGHT ───────────────────────────────────────────
  #
  # resolve_sides: left_noun ∈ GAME_NOUNS, right_noun ∈ VIDEO_NOUNS
  # → resolve_game(left_words.drop(1)), resolve_video(right_words.drop(1))
  # → destroy_link(game, video) → VGL.find_by + link.destroy!

  describe "free-chat: game noun LEFT, vid noun RIGHT — all noun aliases × from connector × id forms" do
    {
      # #N id form — all 8 noun combos (game/games × vid/vids/video/videos)
      "game #1 from vid #2"     => "game + vid",
      "game #1 from vids #2"    => "game + vids",
      "game #1 from video #2"   => "game + video",
      "game #1 from videos #2"  => "game + videos",
      "games #1 from vid #2"    => "games + vid",
      "games #1 from vids #2"   => "games + vids",
      "games #1 from video #2"  => "games + video",
      "games #1 from videos #2" => "games + videos",
      # Bare integer ids (no # prefix)
      "game 1 from vid 2"       => "bare integer ids",
      "games 1 from videos 2"   => "bare ids, plural nouns"
    }.each do |body, note|
      it "unlink #{body.inspect} → Result::Ok :system, link destroyed (#{note})" do
        expect(::Game).to        receive(:find_by).with(id: "1").and_return(game_double)
        expect(::Video).to       receive(:find_by).with(id: "2").and_return(video_double)
        expect(VideoGameLink).to receive(:find_by).with(video: video_double, game: game_double)
                                                  .and_return(link_double)
        expect(link_double).to receive(:destroy!)

        result = call(body)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["text"]).to be_a(String).and be_present
      end
    end
  end

  # ── Free-chat: vid LEFT + game RIGHT ───────────────────────────────────────────
  #
  # resolve_sides: left_noun ∈ VIDEO_NOUNS, right_noun ∈ GAME_NOUNS
  # → resolve_video(left_words.drop(1)), resolve_game(right_words.drop(1))
  # Roles are the same for destroy_link: destroy_link(game, video).

  describe "free-chat: vid noun LEFT, game noun RIGHT — all noun aliases × from connector × id forms" do
    {
      "vid #2 from game #1"     => "vid + game",
      "vids #2 from game #1"    => "vids + game",
      "video #2 from game #1"   => "video + game",
      "videos #2 from games #1" => "videos + games",
      # Bare integer ids
      "vid 2 from game 1"       => "bare ids, vid + game",
      "video 2 from games 1"    => "bare ids, video + games"
    }.each do |body, note|
      it "unlink #{body.inspect} → Result::Ok :system, link destroyed (#{note})" do
        expect(::Video).to       receive(:find_by).with(id: "2").and_return(video_double)
        expect(::Game).to        receive(:find_by).with(id: "1").and_return(game_double)
        expect(VideoGameLink).to receive(:find_by).with(video: video_double, game: game_double)
                                                  .and_return(link_double)
        expect(link_double).to receive(:destroy!)

        result = call(body)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end
  end

  # ── Free-chat: already-not-linked (VGL.find_by → nil) ─────────────────────────
  #
  # destroy_link: VGL.find_by → nil → emits "not_linked" system event.
  # Idempotent: still Result::Ok, no exception raised, no destroy! called.

  describe "free-chat: already not linked (VideoGameLink.find_by → nil)" do
    before { allow(VideoGameLink).to receive(:find_by).and_return(nil) }

    it "game #1 from vid #2 → Result::Ok :system (not_linked message)" do
      result = call("game #1 from vid #2")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["text"]).to be_a(String).and be_present
    end

    it "vid #2 from game #1 → Result::Ok :system (not_linked message, reversed noun order)" do
      result = call("vid #2 from game #1")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "does NOT call destroy! when the link is already absent" do
      expect(link_double).not_to receive(:destroy!)
      call("game #1 from vid #2")
    end
  end

  # ── Free-chat: not-found ───────────────────────────────────────────────────────
  #
  # resolve_game / resolve_video: find_by → nil → not_found_game / not_found_video.
  # Still Result::Ok (the handler returns a "not found" message event).

  describe "free-chat: record not found → Result::Ok with :system event" do
    context "game not found (Game.find_by → nil)" do
      before { allow(::Game).to receive(:find_by).and_return(nil) }

      {
        "game #99 from vid #2"    => "game LEFT, not found",
        "games #99 from video #2" => "games noun LEFT, not found",
        "vid #2 from game #99"    => "game RIGHT, not found",
        "video #2 from games #99" => "game RIGHT plural noun, not found"
      }.each do |body, note|
        it "unlink #{body.inspect} → Result::Ok :system (#{note})" do
          result = call(body)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
        end
      end
    end

    context "video not found (Video.find_by → nil)" do
      before { allow(::Video).to receive(:find_by).and_return(nil) }

      {
        "game #1 from vid #99"    => "video RIGHT, not found",
        "game #1 from videos #99" => "videos noun RIGHT, not found",
        "vid #99 from game #1"    => "video LEFT, not found",
        "videos #99 from game #1" => "videos noun LEFT, not found"
      }.each do |body, note|
        it "unlink #{body.inspect} → Result::Ok :system (#{note})" do
          result = call(body)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
        end
      end
    end
  end

  # ── Free-chat: usage errors — missing connector, no noun, no ids ──────────────
  #
  # usage_hint → Result::Error "pito.chat.unlink.usage"

  describe "free-chat: usage errors → Result::Error (pito.chat.unlink.usage)" do
    shared_examples "usage error" do |body|
      it "unlink #{body.inspect} → Result::Error" do
        result = call(body)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.unlink.usage")
      end
    end

    # Bare verb (empty body) → body_tokens empty → raw="" → split has 1 part < 2
    include_examples "usage error", ""

    # No 'from' connector → parts.size == 1 → usage_hint
    include_examples "usage error", "game #1"
    include_examples "usage error", "vid #2"
    include_examples "usage error", "game #1 vid #2"    # space only, no from keyword

    # No noun discriminator on either side → resolve_sides falls to else → usage_hint
    include_examples "usage error", "#1 from #2"
    include_examples "usage error", "1 from 2"

    # Both sides same noun class
    include_examples "usage error", "game #1 from game #2"
    include_examples "usage error", "vid #1 from vid #2"
    include_examples "usage error", "games #1 from games #2"
    include_examples "usage error", "videos #1 from videos #2"

    # Noun present but blank ref → resolve_game / resolve_video returns usage_hint
    include_examples "usage error", "game from vid"      # blank ids on both sides
    include_examples "usage error", "game #1 from vid"   # blank right-side id
    include_examples "usage error", "game from video #2" # blank left-side id
    include_examples "usage error", "vid from game"
    include_examples "usage error", "video #2 from game" # blank right-side id
    include_examples "usage error", "vid from game #1"   # blank left-side id
  end

  # ── Free-chat: multi-id rejected (single id only in free-chat) ────────────────
  #
  # resolve_game / resolve_video: joins ref_words → id.match?(/\A\d+\z/) fails
  # on comma or space-separated multi-ids → usage_hint.
  # This is a deliberate unlink limitation vs link (which uses resolve_records).

  describe "free-chat: multi-id → Result::Error (usage — not supported in free-chat)" do
    shared_examples "multi-id usage error" do |body|
      it "unlink #{body.inspect} → Result::Error (multi-id rejected)" do
        result = call(body)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.unlink.usage")
      end
    end

    # comma-joined ids
    include_examples "multi-id usage error", "game #1,#2 from vid #3"
    include_examples "multi-id usage error", "game #1 from vid #2,#3"
    # space-separated ids
    include_examples "multi-id usage error", "game #1 #2 from vid #3"
    include_examples "multi-id usage error", "game #1 from vid #2 #3"
  end

  # ── Follow-up: video_detail context ───────────────────────────────────────────
  #
  # Payload carries video_id → is_detail = true.
  # Source = that Video; targets = Games parsed from follow_up.rest (after "from").
  # video_target?: reply_target "video_detail".start_with?("video") → true
  # → source_class = ::Video, other_class = ::Game.
  #
  # Connector: "from" only.
  # Multi-target supported (follow_up_multi iterates target_ids).
  # VGL.find_by + link&.destroy (no-bang) per target — idempotent when link absent.

  describe "follow-up: video_detail context (source=Video, targets=Games)" do
    let(:source_event) do
      instance_double(
        Event,
        payload: { "video_id" => UNLINK_VIDEO_STUB_ID, "reply_target" => "video_detail" }
      )
    end

    def video_detail_handler(rest)
      ctx = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: rest)
      Pito::Chat::Handlers::Unlink.new(
        message:      instance_double(Pito::Chat::Message),
        conversation: conversation,
        follow_up:    ctx
      )
    end

    # All `rest` phrasings that should resolve a single-target unlink.
    {
      # Connector present → parts[1] = targets_text
      "from game #7"  => "connector + game noun + #id",
      "from games #7" => "connector + games noun + #id",
      "from game 7"   => "connector + game noun + bare id",
      "from #7"       => "connector + no noun + #id",
      "from 7"        => "connector + no noun + bare id",
      # No connector → implicit strip of leading noun/connector word
      "game #7"       => "no connector, game noun implicit",
      "#7"            => "no connector, no noun, bare #id",
      "7"             => "no connector, no noun, bare id"
    }.each do |rest, note|
      it "rest=#{rest.inspect} (#{note}) → Result::Ok :system, link destroyed" do
        expect(::Video).to receive(:find_by).with(id: UNLINK_VIDEO_STUB_ID).and_return(video_double)
        expect(::Game).to  receive(:find_by).and_return(game_double)
        allow(VideoGameLink).to receive(:find_by).and_return(link_double)
        expect(link_double).to receive(:destroy)

        result = video_detail_handler(rest).call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    it "rest='from game #7,#8' (multi-target comma-separated) → two unlinks" do
      expect(::Video).to receive(:find_by).with(id: UNLINK_VIDEO_STUB_ID).and_return(video_double)
      allow(::Game).to   receive(:find_by).and_return(game_double)
      allow(VideoGameLink).to receive(:find_by).and_return(link_double)
      expect(link_double).to receive(:destroy).twice

      result = video_detail_handler("from game #7,#8").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "rest='from game #7 #8' (multi-target space-separated) → two unlinks" do
      expect(::Video).to receive(:find_by).with(id: UNLINK_VIDEO_STUB_ID).and_return(video_double)
      allow(::Game).to   receive(:find_by).and_return(game_double)
      allow(VideoGameLink).to receive(:find_by).and_return(link_double)
      expect(link_double).to receive(:destroy).twice

      result = video_detail_handler("from game #7 #8").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    it "already not linked (VGL.find_by → nil) → Result::Ok :system (idempotent, link&.destroy no-op)" do
      allow(::Video).to receive(:find_by).and_return(video_double)
      allow(::Game).to  receive(:find_by).and_return(game_double)
      allow(VideoGameLink).to receive(:find_by).and_return(nil)

      result = video_detail_handler("from game #7").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
    end

    context "source video not found (Video.find_by → nil)" do
      before { allow(::Video).to receive(:find_by).and_return(nil) }

      it "rest='from game #7' → Result::Ok :system (source gone, not-found message)" do
        result = video_detail_handler("from game #7").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    context "target game not found (Game.find_by → nil)" do
      before do
        allow(::Video).to receive(:find_by).and_return(video_double)
        allow(::Game).to  receive(:find_by).and_return(nil)
      end

      it "rest='from game #99' → Result::Ok :system (target gone, not-found message)" do
        result = video_detail_handler("from game #99").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    context "rest has no parseable ids" do
      before { allow(::Video).to receive(:find_by).and_return(video_double) }

      it "rest='from game' (noun only, no id) → Result::Error follow_up_usage.detail" do
        result = video_detail_handler("from game").call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.unlink.follow_up_usage.detail")
      end

      it "rest='from' (bare connector, no id) → Result::Error follow_up_usage.detail" do
        result = video_detail_handler("from").call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.unlink.follow_up_usage.detail")
      end

      it "rest='' (empty rest) → Result::Error follow_up_usage.detail" do
        result = video_detail_handler("").call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.unlink.follow_up_usage.detail")
      end
    end
  end

  # ── Follow-up: game_detail context ────────────────────────────────────────────
  #
  # Payload carries game_id → is_detail = true.
  # Source = that Game; targets = Videos parsed from follow_up.rest.
  # video_target?: "game_detail".start_with?("video") → false
  # → source_class = ::Game, other_class = ::Video.

  describe "follow-up: game_detail context (source=Game, targets=Videos)" do
    let(:source_event) do
      instance_double(
        Event,
        payload: { "game_id" => UNLINK_GAME_STUB_ID, "reply_target" => "game_detail" }
      )
    end

    def game_detail_handler(rest)
      ctx = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: rest)
      Pito::Chat::Handlers::Unlink.new(
        message:      instance_double(Pito::Chat::Message),
        conversation: conversation,
        follow_up:    ctx
      )
    end

    {
      "from vid #42"    => "connector + vid noun + #id",
      "from vids #42"   => "connector + vids noun + #id",
      "from video #42"  => "connector + video noun + #id",
      "from videos #42" => "connector + videos noun + #id",
      "from #42"        => "connector + no noun + #id",
      "from 42"         => "connector + no noun + bare id",
      # No connector → implicit strip path
      "vid #42"         => "no connector, vid noun implicit",
      "#42"             => "no connector, no noun, bare #id",
      "42"              => "no connector, no noun, bare id"
    }.each do |rest, note|
      it "rest=#{rest.inspect} (#{note}) → Result::Ok :system, link destroyed" do
        expect(::Game).to  receive(:find_by).with(id: UNLINK_GAME_STUB_ID).and_return(game_double)
        expect(::Video).to receive(:find_by).and_return(video_double)
        allow(VideoGameLink).to receive(:find_by).and_return(link_double)
        expect(link_double).to receive(:destroy)

        result = game_detail_handler(rest).call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    it "rest='from vid #42,#43' (multi-target) → two unlinks" do
      expect(::Game).to  receive(:find_by).with(id: UNLINK_GAME_STUB_ID).and_return(game_double)
      allow(::Video).to  receive(:find_by).and_return(video_double)
      allow(VideoGameLink).to receive(:find_by).and_return(link_double)
      expect(link_double).to receive(:destroy).twice

      result = game_detail_handler("from vid #42,#43").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    it "rest='from vid #42 #43' (multi-target space-separated) → two unlinks" do
      expect(::Game).to  receive(:find_by).with(id: UNLINK_GAME_STUB_ID).and_return(game_double)
      allow(::Video).to  receive(:find_by).and_return(video_double)
      allow(VideoGameLink).to receive(:find_by).and_return(link_double)
      expect(link_double).to receive(:destroy).twice

      result = game_detail_handler("from vid #42 #43").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    it "already not linked (VGL.find_by → nil) → Result::Ok :system (idempotent)" do
      allow(::Game).to  receive(:find_by).and_return(game_double)
      allow(::Video).to receive(:find_by).and_return(video_double)
      allow(VideoGameLink).to receive(:find_by).and_return(nil)

      result = game_detail_handler("from vid #42").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
    end

    context "source game not found (Game.find_by → nil)" do
      before { allow(::Game).to receive(:find_by).and_return(nil) }

      it "rest='from vid #42' → Result::Ok :system (source gone)" do
        result = game_detail_handler("from vid #42").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    context "target video not found (Video.find_by → nil)" do
      before do
        allow(::Game).to  receive(:find_by).and_return(game_double)
        allow(::Video).to receive(:find_by).and_return(nil)
      end

      it "rest='from vid #99' → Result::Ok :system (target gone)" do
        result = game_detail_handler("from vid #99").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    context "rest has no parseable ids" do
      before { allow(::Game).to receive(:find_by).and_return(game_double) }

      it "rest='from vid' (noun only, no id) → Result::Error follow_up_usage.detail" do
        result = game_detail_handler("from vid").call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.unlink.follow_up_usage.detail")
      end

      it "rest='from' (bare connector, no id) → Result::Error follow_up_usage.detail" do
        result = game_detail_handler("from").call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.unlink.follow_up_usage.detail")
      end

      it "rest='' (empty rest) → Result::Error follow_up_usage.detail" do
        result = game_detail_handler("").call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.unlink.follow_up_usage.detail")
      end
    end
  end

  # ── Follow-up: video_list context ─────────────────────────────────────────────
  #
  # Payload has video_ids array, no singular video_id → is_detail = false.
  # Source id must appear on the LEFT of "from"; targets on the RIGHT.
  # video_target?: "video_list".start_with?("video") → true → source=::Video.
  # source_nouns = VIDEO_NOUNS; leading noun filler stripped from LEFT.

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
      Pito::Chat::Handlers::Unlink.new(
        message:      instance_double(Pito::Chat::Message),
        conversation: conversation,
        follow_up:    ctx
      )
    end

    {
      "17 from game #5"      => "bare source id + from + game noun + #id",
      "17 from games #5"     => "bare source id + from + games noun",
      "17 from #5"           => "bare source id + from + no noun + #id",
      "17 from 5"            => "bare source id + from + bare target id",
      "#17 from game #5"     => "#-prefixed source id + connector",
      "#17 from #5"          => "#-prefixed source id + no noun target",
      "vid 17 from game #5"  => "video noun filler before source id",
      "vids 17 from game #5" => "vids noun filler before source id",
      "video 17 from #5"     => "video noun filler + no target noun",
      "videos 17 from #5"    => "videos noun filler + no target noun"
    }.each do |rest, note|
      it "rest=#{rest.inspect} (#{note}) → Result::Ok :system, link destroyed" do
        expect(::Video).to receive(:find_by).and_return(video_double)
        expect(::Game).to  receive(:find_by).and_return(game_double)
        allow(VideoGameLink).to receive(:find_by).and_return(link_double)
        expect(link_double).to receive(:destroy).at_least(:once)

        result = video_list_handler(rest).call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    it "rest='17 from game #5,#6' (multi-target) → two unlinks" do
      allow(::Video).to receive(:find_by).and_return(video_double)
      allow(::Game).to  receive(:find_by).and_return(game_double)
      allow(VideoGameLink).to receive(:find_by).and_return(link_double)
      expect(link_double).to receive(:destroy).twice

      result = video_list_handler("17 from game #5,#6").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    it "already not linked (VGL.find_by → nil) → Result::Ok :system (idempotent)" do
      allow(::Video).to receive(:find_by).and_return(video_double)
      allow(::Game).to  receive(:find_by).and_return(game_double)
      allow(VideoGameLink).to receive(:find_by).and_return(nil)

      result = video_list_handler("17 from game #5").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
    end

    context "missing connector (no 'from' in rest) → Result::Error follow_up_usage.list" do
      [ "17", "#17", "vid 17" ].each do |rest|
        it "rest=#{rest.inspect} (no connector) → Result::Error" do
          result = video_list_handler(rest).call
          expect(result).to be_a(Pito::Chat::Result::Error)
          expect(result.message_key).to eq("pito.chat.unlink.follow_up_usage.list")
        end
      end
    end

    context "non-numeric source id → Result::Error (usage_hint falls back to unlink.usage)" do
      it "rest='abc from game #5' → Result::Error" do
        result = video_list_handler("abc from game #5").call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.unlink.usage")
      end
    end

    context "source video not found (Video.find_by → nil)" do
      before { allow(::Video).to receive(:find_by).and_return(nil) }

      it "rest='17 from game #5' → Result::Ok :system (source gone)" do
        result = video_list_handler("17 from game #5").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    context "target game not found (Game.find_by → nil)" do
      before do
        allow(::Video).to receive(:find_by).and_return(video_double)
        allow(::Game).to  receive(:find_by).and_return(nil)
      end

      it "rest='17 from game #99' → Result::Ok :system (target gone)" do
        result = video_list_handler("17 from game #99").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end
  end

  # ── Follow-up: game_list context ──────────────────────────────────────────────
  #
  # Payload has game_ids array, no singular game_id → is_detail = false.
  # video_target?: "game_list".start_with?("video") → false
  # → source_class = ::Game, other_class = ::Video.
  # source_nouns = GAME_NOUNS; leading noun filler stripped from LEFT.

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
      Pito::Chat::Handlers::Unlink.new(
        message:      instance_double(Pito::Chat::Message),
        conversation: conversation,
        follow_up:    ctx
      )
    end

    {
      "7 from vid #42"       => "bare source id + from + vid noun",
      "7 from vids #42"      => "bare source id + from + vids noun",
      "7 from video #42"     => "bare source id + from + video noun",
      "7 from videos #42"    => "bare source id + from + videos noun",
      "7 from #42"           => "bare source id + from + no noun + #id",
      "7 from 42"            => "bare source id + from + bare target id",
      "#7 from vid #42"      => "#-prefixed source id",
      "#7 from #42"          => "#-prefixed source id + no noun",
      "game 7 from vid #42"  => "game noun filler before source id",
      "games 7 from vid #42" => "games noun filler before source id"
    }.each do |rest, note|
      it "rest=#{rest.inspect} (#{note}) → Result::Ok :system, link destroyed" do
        expect(::Game).to  receive(:find_by).and_return(game_double)
        expect(::Video).to receive(:find_by).and_return(video_double)
        allow(VideoGameLink).to receive(:find_by).and_return(link_double)
        expect(link_double).to receive(:destroy).at_least(:once)

        result = game_list_handler(rest).call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    it "rest='7 from vid #42,#43' (multi-target) → two unlinks" do
      allow(::Game).to  receive(:find_by).and_return(game_double)
      allow(::Video).to receive(:find_by).and_return(video_double)
      allow(VideoGameLink).to receive(:find_by).and_return(link_double)
      expect(link_double).to receive(:destroy).twice

      result = game_list_handler("7 from vid #42,#43").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    it "rest='7 from vid #42 #43' (multi-target space-separated) → two unlinks" do
      allow(::Game).to  receive(:find_by).and_return(game_double)
      allow(::Video).to receive(:find_by).and_return(video_double)
      allow(VideoGameLink).to receive(:find_by).and_return(link_double)
      expect(link_double).to receive(:destroy).twice

      result = game_list_handler("7 from vid #42 #43").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    it "already not linked (VGL.find_by → nil) → Result::Ok :system (idempotent)" do
      allow(::Game).to  receive(:find_by).and_return(game_double)
      allow(::Video).to receive(:find_by).and_return(video_double)
      allow(VideoGameLink).to receive(:find_by).and_return(nil)

      result = game_list_handler("7 from vid #42").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
    end

    context "missing connector (no 'from' in rest) → Result::Error follow_up_usage.list" do
      [ "7", "#7", "game 7" ].each do |rest|
        it "rest=#{rest.inspect} (no connector) → Result::Error" do
          result = game_list_handler(rest).call
          expect(result).to be_a(Pito::Chat::Result::Error)
          expect(result.message_key).to eq("pito.chat.unlink.follow_up_usage.list")
        end
      end
    end

    context "non-numeric source id → Result::Error (usage_hint falls back to unlink.usage)" do
      it "rest='abc from vid #42' → Result::Error" do
        result = game_list_handler("abc from vid #42").call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.unlink.usage")
      end
    end

    context "source game not found (Game.find_by → nil)" do
      before { allow(::Game).to receive(:find_by).and_return(nil) }

      it "rest='7 from vid #42' → Result::Ok :system (source gone)" do
        result = game_list_handler("7 from vid #42").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    context "target video not found (Video.find_by → nil)" do
      before do
        allow(::Game).to  receive(:find_by).and_return(game_double)
        allow(::Video).to receive(:find_by).and_return(nil)
      end

      it "rest='7 from vid #99' → Result::Ok :system (target gone)" do
        result = game_list_handler("7 from vid #99").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end
  end
end
