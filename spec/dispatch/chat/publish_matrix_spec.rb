# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `publish` (recognition only, DB mocked) ────────────────────
#
# RULE: every kwarg combination is recognised — no exception. We test what the
# handler UNDERSTANDS from a raw input, not data persistence. All DB lookups are
# stubbed so the handler resolves records without touching the database.
#
# Subject: Pito::Chat::Handlers::Publish
#          (lib/pito/chat/handlers/publish.rb)
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
#                                         payload: { "command" => "video_publish",
#                                                    "video_id"    => id,
#                                                    "video_title" => title,
#                                                    "reply_handle" => handle,
#                                                    "reply_target" => "confirmation" } }]
#   Not-found  → Result::Ok   events: [{ kind: :system, payload: (no "command" key) }]
#   No ref     → Result::Error { message_key: "pito.chat.publish.needs_ref" }
#
# Follow-up note: publish.rb reads message.body_tokens directly and never
# consults follow_up.source_event.payload. A `#<handle> publish` reply with no
# body tokens → extract_ref → "" → needs_ref. This is covered in the
# follow-up section below; a failing test there indicates a RECOGNITION BUG.

RSpec.describe "Dispatch matrix — publish (recognition, DB mocked)", type: :dispatch do
  # Shared stub id — every stubbed Video.find_by call returns this id.
  PUBLISH_VIDEO_STUB_ID = 42

  # publish_now_violation: nil — the stage-time spacing-law dry-run finds no
  # violation in recognition examples (the law itself is spacing_policy_spec's).
  let(:video_double) { double("Video", id: PUBLISH_VIDEO_STUB_ID, title: "Test Video", publish_now_violation: nil) }
  let(:conversation) { double("Conversation") }

  before do
    # Avoid the Conversation#events DB query inside Pito::HandleGenerator.
    allow(Pito::HandleGenerator).to receive(:call).and_return("mock-1234")
    # Default: every Video.find_by succeeds.
    allow(::Video).to receive(:find_by).and_return(video_double)
  end

  # Build and invoke a Publish handler from a raw chat input string.
  # Splits on whitespace — the verb is the first word, the rest become body_tokens.
  def make_handler(raw, follow_up: nil)
    parts       = raw.strip.split(/\s+/)
    body_words  = parts[1..]
    body_tokens = body_words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: true)
    end
    msg = Pito::Chat::Message.new(
      tool:        :publish,
      body_tokens: body_tokens,
      kind:        :new_turn,
      raw:         raw
    )
    Pito::Chat::Handlers::Publish.new(
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
  #   "publish #5"        body_tokens: ["#5"]           → ref "#5"  → id "5"
  #   "publish vid #5"    body_tokens: ["vid", "#5"]    → after reject: ["#5"] → id "5"
  #   "publish video #5"  body_tokens: ["video", "#5"]  → after reject: ["#5"] → id "5"
  # resolve_video strips the leading `#` before the digit check, so "#5" → "5".

  describe "noun fillers × #id form → :confirmation, command: 'video_publish'" do
    {
      # bare #id (no noun filler)
      "publish #5"        => PUBLISH_VIDEO_STUB_ID,
      # vid + #id
      "publish vid #5"    => PUBLISH_VIDEO_STUB_ID,
      # vids + #id
      "publish vids #5"   => PUBLISH_VIDEO_STUB_ID,
      # video + #id
      "publish video #5"  => PUBLISH_VIDEO_STUB_ID,
      # videos + #id
      "publish videos #5" => PUBLISH_VIDEO_STUB_ID
    }.each do |raw, expected_id|
      it "#{raw.inspect} → :confirmation, video_id: #{expected_id}" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("video_publish")
        expect(event[:payload]["video_id"]).to eq(expected_id)
      end
    end
  end

  # ── Bare numeric id forms — all four noun fillers + no filler ─────────────────
  #
  # "publish 5"        body_tokens: ["5"]         → ref "5"  → id "5" (digits)
  # "publish video 5"  body_tokens: ["video", "5"] → after reject: ["5"] → id "5"

  describe "noun fillers × bare numeric id → :confirmation, command: 'video_publish'" do
    {
      # bare id (no noun filler)
      "publish 5"        => PUBLISH_VIDEO_STUB_ID,
      # vid + bare id
      "publish vid 5"    => PUBLISH_VIDEO_STUB_ID,
      # vids + bare id
      "publish vids 5"   => PUBLISH_VIDEO_STUB_ID,
      # video + bare id
      "publish video 5"  => PUBLISH_VIDEO_STUB_ID,
      # videos + bare id
      "publish videos 5" => PUBLISH_VIDEO_STUB_ID
    }.each do |raw, expected_id|
      it "#{raw.inspect} → :confirmation, video_id: #{expected_id}" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("video_publish")
        expect(event[:payload]["video_id"]).to eq(expected_id)
      end
    end
  end

  # ── Confirmation payload completeness ─────────────────────────────────────────
  #
  # PublishConfirmation emits: command, body, html, video_id, video_title, plus the
  # follow-up stamp: reply_handle, reply_target.

  describe "confirmation payload — full key coverage" do
    it "publish #5 → payload carries all expected keys" do
      result  = call("publish #5")
      payload = result.events.first[:payload]
      expect(payload["command"]).to     eq("video_publish")
      expect(payload["video_id"]).to    eq(PUBLISH_VIDEO_STUB_ID)
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
      "publish",
      "publish   ",
      "publish vid",
      "publish vids",
      "publish video",
      "publish videos"
    ].each do |raw|
      it "#{raw.inspect} → Result::Error, message_key: 'pito.chat.publish.needs_ref'" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.publish.needs_ref")
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
        "publish #99"        => nil,
        "publish 99"         => nil,
        "publish vid #99"    => nil,
        "publish vids 99"    => nil,
        "publish video #99"  => nil,
        "publish videos 99"  => nil
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
        "publish abc",
        "publish video abc",
        "publish vid some-title",
        "publish #abc"
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

  # ── Publish IS a video_detail reply action (publish + pub alias) ─────────────
  #
  # publish/pub are registered video_detail follow-up actions
  # (lib/pito/follow_up/handlers/video_detail.rb:29-30). A
  # `#<handle> publish` reply on a video_detail card is delegated (ToolDelegator)
  # to the chat Publish handler, which reads video_id from the source event's
  # payload. We don't assert an exact action set — it also carries
  # del/sync/unlist/schedule — only that publish + pub are present.

  describe "publish + pub are video_detail reply actions" do
    before { Pito::FollowUp::Registry.register_all! }

    it "video_detail follow-up actions include 'publish'" do
      expect(Pito::FollowUp::Registry.actions_for("video_detail")).to include("publish")
    end

    it "video_detail follow-up actions include the 'pub' alias" do
      expect(Pito::FollowUp::Registry.actions_for("video_detail")).to include("pub")
    end
  end

  # ── Follow-up detail context — `#<handle> publish` on a video_detail card ─────
  #
  # publish.rb's follow_up branch (lines 22-28): when no typed ref is present and
  # follow_up? is true, it reads video_id from follow_up.source_event.payload,
  # resolves via ::Video.find_by, and emits the publish confirmation. The Message
  # object is never read on this path, so an instance_double with empty body_tokens
  # is intentional (extract_ref must return "" so the follow_up branch is taken).

  describe "follow-up detail context — video_detail card" do
    def follow_up_handler(payload:, rest: "publish")
      source_event = instance_double(Event, payload: payload)
      ctx          = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: rest)
      Pito::Chat::Handlers::Publish.new(
        message:      instance_double(Pito::Chat::Message, body_tokens: []),
        conversation: conversation,
        follow_up:    ctx
      )
    end

    it "#<handle> publish → resolves source video, emits :confirmation (video_id from payload)" do
      result = follow_up_handler(
        payload: { "video_id" => PUBLISH_VIDEO_STUB_ID, "reply_target" => "video_detail" }
      ).call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to eq("video_publish")
      expect(event[:payload]["video_id"]).to eq(PUBLISH_VIDEO_STUB_ID)
    end

    it "#<handle> publish with empty rest → same confirmation (rest unused on this path)" do
      result = follow_up_handler(
        payload: { "video_id" => PUBLISH_VIDEO_STUB_ID, "reply_target" => "video_detail" },
        rest:    ""
      ).call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["video_id"]).to eq(PUBLISH_VIDEO_STUB_ID)
    end

    context "stale source — video_id present but ::Video.find_by returns nil" do
      before { allow(::Video).to receive(:find_by).and_return(nil) }

      it "→ not-found :system event (no command)" do
        result = follow_up_handler(
          payload: { "video_id" => PUBLISH_VIDEO_STUB_ID, "reply_target" => "video_detail" }
        ).call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["command"]).to be_nil
      end
    end

    context "missing video_id in source payload" do
      it "→ Result::Error (needs_ref)" do
        result = follow_up_handler(
          payload: { "reply_target" => "video_detail" }
        ).call
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.publish.needs_ref")
      end
    end
  end

  # ── `pub` alias — resolves to the same chat Publish handler ──────────────────
  #
  # The grammar registers `:pub` as an alias of `:publish` (lib/pito/grammar/specs.rb).
  # The Parser canonicalizes the alias to verb :publish (parser.rb), and the chat
  # Registry maps :publish → Pito::Chat::Handlers::Publish. We prove the alias
  # routing through the REAL lexer/parser + registry, then exercise the same
  # recognition cases the canonical `publish` verb supports.

  describe "`pub` alias resolution (real lexer/parser + registry)" do
    {
      "pub #5"        => PUBLISH_VIDEO_STUB_ID,
      "pub 5"         => PUBLISH_VIDEO_STUB_ID,
      "pub vid #5"    => PUBLISH_VIDEO_STUB_ID,
      "pub video #5"  => PUBLISH_VIDEO_STUB_ID,
      "pub videos 5"  => PUBLISH_VIDEO_STUB_ID
    }.each do |raw, expected_id|
      it "#{raw.inspect} → verb :publish → Publish handler → :confirmation, video_id #{expected_id}" do
        message = Pito::Chat::Parser.call(
          Pito::Lex::Lexer.call(raw),
          raw:          raw,
          conversation: conversation
        )
        # Parser canonicalizes the alias `pub` to the publish verb.
        expect(message.tool).to eq(:publish)
        # The chat registry routes that canonical verb to the Publish handler.
        expect(Pito::Chat::Registry.lookup(message.tool)).to eq(Pito::Chat::Handlers::Publish)

        result = Pito::Chat::Handlers::Publish.new(
          message:      message,
          conversation: conversation,
          follow_up:    nil
        ).call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("video_publish")
        expect(event[:payload]["video_id"]).to eq(expected_id)
      end
    end

    it "bare `pub` (no ref) → Result::Error (needs_ref)" do
      message = Pito::Chat::Parser.call(
        Pito::Lex::Lexer.call("pub"),
        raw:          "pub",
        conversation: conversation
      )
      expect(message.tool).to eq(:publish)
      result = Pito::Chat::Handlers::Publish.new(
        message: message, conversation: conversation, follow_up: nil
      ).call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.publish.needs_ref")
    end
  end
end
