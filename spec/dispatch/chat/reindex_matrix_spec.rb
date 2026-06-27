# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `reindex` (recognition only, DB mocked) ──────────────────
#
# RULE: every kwarg combination recognized — no exception. Tests what the handler
# UNDERSTANDS from a raw input, not data persistence. All DB lookups are stubbed
# so the handler resolves records without touching the database.
#
# Subject:  Pito::Chat::Handlers::Reindex (app/services/pito/chat/handlers/reindex.rb)
#           lib/pito/chat/target_resolution.rb (id_only_resolution!)
# Resolver: id_only_resolution! — title (ILIKE) lookups intentionally disabled.
#
# Branches (video_target? in lib/pito/chat/target_resolution.rb):
#   video branch — any body token in VIDEO_NOUN_FILLERS: vid / vids / video / videos
#   game branch  — default (no video noun present, OR follow-up reply_target !~ /\Avideo/)
#
# Confirmation payload keys emitted on success (MessageBuilder::*::ReindexConfirmation):
#   game:  { "command" => "game_reindex",  "game_id"  => id, "game_title"  => title }
#   video: { "command" => "video_reindex", "video_id" => id, "video_title" => title }
#
# Follow-up paths — only targets that declare :reindex in their actions list:
#   video_detail — declares "reindex" (Pito::FollowUp::Handlers::VideoDetail)
#   game_detail  — declares "reindex" (Pito::FollowUp::Handlers::GameDetail)

RSpec.describe "Dispatch matrix — reindex (recognition, DB mocked)", type: :dispatch do
  VIDEO_REINDEX_STUB_ID = 42
  GAME_REINDEX_STUB_ID  =  7

  let(:video_double) { double("Video", id: VIDEO_REINDEX_STUB_ID, title: "Stub Video") }
  let(:game_double)  { double("Game",  id: GAME_REINDEX_STUB_ID,  title: "Stub Game") }

  # Conversation double — only required to thread through make_followupable! inside
  # the ReindexConfirmation builders, which mint a reply handle via HandleGenerator.
  let(:conversation) { double("Conversation") }

  # Build and call a Reindex handler from a raw string.
  # `verb` is always :reindex; raw is passed verbatim so extract_ref_from can strip it.
  def make_handler(raw, follow_up: nil)
    parts       = raw.strip.split(/\s+/)
    body_words  = parts[1..]
    body_tokens = body_words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: true)
    end
    msg = Pito::Chat::Message.new(
      verb:        :reindex,
      body_tokens: body_tokens,
      kind:        :new_turn,
      raw:         raw
    )
    Pito::Chat::Handlers::Reindex.new(
      message:      msg,
      conversation: conversation,
      follow_up:    follow_up
    )
  end

  def call(raw, follow_up: nil)
    make_handler(raw, follow_up:).call
  end

  # Default stubs: every find_by succeeds, returning the matching type double.
  # HandleGenerator is stubbed to avoid the conversation.events DB query inside
  # Pito::FollowUp.make_followupable! (called by both ReindexConfirmation builders).
  before do
    allow(Pito::HandleGenerator).to receive(:call).and_return("mock-rfx1")
    allow(::Video).to receive(:find_by).and_return(video_double)
    allow(::Game).to receive(:find_by).and_return(game_double)
  end

  # ── Video noun — all four fillers × #id + bare id ────────────────────────────
  #
  # video_target? returns true when any body token value matches vid/vids/video/videos.

  describe "video noun — all four noun fillers, both id forms" do
    {
      # singular vid
      "reindex vid #5"    => VIDEO_REINDEX_STUB_ID,
      "reindex vid 5"     => VIDEO_REINDEX_STUB_ID,
      # plural vids
      "reindex vids #5"   => VIDEO_REINDEX_STUB_ID,
      "reindex vids 5"    => VIDEO_REINDEX_STUB_ID,
      # singular video
      "reindex video #5"  => VIDEO_REINDEX_STUB_ID,
      "reindex video 5"   => VIDEO_REINDEX_STUB_ID,
      # plural videos
      "reindex videos #5" => VIDEO_REINDEX_STUB_ID,
      "reindex videos 5"  => VIDEO_REINDEX_STUB_ID
    }.each do |raw, expected_id|
      it "#{raw.inspect} → :confirmation, command: 'video_reindex', video_id: #{expected_id}" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("video_reindex")
        expect(event[:payload]["video_id"]).to eq(expected_id)
      end
    end
  end

  # ── Game noun — both fillers × #id + bare id ──────────────────────────────────
  #
  # video_target? is false → game branch.

  describe "game noun — both noun fillers, both id forms" do
    {
      # singular game
      "reindex game #5"  => GAME_REINDEX_STUB_ID,
      "reindex game 5"   => GAME_REINDEX_STUB_ID,
      # plural games
      "reindex games #5" => GAME_REINDEX_STUB_ID,
      "reindex games 5"  => GAME_REINDEX_STUB_ID
    }.each do |raw, expected_id|
      it "#{raw.inspect} → :confirmation, command: 'game_reindex', game_id: #{expected_id}" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("game_reindex")
        expect(event[:payload]["game_id"]).to eq(expected_id)
      end
    end
  end

  # ── No noun → game branch (default) ───────────────────────────────────────────
  #
  # When no noun filler appears in body_tokens, video_target? is false → game branch.
  # The ref (#5 / 5) is extracted from raw (verb stripped first) and resolved by id.

  describe "no noun → defaults to game branch" do
    {
      "reindex #5" => GAME_REINDEX_STUB_ID,
      "reindex 5"  => GAME_REINDEX_STUB_ID
    }.each do |raw, expected_id|
      it "#{raw.inspect} → :confirmation, command: 'game_reindex' (no noun = game default)" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("game_reindex")
        expect(event[:payload]["game_id"]).to eq(expected_id)
      end
    end
  end

  # ── Bare verb (no ref, no noun) → Result::Error (needs_ref) ───────────────────
  #
  # extract_ref_from strips the verb token, leaving ""; blank ref → :needs_ref.
  # Both go to the game branch (default). Result::Error with the reindex needs_ref key.

  describe "bare verb, no ref → Result::Error (needs_ref)" do
    [ "reindex", "reindex   " ].each do |raw|
      it "#{raw.inspect} → Result::Error (message_key: pito.chat.reindex.needs_ref)" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.reindex.needs_ref")
      end
    end
  end

  # ── Noun only (no id) → Result::Error (needs_ref) ─────────────────────────────
  #
  # After stripping the verb and noun filler, ref is blank → :needs_ref.
  # Video nouns → video branch → needs_ref; game nouns → game branch → needs_ref.
  # Both use the same message_key "pito.chat.reindex.needs_ref".

  describe "noun only (no id) → Result::Error (needs_ref)" do
    [
      "reindex vid",
      "reindex vids",
      "reindex video",
      "reindex videos",
      "reindex game",
      "reindex games"
    ].each do |raw|
      it "#{raw.inspect} → Result::Error (no id supplied)" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.reindex.needs_ref")
      end
    end
  end

  # ── id-only: non-numeric title ref → not-found (no ILIKE fallback) ────────────
  #
  # id_only_resolution! skips title lookup entirely — a non-numeric ref returns nil
  # without calling find_by at all. The handler then falls to the not-found path.

  describe "non-numeric (title) ref → not-found (id-only resolution)" do
    it "reindex video a-title → :system (video not found, no command)" do
      result = call("reindex video a-title")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["command"]).to be_nil
    end

    it "reindex game a-title → :system (game not found, no command)" do
      result = call("reindex game a-title")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["command"]).to be_nil
    end

    it "reindex a-title (no noun) → :system (game branch, not found)" do
      result = call("reindex a-title")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["command"]).to be_nil
    end
  end

  # ── Not-found — find_by returns nil → :system event, no command ───────────────
  #
  # Numeric id that doesn't exist: find_by(id:) → nil → not-found path.
  # id-only: a title ref also yields nil immediately (no ILIKE), see section above.

  describe "not-found → :system event" do
    context "video branch: Video.find_by returns nil" do
      before { allow(::Video).to receive(:find_by).and_return(nil) }

      {
        "reindex vid #99"    => nil,
        "reindex vid 99"     => nil,
        "reindex vids #99"   => nil,
        "reindex vids 99"    => nil,
        "reindex video #99"  => nil,
        "reindex video 99"   => nil,
        "reindex videos #99" => nil,
        "reindex videos 99"  => nil
      }.each do |raw, _|
        it "#{raw.inspect} → :system event (video not found, no command key)" do
          result = call(raw)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
          expect(result.events.first[:payload]["command"]).to be_nil
        end
      end
    end

    context "game branch: Game.find_by returns nil" do
      before { allow(::Game).to receive(:find_by).and_return(nil) }

      {
        "reindex game #99"  => nil,
        "reindex game 99"   => nil,
        "reindex games #99" => nil,
        "reindex games 99"  => nil,
        "reindex #99"       => nil,
        "reindex 99"        => nil
      }.each do |raw, _|
        it "#{raw.inspect} → :system event (game not found, no command key)" do
          result = call(raw)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
          expect(result.events.first[:payload]["command"]).to be_nil
        end
      end
    end
  end

  # ── Follow-up detail context ──────────────────────────────────────────────────
  #
  # `reindex` is declared in both video_detail and game_detail follow-up handlers:
  #   VideoDetail: self.actions "rm", "delete", "reindex", "link", "unlink", "shinies", "sync"
  #   GameDetail:  self.actions "rm", "delete", "reindex", "link", "unlink", "footage", ...
  #
  # In a follow-up context, video_target? reads reply_target from the source event
  # payload (not body_tokens) — "video_detail".start_with?("video") → video branch.
  # resolve_target reads the entity id from payload's id key (not message.raw).
  # The Message object is never accessed in this path — instance_double is intentional.

  describe "follow-up detail context" do
    context "reply_target: 'video_detail'" do
      it "source payload {video_id: VIDEO_REINDEX_STUB_ID} → :confirmation, command: 'video_reindex'" do
        source_event = instance_double(
          Event,
          payload: { "video_id" => VIDEO_REINDEX_STUB_ID, "reply_target" => "video_detail" }
        )
        ctx     = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "reindex")
        handler = Pito::Chat::Handlers::Reindex.new(
          message:      instance_double(Pito::Chat::Message),
          conversation: conversation,
          follow_up:    ctx
        )
        result = handler.call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("video_reindex")
        expect(event[:payload]["video_id"]).to eq(VIDEO_REINDEX_STUB_ID)
      end

      context "video stale — Video.find_by returns nil" do
        before { allow(::Video).to receive(:find_by).and_return(nil) }

        it "video_id in payload but record gone → :system event (no command)" do
          source_event = instance_double(
            Event,
            payload: { "video_id" => VIDEO_REINDEX_STUB_ID, "reply_target" => "video_detail" }
          )
          ctx     = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "reindex")
          handler = Pito::Chat::Handlers::Reindex.new(
            message:      instance_double(Pito::Chat::Message),
            conversation: conversation,
            follow_up:    ctx
          )
          result = handler.call
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
          expect(result.events.first[:payload]["command"]).to be_nil
        end
      end
    end

    context "reply_target: 'game_detail'" do
      it "source payload {game_id: GAME_REINDEX_STUB_ID} → :confirmation, command: 'game_reindex'" do
        source_event = instance_double(
          Event,
          payload: { "game_id" => GAME_REINDEX_STUB_ID, "reply_target" => "game_detail" }
        )
        ctx     = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "reindex")
        handler = Pito::Chat::Handlers::Reindex.new(
          message:      instance_double(Pito::Chat::Message),
          conversation: conversation,
          follow_up:    ctx
        )
        result = handler.call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("game_reindex")
        expect(event[:payload]["game_id"]).to eq(GAME_REINDEX_STUB_ID)
      end

      context "game stale — Game.find_by returns nil" do
        before { allow(::Game).to receive(:find_by).and_return(nil) }

        it "game_id in payload but record gone → :system event (no command)" do
          source_event = instance_double(
            Event,
            payload: { "game_id" => GAME_REINDEX_STUB_ID, "reply_target" => "game_detail" }
          )
          ctx     = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "reindex")
          handler = Pito::Chat::Handlers::Reindex.new(
            message:      instance_double(Pito::Chat::Message),
            conversation: conversation,
            follow_up:    ctx
          )
          result = handler.call
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
          expect(result.events.first[:payload]["command"]).to be_nil
        end
      end
    end
  end
end
