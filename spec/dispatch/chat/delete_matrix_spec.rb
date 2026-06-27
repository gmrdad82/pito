# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `delete` / `rm` (recognition only, DB mocked) ──────────────
#
# RULE: every kwarg combination recognized — no exception. Tests what the handler
# UNDERSTANDS from a raw input, not data persistence. All DB lookups are stubbed
# so the handler resolves records without touching the database.
#
# Subject:  Pito::Chat::Handlers::Delete  (app/services/pito/chat/handlers/delete.rb)
# Aliases:  `rm`, `del` (canonical: :delete — verified by chat_recognition_spec)
# Resolver: id_only_resolution! — title (ILIKE) lookups are intentionally disabled.
#
# Branches (video_target? in lib/pito/chat/target_resolution.rb):
#   video branch — any token in VIDEO_NOUN_FILLERS: vid / vids / video / videos
#   game branch  — default (no video noun OR follow-up reply_target starts "game")
#
# Confirmation payload keys emitted on success (MessageBuilder::*::DeleteConfirmation):
#   game:  { "command" => "game_delete",  "game_id"  => id, "game_title"  => title }
#   video: { "command" => "video_delete", "video_id" => id, "video_title" => title }

RSpec.describe "Dispatch matrix — delete (recognition, DB mocked)", type: :dispatch do
  VIDEO_STUB_ID = 42
  GAME_STUB_ID  =  7

  let(:video_double) { double("Video", id: VIDEO_STUB_ID, title: "Test Video") }
  let(:game_double)  { double("Game",  id: GAME_STUB_ID,  title: "Test Game") }

  # Conversation double: only used to thread through make_followupable!, which
  # calls Pito::HandleGenerator — stubbed below so no DB access ever occurs.
  let(:conversation) { double("Conversation") }

  # Build and call a Delete handler from a raw string.
  # verb is always :delete (canonical); `rm` vs `delete` only affects the first
  # word in raw (used by extract_ref_from to strip the verb before noun extraction).
  def make_handler(raw, follow_up: nil)
    parts       = raw.strip.split(/\s+/)
    body_words  = parts[1..]
    body_tokens = body_words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: true)
    end
    msg = Pito::Chat::Message.new(
      verb:        :delete,
      body_tokens: body_tokens,
      kind:        :new_turn,
      raw:         raw
    )
    Pito::Chat::Handlers::Delete.new(
      message:      msg,
      conversation: conversation,
      follow_up:    follow_up
    )
  end

  def call(raw, follow_up: nil)
    make_handler(raw, follow_up:).call
  end

  # Default stubs: every find_by succeeds, returning the matching type double.
  # HandleGenerator is stubbed to avoid the conversation.events DB query.
  before do
    allow(Pito::HandleGenerator).to receive(:call).and_return("mock-1234")
    allow(::Video).to receive(:find_by).and_return(video_double)
    allow(::Game).to receive(:find_by).and_return(game_double)
  end

  # ── Video noun — all four fillers × `delete` + `rm` × `#id` + bare id ────────
  #
  # video_target? is true whenever a body token matches vid/vids/video/videos.

  describe "video noun — all noun fillers, both verb forms, both id forms" do
    {
      # `delete` + singular vid
      "delete vid #5"    => VIDEO_STUB_ID,
      "delete vid 5"     => VIDEO_STUB_ID,
      # `delete` + plural vids
      "delete vids #5"   => VIDEO_STUB_ID,
      "delete vids 5"    => VIDEO_STUB_ID,
      # `delete` + singular video
      "delete video #5"  => VIDEO_STUB_ID,
      "delete video 5"   => VIDEO_STUB_ID,
      # `delete` + plural videos
      "delete videos #5" => VIDEO_STUB_ID,
      "delete videos 5"  => VIDEO_STUB_ID,
      # `rm` alias + singular vid
      "rm vid #5"        => VIDEO_STUB_ID,
      "rm vid 5"         => VIDEO_STUB_ID,
      # `rm` alias + plural vids
      "rm vids #5"       => VIDEO_STUB_ID,
      "rm vids 5"        => VIDEO_STUB_ID,
      # `rm` alias + singular video
      "rm video #5"      => VIDEO_STUB_ID,
      "rm video 5"       => VIDEO_STUB_ID,
      # `rm` alias + plural videos
      "rm videos #5"     => VIDEO_STUB_ID,
      "rm videos 5"      => VIDEO_STUB_ID,
      # `del` alias + singular vid
      "del vid #5"       => VIDEO_STUB_ID,
      "del vid 5"        => VIDEO_STUB_ID,
      # `del` alias + plural vids
      "del vids #5"      => VIDEO_STUB_ID,
      "del vids 5"       => VIDEO_STUB_ID,
      # `del` alias + singular video
      "del video #5"     => VIDEO_STUB_ID,
      "del video 5"      => VIDEO_STUB_ID,
      # `del` alias + plural videos
      "del videos #5"    => VIDEO_STUB_ID,
      "del videos 5"     => VIDEO_STUB_ID
    }.each do |raw, expected_id|
      it "#{raw.inspect} → :confirmation, command: 'video_delete', video_id: #{expected_id}" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("video_delete")
        expect(event[:payload]["video_id"]).to eq(expected_id)
      end
    end
  end

  # ── Game noun — both fillers × `delete` + `rm` × `#id` + bare id ─────────────

  describe "game noun — both noun fillers, both verb forms, both id forms" do
    {
      # `delete` + singular game
      "delete game #5"  => GAME_STUB_ID,
      "delete game 5"   => GAME_STUB_ID,
      # `delete` + plural games
      "delete games #5" => GAME_STUB_ID,
      "delete games 5"  => GAME_STUB_ID,
      # `rm` alias + singular game
      "rm game #5"      => GAME_STUB_ID,
      "rm game 5"       => GAME_STUB_ID,
      # `rm` alias + plural games
      "rm games #5"     => GAME_STUB_ID,
      "rm games 5"      => GAME_STUB_ID,
      # `del` alias + singular game
      "del game #5"     => GAME_STUB_ID,
      "del game 5"      => GAME_STUB_ID,
      # `del` alias + plural games
      "del games #5"    => GAME_STUB_ID,
      "del games 5"     => GAME_STUB_ID
    }.each do |raw, expected_id|
      it "#{raw.inspect} → :confirmation, command: 'game_delete', game_id: #{expected_id}" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("game_delete")
        expect(event[:payload]["game_id"]).to eq(expected_id)
      end
    end
  end

  # ── No noun → game branch (default) ──────────────────────────────────────────
  #
  # When no noun filler appears in body_tokens, video_target? is false → game
  # branch. The ref (`#5` or `5`) is still extracted from raw and resolved.

  describe "no noun → defaults to game branch" do
    {
      "delete #5" => GAME_STUB_ID,
      "delete 5"  => GAME_STUB_ID,
      "rm #5"     => GAME_STUB_ID,
      "rm 5"      => GAME_STUB_ID,
      "del #5"    => GAME_STUB_ID,
      "del 5"     => GAME_STUB_ID
    }.each do |raw, expected_id|
      it "#{raw.inspect} → :confirmation, command: 'game_delete' (no noun = game default)" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("game_delete")
        expect(event[:payload]["game_id"]).to eq(expected_id)
      end
    end
  end

  # ── Bare verb (no ref, no noun) → Result::Error ───────────────────────────────
  #
  # extract_ref_from strips the verb, then strip_noun returns "", which is blank
  # → :needs_ref → needs_ref → Result::Error.

  describe "bare verb, no ref → Result::Error (needs_ref)" do
    [ "delete", "rm", "del", "delete   ", "rm   ", "del   " ].each do |raw|
      it "#{raw.inspect} → Result::Error (message_key: pito.chat.delete.needs_ref)" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.delete.needs_ref")
      end
    end
  end

  # ── Noun only, no id → Result::Error ──────────────────────────────────────────
  #
  # After stripping the verb and noun, ref is blank → :needs_ref.

  describe "noun only (no id) → Result::Error (needs_ref)" do
    [
      "delete vid",
      "delete vids",
      "delete video",
      "delete videos",
      "delete game",
      "delete games",
      "rm vid",
      "rm vids",
      "rm video",
      "rm videos",
      "rm game",
      "rm games",
      "del vid",
      "del vids",
      "del video",
      "del videos",
      "del game",
      "del games"
    ].each do |raw|
      it "#{raw.inspect} → Result::Error (no id supplied)" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.delete.needs_ref")
      end
    end
  end

  # ── Not-found — find_by returns nil → :system event, no command ───────────────
  #
  # id-only resolution: a title ref returns nil immediately (no ILIKE fallback).
  # A numeric id that doesn't match also returns nil → not-found path.

  describe "not-found → :system event" do
    context "video branch: Video.find_by returns nil" do
      before { allow(::Video).to receive(:find_by).and_return(nil) }

      {
        "delete vid #99"    => nil,
        "delete vid 99"     => nil,
        "delete vids #99"   => nil,
        "delete video #99"  => nil,
        "delete videos #99" => nil,
        "rm vid #99"        => nil,
        "rm video #99"      => nil,
        "rm videos #99"     => nil,
        "del vid #99"       => nil,
        "del video #99"     => nil,
        "del videos #99"    => nil
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
        "delete game #99"  => nil,
        "delete game 99"   => nil,
        "delete games #99" => nil,
        "rm game #99"      => nil,
        "rm games #99"     => nil,
        "del game #99"     => nil,
        "del games #99"    => nil,
        "delete #99"       => nil,
        "rm #99"           => nil,
        "del #99"          => nil
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
  # When the handler is reached via `#<handle> delete` reply, video_target? reads
  # reply_target from the source event payload (not body_tokens), and resolve_target
  # reads the entity id from the payload's id key (not message.raw). The Message
  # object is never accessed in this path — instance_double is intentional.

  describe "follow-up detail context" do
    context "reply_target: 'video_detail'" do
      it "source payload {video_id: VIDEO_STUB_ID} → :confirmation, command: 'video_delete'" do
        source_event = instance_double(
          Event,
          payload: { "video_id" => VIDEO_STUB_ID, "reply_target" => "video_detail" }
        )
        ctx     = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "delete")
        handler = Pito::Chat::Handlers::Delete.new(
          message:      instance_double(Pito::Chat::Message),
          conversation: conversation,
          follow_up:    ctx
        )
        result = handler.call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("video_delete")
        expect(event[:payload]["video_id"]).to eq(VIDEO_STUB_ID)
      end

      # `#<handle> del` reply — the action word reaches the handler in `rest`
      # (already delegated to :delete by verb_delegator; see registry block below).
      # In detail context the entity id comes from the payload, so the path is
      # identical to `delete`/`rm` and must still emit video_delete.
      it "del reply (rest: 'del') → :confirmation, command: 'video_delete'" do
        source_event = instance_double(
          Event,
          payload: { "video_id" => VIDEO_STUB_ID, "reply_target" => "video_detail" }
        )
        ctx     = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "del")
        handler = Pito::Chat::Handlers::Delete.new(
          message:      instance_double(Pito::Chat::Message),
          conversation: conversation,
          follow_up:    ctx
        )
        event = handler.call.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("video_delete")
        expect(event[:payload]["video_id"]).to eq(VIDEO_STUB_ID)
      end

      context "video stale — Video.find_by returns nil" do
        before { allow(::Video).to receive(:find_by).and_return(nil) }

        it "video_id in payload but record gone → :system event" do
          source_event = instance_double(
            Event,
            payload: { "video_id" => VIDEO_STUB_ID, "reply_target" => "video_detail" }
          )
          ctx     = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "delete")
          handler = Pito::Chat::Handlers::Delete.new(
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
      it "source payload {game_id: GAME_STUB_ID} → :confirmation, command: 'game_delete'" do
        source_event = instance_double(
          Event,
          payload: { "game_id" => GAME_STUB_ID, "reply_target" => "game_detail" }
        )
        ctx     = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "delete")
        handler = Pito::Chat::Handlers::Delete.new(
          message:      instance_double(Pito::Chat::Message),
          conversation: conversation,
          follow_up:    ctx
        )
        result = handler.call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("game_delete")
        expect(event[:payload]["game_id"]).to eq(GAME_STUB_ID)
      end

      it "del reply (rest: 'del') → :confirmation, command: 'game_delete'" do
        source_event = instance_double(
          Event,
          payload: { "game_id" => GAME_STUB_ID, "reply_target" => "game_detail" }
        )
        ctx     = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "del")
        handler = Pito::Chat::Handlers::Delete.new(
          message:      instance_double(Pito::Chat::Message),
          conversation: conversation,
          follow_up:    ctx
        )
        event = handler.call.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("game_delete")
        expect(event[:payload]["game_id"]).to eq(GAME_STUB_ID)
      end

      context "game stale — Game.find_by returns nil" do
        before { allow(::Game).to receive(:find_by).and_return(nil) }

        it "game_id in payload but record gone → :system event" do
          source_event = instance_double(
            Event,
            payload: { "game_id" => GAME_STUB_ID, "reply_target" => "game_detail" }
          )
          ctx     = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "delete")
          handler = Pito::Chat::Handlers::Delete.new(
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

  # ── Follow-up registry — `del` is an allowed action on every delete target ────
  #
  # The follow-up delegator (Pito::FollowUp::VerbDelegator) only routes a reply's
  # action word when it appears in Registry.actions_for(reply_target). For `del`
  # to reach the Delete handler from a reply, it MUST be declared on each target
  # alongside the existing "delete" / "rm".
  describe "follow-up registry recognizes `del` (alongside delete/rm)" do
    before { Pito::FollowUp::Registry.register_all! }

    %w[video_detail game_detail video_list game_list].each do |target|
      it "actions_for(#{target.inspect}) includes del, delete, rm" do
        actions = Pito::FollowUp::Registry.actions_for(target).map(&:to_s)
        expect(actions).to include("del", "delete", "rm")
      end
    end
  end
end
