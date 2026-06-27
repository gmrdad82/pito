# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `unlist` (recognition only, DB mocked) ─────────────────────
#
# RULE: every kwarg combination is recognised — no exception. We test what the
# handler UNDERSTANDS from a raw input, not data persistence. All DB lookups are
# stubbed so the handler resolves records without touching the database.
#
# Subject: Pito::Chat::Handlers::Unlist
#          (app/services/pito/chat/handlers/unlist.rb)
#
# Resolution path — own implementation, NOT TargetResolution:
#   extract_ref  → strips NOUN_FILLERS from body_tokens, joins remainder.
#   resolve_video → strips leading `#`, requires /\A\d+\z/, calls Video.find_by(id:).
#                   Non-numeric refs return nil immediately (no ILIKE fallback).
#
# NOUN_FILLERS = %w[vid vids video videos]
#
# Result shapes:
#   Found      → Result::Ok   events: [{ kind: :confirmation,
#                                         payload: { "command"      => "video_unlist",
#                                                    "video_id"     => id,
#                                                    "video_title"  => title,
#                                                    "reply_handle" => handle,
#                                                    "reply_target" => "confirmation" } }]
#   Not-found  → Result::Ok   events: [{ kind: :system, payload: (no "command" key) }]
#   No ref     → Result::Error { message_key: "pito.chat.unlist.needs_ref" }
#
# Follow-up note (Phase F4 — source changed):
#   `unlist` IS NOW declared in video_detail's action list
#   (app/services/pito/follow_up/handlers/video_detail.rb — actions include
#   rm, del, delete, reindex, link, unlink, shinies, sync, publish, pub,
#   unlist, schedule). A `#<handle> unlist` reply on a video_detail card is
#   delegated to this chat Unlist handler with a FollowUpContext attached.
#   The handler is follow-up-aware: when no ref is typed it reads `video_id`
#   from the source event payload (see Unlist#call follow_up? branch).
#   `unlist` is also declared in video_list's action list
#   (app/services/pito/follow_up/handlers/video_list.rb). Both registry
#   contracts and the video_detail follow-up resolution are asserted below.

RSpec.describe "Dispatch matrix — unlist (recognition, DB mocked)", type: :dispatch do
  # Shared stub id — every stubbed Video.find_by call returns this id.
  UNLIST_VIDEO_STUB_ID = 42

  let(:video_double) { double("Video", id: UNLIST_VIDEO_STUB_ID, title: "Test Video") }
  let(:conversation) { double("Conversation") }

  before do
    # Avoid the Conversation#events DB query inside Pito::HandleGenerator.
    allow(Pito::HandleGenerator).to receive(:call).and_return("mock-1234")
    # Default: every Video.find_by succeeds.
    allow(::Video).to receive(:find_by).and_return(video_double)
  end

  # Build and invoke an Unlist handler from a raw chat input string.
  # Splits on whitespace — the verb is the first word, the rest become body_tokens.
  def make_handler(raw, follow_up: nil)
    parts       = raw.strip.split(/\s+/)
    body_words  = parts[1..]
    body_tokens = body_words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: true)
    end
    msg = Pito::Chat::Message.new(
      verb:        :unlist,
      body_tokens: body_tokens,
      kind:        :new_turn,
      raw:         raw
    )
    Pito::Chat::Handlers::Unlist.new(
      message:      msg,
      conversation: conversation,
      follow_up:    follow_up
    )
  end

  def call(raw, follow_up: nil)
    make_handler(raw, follow_up:).call
  end

  # ── #id forms — all four noun fillers + no filler ─────────────────────────────
  #
  # Token layout examples:
  #   "unlist #5"        body_tokens: ["#5"]           → ref "#5"  → id "5"
  #   "unlist vid #5"    body_tokens: ["vid", "#5"]    → after reject: ["#5"] → id "5"
  #   "unlist video #5"  body_tokens: ["video", "#5"]  → after reject: ["#5"] → id "5"
  # resolve_video strips the leading `#` before the digit check, so "#5" → "5".

  describe "noun fillers × #id form → :confirmation, command: 'video_unlist'" do
    {
      # bare #id (no noun filler)
      "unlist #5"        => UNLIST_VIDEO_STUB_ID,
      # vid + #id
      "unlist vid #5"    => UNLIST_VIDEO_STUB_ID,
      # vids + #id
      "unlist vids #5"   => UNLIST_VIDEO_STUB_ID,
      # video + #id
      "unlist video #5"  => UNLIST_VIDEO_STUB_ID,
      # videos + #id
      "unlist videos #5" => UNLIST_VIDEO_STUB_ID
    }.each do |raw, expected_id|
      it "#{raw.inspect} → :confirmation, video_id: #{expected_id}" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("video_unlist")
        expect(event[:payload]["video_id"]).to eq(expected_id)
      end
    end
  end

  # ── Bare numeric id forms — all four noun fillers + no filler ─────────────────
  #
  # "unlist 5"        body_tokens: ["5"]          → ref "5"  → id "5" (digits)
  # "unlist video 5"  body_tokens: ["video", "5"] → after reject: ["5"] → id "5"

  describe "noun fillers × bare numeric id → :confirmation, command: 'video_unlist'" do
    {
      # bare id (no noun filler)
      "unlist 5"        => UNLIST_VIDEO_STUB_ID,
      # vid + bare id
      "unlist vid 5"    => UNLIST_VIDEO_STUB_ID,
      # vids + bare id
      "unlist vids 5"   => UNLIST_VIDEO_STUB_ID,
      # video + bare id
      "unlist video 5"  => UNLIST_VIDEO_STUB_ID,
      # videos + bare id
      "unlist videos 5" => UNLIST_VIDEO_STUB_ID
    }.each do |raw, expected_id|
      it "#{raw.inspect} → :confirmation, video_id: #{expected_id}" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("video_unlist")
        expect(event[:payload]["video_id"]).to eq(expected_id)
      end
    end
  end

  # ── Confirmation payload completeness ─────────────────────────────────────────
  #
  # UnlistConfirmation emits: command, body, html, video_id, video_title, plus the
  # follow-up stamp: reply_handle, reply_target.

  describe "confirmation payload — full key coverage" do
    it "unlist #5 → payload carries all expected keys" do
      result  = call("unlist #5")
      payload = result.events.first[:payload]
      expect(payload["command"]).to     eq("video_unlist")
      expect(payload["video_id"]).to    eq(UNLIST_VIDEO_STUB_ID)
      expect(payload["video_title"]).to eq("Test Video")
      expect(payload["reply_handle"]).to be_present
      expect(payload["reply_target"]).to eq("confirmation")
    end
  end

  # ── Bare verb / noun-only (no id ref) → Result::Error (needs_ref) ─────────────
  #
  # After stripping noun fillers, the remaining tokens are empty → extract_ref
  # returns "" → blank → needs_ref.

  describe "bare verb / noun only (no id) → Result::Error" do
    [
      "unlist",
      "unlist   ",
      "unlist vid",
      "unlist vids",
      "unlist video",
      "unlist videos"
    ].each do |raw|
      it "#{raw.inspect} → Result::Error, message_key: 'pito.chat.unlist.needs_ref'" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.unlist.needs_ref")
      end
    end
  end

  # ── Not-found paths ───────────────────────────────────────────────────────────
  #
  # Two sub-cases both resolve to not_found → Result::Ok + :system event:
  #   a) Numeric ref supplied, Video.find_by returns nil (record absent or wrong id).
  #   b) Non-numeric ref supplied → resolve_video returns nil immediately without
  #      hitting the DB (no ILIKE fallback, unlike TargetResolution's find_by_ref).

  describe "not-found → :system event (no 'command' key in payload)" do
    context "numeric ref, Video.find_by returns nil" do
      before { allow(::Video).to receive(:find_by).and_return(nil) }

      {
        "unlist #99"        => nil,
        "unlist 99"         => nil,
        "unlist vid #99"    => nil,
        "unlist vids 99"    => nil,
        "unlist video #99"  => nil,
        "unlist videos 99"  => nil
      }.each do |raw, _|
        it "#{raw.inspect} → :system event, no command" do
          result = call(raw)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
          expect(result.events.first[:payload]["command"]).to be_nil
        end
      end
    end

    context "non-numeric ref → resolve_video returns nil (no DB call)" do
      # The handler's resolve_video returns nil for any non-digit ref.
      [
        "unlist abc",
        "unlist video abc",
        "unlist vid some-title",
        "unlist #abc"
      ].each do |raw|
        it "#{raw.inspect} → :system event, no command" do
          result = call(raw)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
          expect(result.events.first[:payload]["command"]).to be_nil
        end
      end
    end
  end

  # ── Follow-up registry contract ───────────────────────────────────────────────
  #
  # Phase F4: `unlist` is NOW declared in the video_detail follow-up handler's
  # action list (app/services/pito/follow_up/handlers/video_detail.rb → includes
  # "unlist" alongside rm/del/delete/reindex/link/unlink/shinies/sync/publish/
  # pub/schedule). A `#<handle> unlist` reply on a video_detail card is therefore
  # delegated via VerbDelegator to the chat Unlist handler.
  #
  # `unlist` is also declared in the video_list follow-up handler's action list
  # (app/services/pito/follow_up/handlers/video_list.rb → includes "unlist").
  #
  # We assert membership only (the action sets carry other verbs too) — not the
  # exact set, which is owned by the source and changes as verbs are added.

  describe "follow-up registry contract" do
    before { Pito::FollowUp::Registry.register_all! }

    it "video_detail follow-up actions include 'unlist'" do
      expect(Pito::FollowUp::Registry.actions_for("video_detail")).to include("unlist")
    end

    it "video_list follow-up actions include 'unlist'" do
      expect(Pito::FollowUp::Registry.actions_for("video_list")).to include("unlist")
    end
  end

  # ── Follow-up: video_detail reply (`#<handle> unlist`) ─────────────────────────
  #
  # When the user replies `#<handle> unlist` on a video_detail card, VerbDelegator
  # reconstructs a chat invocation of verb :unlist with NO trailing ref (body_tokens
  # empty) and a FollowUpContext carrying the source event. Unlist#call's
  # extract_ref is then blank, so it takes the `follow_up?` branch and reads
  # `video_id` from the source event payload.
  #
  # We build the handler directly (mirroring the link/unlink matrix specs):
  # raw "unlist" → empty body_tokens → blank ref → follow_up branch.

  describe "follow-up: video_detail card (`#<handle> unlist`, no typed ref)" do
    def detail_source_event(payload)
      instance_double(Event, payload: payload)
    end

    def follow_up_for(payload)
      Pito::Chat::FollowUpContext.new(
        source_event: detail_source_event(payload),
        rest:         "unlist"
      )
    end

    it "resolves the card's video → :confirmation, command 'video_unlist', video_id 42" do
      payload = { "video_id" => UNLIST_VIDEO_STUB_ID, "reply_target" => "video_detail" }
      expect(::Video).to receive(:find_by).with(id: UNLIST_VIDEO_STUB_ID).and_return(video_double)

      result = call("unlist", follow_up: follow_up_for(payload))

      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("video_unlist")
      expect(event[:payload]["video_id"]).to eq(UNLIST_VIDEO_STUB_ID)
    end

    it "stale card (Video.find_by → nil) → :system not-found, no command" do
      payload = { "video_id" => UNLIST_VIDEO_STUB_ID, "reply_target" => "video_detail" }
      allow(::Video).to receive(:find_by).and_return(nil)

      result = call("unlist", follow_up: follow_up_for(payload))

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["command"]).to be_nil
    end

    it "missing video_id in payload → Result::Error needs_ref" do
      payload = { "reply_target" => "video_detail" } # no video_id key

      result = call("unlist", follow_up: follow_up_for(payload))

      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.unlist.needs_ref")
    end
  end
end
