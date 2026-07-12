# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `shinies` (recognition only, DB mocked) ──────────────────
#
# RULE: every kwarg combination recognised — no exception. Tests what the handler
# UNDERSTANDS from a raw input, not data persistence. All DB lookups and the
# ViewComponent-rendering MessageBuilder are stubbed so nothing touches the DB.
#
# Subject:  Pito::Chat::Handlers::Shinies  (lib/pito/chat/handlers/shinies.rb)
# Resolver: id_only_resolution! — ILIKE title lookups are intentionally disabled.
#
# ── Entity branches ───────────────────────────────────────────────────────────
#
#   channel branch — channel_noun? true:
#     free-chat:   any body token in CHANNEL_NOUN_FILLERS (channel/channels)
#     follow-up:   reply_target.start_with?("channel")
#   video branch   — video_target? true:
#     free-chat:   any body token in VIDEO_NOUN_FILLERS (vid/vids/video/videos)
#     follow-up:   reply_target.start_with?("video")
#   game branch    — default when no channel/video noun token present
#
# IMPORTANT: `shinies @handle` WITHOUT a channel noun → game branch (not channel).
# The "channel"/"channels" noun token is mandatory to enter the channel branch.
#
# ── Channel resolution ────────────────────────────────────────────────────────
#
#   free-chat:  extract_ref_from(message.raw, CHANNEL_NOUN_FILLERS)
#               = strip verb token, then strip leading channel noun → @handle
#   follow-up:  strip_noun(follow_up.rest, CHANNEL_NOUN_FILLERS) → @handle
#   normalize:  handle.sub(/\A@+/, "").downcase → SQL LOWER(REPLACE(handle,'@',''))
#
# ── Follow-up paths that declare shinies in Registry ─────────────────────────
#
#   video_detail → ToolDelegator → Shinies handler with video_detail reply_target
#   video_list   → ToolDelegator → Shinies handler with video_list reply_target
#   game_detail  → ToolDelegator → Shinies handler with game_detail reply_target
#   game_list    → ToolDelegator → Shinies handler with game_list reply_target
#   channel_list → ChannelList handler delegates directly to ToolDelegator
#
# Note: channel_detail only declares "visit" and "sync" — shinies is NOT a
# follow-up action from channel_detail, so it is not tested here.
#
# ── Result shapes ─────────────────────────────────────────────────────────────
#
#   Success   → Pito::Chat::Result::Ok, one :system event
#               payload: { "body" => String, "html" => true, "<entity>_id" => id }
#   Needs ref → Pito::Chat::Result::Error
#               message_key: "pito.chat.shinies.needs_ref"
#   Not found → Pito::Chat::Result::Ok, one :system event, text payload (no "html")

RSpec.describe "Dispatch matrix — shinies (recognition, DB mocked)", type: :dispatch do
  SHINIES_CHANNEL_ID = 11
  SHINIES_VIDEO_ID   = 42
  SHINIES_GAME_ID    =  7

  let(:channel_double) { double("Channel", id: SHINIES_CHANNEL_ID) }
  let(:video_double)   { double("Video",   id: SHINIES_VIDEO_ID) }
  let(:game_double)    { double("Game",    id: SHINIES_GAME_ID) }
  let(:conversation)   { double("Conversation") }

  # Stub all DB lookups and the ViewComponent-rendering builder.
  # MessageBuilder::Shinies renders a ShiniesComponent — not needed in a routing spec.
  before do
    allow(::Channel).to receive(:find_by).and_return(channel_double)
    allow(::Video).to  receive(:find_by).and_return(video_double)
    allow(::Game).to   receive(:find_by).and_return(game_double)

    allow(Pito::MessageBuilder::Shinies).to receive(:call).with(channel_double)
      .and_return({ "body" => "<shinies/>", "html" => true, "channel_id" => SHINIES_CHANNEL_ID })
    allow(Pito::MessageBuilder::Shinies).to receive(:call).with(video_double)
      .and_return({ "body" => "<shinies/>", "html" => true, "video_id" => SHINIES_VIDEO_ID })
    allow(Pito::MessageBuilder::Shinies).to receive(:call).with(game_double)
      .and_return({ "body" => "<shinies/>", "html" => true, "game_id" => SHINIES_GAME_ID })

    # Not-found paths (channel_not_found / entity_not_found) use MessageBuilder::Text.
    allow(Pito::MessageBuilder::Text).to receive(:call).and_return({ "text" => "not found" })
  end

  # Build a Shinies handler from a raw input string.
  # body_tokens are derived from the words after the verb ("shinies") so that
  # channel_noun? and video_target? work correctly from the token list.
  def make_handler(raw, follow_up: nil)
    words = raw.to_s.strip.split(/\s+/)[1..] || []
    body_tokens = words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
    msg = Pito::Chat::Message.new(
      tool:        :shinies,
      body_tokens: body_tokens,
      kind:        :new_turn,
      raw:         raw
    )
    Pito::Chat::Handlers::Shinies.new(
      message:      msg,
      conversation: conversation,
      follow_up:    follow_up
    )
  end

  def call(raw, follow_up: nil)
    make_handler(raw, follow_up: follow_up).call
  end

  # ── Follow-up context helpers ─────────────────────────────────────────────────

  def video_detail_ctx(video_id: SHINIES_VIDEO_ID, rest: "")
    src = instance_double(Event, payload: { "video_id" => video_id, "reply_target" => "video_detail" })
    Pito::Chat::FollowUpContext.new(source_event: src, rest: rest)
  end

  def game_detail_ctx(game_id: SHINIES_GAME_ID, rest: "")
    src = instance_double(Event, payload: { "game_id" => game_id, "reply_target" => "game_detail" })
    Pito::Chat::FollowUpContext.new(source_event: src, rest: rest)
  end

  def video_list_ctx(rest:, table_rows: [])
    src = instance_double(Event, payload: { "reply_target" => "video_list", "table_rows" => table_rows })
    Pito::Chat::FollowUpContext.new(source_event: src, rest: rest)
  end

  def game_list_ctx(rest:, table_rows: [])
    src = instance_double(Event, payload: { "reply_target" => "game_list", "table_rows" => table_rows })
    Pito::Chat::FollowUpContext.new(source_event: src, rest: rest)
  end

  def channel_list_ctx(rest:)
    src = instance_double(Event, payload: { "reply_target" => "channel_list" })
    Pito::Chat::FollowUpContext.new(source_event: src, rest: rest)
  end

  # ── ① Channel branch — free chat ─────────────────────────────────────────────
  #
  # channel_noun? = true when any body token value (downcased) is in
  # CHANNEL_NOUN_FILLERS = %w[channel channels].
  # channel_ref extraction: strip verb from raw, then strip_noun → @handle string.
  # resolve_channel: strip leading @, downcase → SQL LOWER(REPLACE) compare.

  describe "① channel branch — free chat (channel/channels noun)" do
    {
      "shinies channel @pito"   => SHINIES_CHANNEL_ID,
      "shinies channel pito"    => SHINIES_CHANNEL_ID,  # no @ needed; normalized in resolver
      "shinies channel @PITO"   => SHINIES_CHANNEL_ID,  # case-insensitive
      "shinies channel PITO"    => SHINIES_CHANNEL_ID,  # uppercase, no @
      "shinies channels @pito"  => SHINIES_CHANNEL_ID,  # plural noun filler
      "shinies channels pito"   => SHINIES_CHANNEL_ID   # plural, no @
    }.each do |raw, expected_id|
      it "#{raw.inspect} → Ok :system, channel_id: #{expected_id}" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["channel_id"]).to eq(expected_id)
      end
    end

    it "shinies channel @pito → html payload (html: true, body: String)" do
      result = call("shinies channel @pito")
      payload = result.events.first[:payload]
      expect(payload["html"]).to be(true)
      expect(payload["body"]).to be_a(String)
    end

    it "emits exactly one :system event" do
      events = call("shinies channel @pito").events
      expect(events.size).to eq(1)
      expect(events.first[:kind]).to eq(:system)
    end

    # channel noun present but no handle after stripping → blank handle → needs_ref
    context "channel noun only, no handle → Result::Error (needs_ref)" do
      [ "shinies channel", "shinies channel   ", "shinies channels" ].each do |raw|
        it "#{raw.inspect} → Result::Error (pito.chat.shinies.needs_ref)" do
          result = call(raw)
          expect(result).to be_a(Pito::Chat::Result::Error)
          expect(result.message_key).to eq("pito.chat.shinies.needs_ref")
        end
      end
    end

    # channel_not_found: Channel.find_by returns nil → Ok :system text event (not an Error)
    context "channel not found (Channel.find_by returns nil)" do
      before { allow(::Channel).to receive(:find_by).and_return(nil) }

      [ "shinies channel @nope", "shinies channels @nope" ].each do |raw|
        it "#{raw.inspect} → Ok :system text event (no html key)" do
          result = call(raw)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
          # channel_not_found uses MessageBuilder::Text (text payload, not html)
          expect(result.events.first[:payload].key?("html")).to be(false)
        end
      end
    end
  end

  # ── ② `shinies @handle` without channel noun → game branch ──────────────────
  #
  # Without "channel"/"channels" in body_tokens, channel_noun? is false.
  # The @handle is non-numeric → id_only_resolution! bails before DB call → nil
  # → entity_not_found → Ok :system text event (no shinies achievements shown).

  describe "② shinies @handle (no channel noun) → game branch → not found" do
    before { allow(::Game).to receive(:find_by).and_return(nil) }

    [ "shinies @pito", "shinies @unknown", "shinies @PITO" ].each do |raw|
      it "#{raw.inspect} → game branch, Ok :system text event" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload].key?("html")).to be(false)
      end
    end

    it "shinies @pito → Game.find_by NOT called (id_only short-circuits for @-prefixed ref)" do
      call("shinies @pito")
      expect(::Game).not_to have_received(:find_by)
    end
  end

  # ── ③ Video branch — all four noun fillers × both id forms ──────────────────
  #
  # video_target? = true when any body token is in VIDEO_NOUN_FILLERS =
  # %w[vid vids video videos]. id_only_resolution! — numeric ids only.

  describe "③ video branch — all noun fillers, both id forms" do
    {
      "shinies vid #5"    => SHINIES_VIDEO_ID,
      "shinies vid 5"     => SHINIES_VIDEO_ID,
      "shinies vids #5"   => SHINIES_VIDEO_ID,
      "shinies vids 5"    => SHINIES_VIDEO_ID,
      "shinies video #5"  => SHINIES_VIDEO_ID,
      "shinies video 5"   => SHINIES_VIDEO_ID,
      "shinies videos #5" => SHINIES_VIDEO_ID,
      "shinies videos 5"  => SHINIES_VIDEO_ID
    }.each do |raw, expected_id|
      it "#{raw.inspect} → Ok :system, video_id: #{expected_id}" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["video_id"]).to eq(expected_id)
      end
    end

    # video noun present but no id after stripping → blank ref → needs_ref
    context "video noun only (no id) → Result::Error (needs_ref)" do
      %w[shinies\ vid shinies\ vids shinies\ video shinies\ videos].each do |raw|
        it "#{raw.inspect} → Result::Error (pito.chat.shinies.needs_ref)" do
          result = call(raw)
          expect(result).to be_a(Pito::Chat::Result::Error)
          expect(result.message_key).to eq("pito.chat.shinies.needs_ref")
        end
      end
    end

    # entity_not_found: Video.find_by returns nil → Ok :system text event
    context "video not found (Video.find_by returns nil)" do
      before { allow(::Video).to receive(:find_by).and_return(nil) }

      {
        "shinies vid #99"    => nil,
        "shinies vids 99"    => nil,
        "shinies video #99"  => nil,
        "shinies videos 99"  => nil
      }.each do |raw, _|
        it "#{raw.inspect} → Ok :system text event (no html key)" do
          result = call(raw)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
          expect(result.events.first[:payload].key?("html")).to be(false)
        end
      end
    end

    # id_only_resolution!: non-numeric title ref → nil without hitting the DB
    context "non-numeric title ref → not found (id_only, no DB call)" do
      it "shinies vid BossRush → Ok :system text event, Video.find_by not called" do
        result = call("shinies vid BossRush")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(::Video).not_to have_received(:find_by)
      end

      it "shinies video EldenRing → Ok :system text event, Video.find_by not called" do
        result = call("shinies video EldenRing")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(::Video).not_to have_received(:find_by)
      end
    end
  end

  # ── ④ Game branch — all noun fillers × both id forms ────────────────────────
  #
  # Default branch when no channel/video noun is in body_tokens.
  # GAME_NOUN_FILLERS = %w[game games] are stripped before the id ref.
  # id_only_resolution! — numeric ids only.

  describe "④ game branch — all noun fillers, both id forms" do
    {
      "shinies game #5"   => SHINIES_GAME_ID,
      "shinies game 5"    => SHINIES_GAME_ID,
      "shinies games #5"  => SHINIES_GAME_ID,
      "shinies games 5"   => SHINIES_GAME_ID,
      "shinies #5"        => SHINIES_GAME_ID,  # no noun → still game branch
      "shinies 5"         => SHINIES_GAME_ID   # bare integer, no noun
    }.each do |raw, expected_id|
      it "#{raw.inspect} → Ok :system, game_id: #{expected_id}" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["game_id"]).to eq(expected_id)
      end
    end

    # game noun only (no id) → blank ref → needs_ref
    context "game noun only (no id) → Result::Error (needs_ref)" do
      [ "shinies game", "shinies games" ].each do |raw|
        it "#{raw.inspect} → Result::Error (pito.chat.shinies.needs_ref)" do
          result = call(raw)
          expect(result).to be_a(Pito::Chat::Result::Error)
          expect(result.message_key).to eq("pito.chat.shinies.needs_ref")
        end
      end
    end

    # entity_not_found: Game.find_by returns nil → Ok :system text event
    context "game not found (Game.find_by returns nil)" do
      before { allow(::Game).to receive(:find_by).and_return(nil) }

      {
        "shinies game #99" => nil,
        "shinies games 99" => nil,
        "shinies #99"      => nil,
        "shinies 99"       => nil
      }.each do |raw, _|
        it "#{raw.inspect} → Ok :system text event (no html key)" do
          result = call(raw)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
          expect(result.events.first[:payload].key?("html")).to be(false)
        end
      end
    end

    # id_only_resolution!: non-numeric title ref → nil without hitting the DB
    context "non-numeric title ref → not found (id_only, no DB call)" do
      it "shinies game LiesOfP → Ok :system text event, Game.find_by not called" do
        result = call("shinies game LiesOfP")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(::Game).not_to have_received(:find_by)
      end

      it "shinies EldenRing → Ok :system text event, Game.find_by not called" do
        result = call("shinies EldenRing")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(::Game).not_to have_received(:find_by)
      end
    end
  end

  # ── ⑤ Bare shinies → game branch → needs_ref ────────────────────────────────
  #
  # No noun, no ref → game branch → extract_ref_from yields blank → :needs_ref.

  describe "⑤ bare shinies — no ref, no noun → needs_ref" do
    [ "shinies", "shinies   " ].each do |raw|
      it "#{raw.inspect} → Result::Error (pito.chat.shinies.needs_ref)" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.shinies.needs_ref")
      end
    end
  end

  # ── ⑥ Follow-up: video_detail ────────────────────────────────────────────────
  #
  # reply_target "video_detail" → video_target? = true (starts_with?("video"))
  # → handle_video → resolve_target reads video_id from the source card payload.

  describe "⑥ follow-up — video_detail (video_id from card payload)" do
    it "video_id in payload → Ok :system event, video_id resolved" do
      result = call("shinies", follow_up: video_detail_ctx)
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["video_id"]).to eq(SHINIES_VIDEO_ID)
    end

    it "passes through even with non-empty rest (rest is ignored in detail context)" do
      # ToolDelegator strips the verb; rest goes to FollowUpContext.rest which is
      # ignored when the payload's video_id takes precedence.
      result = call("shinies", follow_up: video_detail_ctx(rest: "ignored"))
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["video_id"]).to eq(SHINIES_VIDEO_ID)
    end

    context "stale card — Video.find_by returns nil" do
      before { allow(::Video).to receive(:find_by).and_return(nil) }

      it "video_id in payload but record gone → Ok :system text event" do
        result = call("shinies", follow_up: video_detail_ctx)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload].key?("html")).to be(false)
      end
    end
  end

  # ── ⑦ Follow-up: game_detail ─────────────────────────────────────────────────
  #
  # reply_target "game_detail" → channel_noun? false, video_target? false
  # → handle_game → resolve_target reads game_id from the source card payload.

  describe "⑦ follow-up — game_detail (game_id from card payload)" do
    it "game_id in payload → Ok :system event, game_id resolved" do
      result = call("shinies", follow_up: game_detail_ctx)
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["game_id"]).to eq(SHINIES_GAME_ID)
    end

    context "stale card — Game.find_by returns nil" do
      before { allow(::Game).to receive(:find_by).and_return(nil) }

      it "game_id in payload but record gone → Ok :system text event" do
        result = call("shinies", follow_up: game_detail_ctx)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload].key?("html")).to be(false)
      end
    end
  end

  # ── ⑧ Follow-up: video_list ──────────────────────────────────────────────────
  #
  # reply_target "video_list" → video_target? = true → handle_video.
  # resolve_target: payload has no video_id → resolve_in_list.
  # strip_noun(follow_up.rest, VIDEO_NOUN_FILLERS) extracts the numeric ref.
  # When table_rows is non-empty, the resolved record's id must appear in that list.

  describe "⑧ follow-up — video_list (video id in follow_up.rest)" do
    {
      "##{SHINIES_VIDEO_ID}"      => SHINIES_VIDEO_ID,
      SHINIES_VIDEO_ID.to_s       => SHINIES_VIDEO_ID,
      "vid #{SHINIES_VIDEO_ID}"   => SHINIES_VIDEO_ID,  # noun filler stripped
      "vids ##{SHINIES_VIDEO_ID}" => SHINIES_VIDEO_ID,  # noun filler + # form
      "video #{SHINIES_VIDEO_ID}" => SHINIES_VIDEO_ID,
      "videos ##{SHINIES_VIDEO_ID}" => SHINIES_VIDEO_ID
    }.each do |rest, expected_id|
      it "rest #{rest.inspect} → Ok :system, video_id: #{expected_id}" do
        result = call("shinies", follow_up: video_list_ctx(rest: rest))
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["video_id"]).to eq(expected_id)
      end
    end

    it "blank rest → needs_ref → Result::Error" do
      result = call("shinies", follow_up: video_list_ctx(rest: ""))
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.shinies.needs_ref")
    end

    it "video noun only in rest, no id → needs_ref" do
      result = call("shinies", follow_up: video_list_ctx(rest: "vid"))
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.shinies.needs_ref")
    end

    context "video id NOT in table_rows scope → nil → not found" do
      # list only shows id 99; resolved record's id (SHINIES_VIDEO_ID) is not in list
      let(:rows_without_video) { [ { cells: [ { text: "#99" } ] } ] }

      it "video id outside list scope → Ok :system text event" do
        ctx    = video_list_ctx(rest: SHINIES_VIDEO_ID.to_s, table_rows: rows_without_video)
        result = call("shinies", follow_up: ctx)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload].key?("html")).to be(false)
      end
    end

    context "video id IS in table_rows scope → resolves normally" do
      let(:rows_with_video) { [ { cells: [ { text: "##{SHINIES_VIDEO_ID}" } ] } ] }

      it "video id in list scope → :system event, video_id resolved" do
        ctx    = video_list_ctx(rest: SHINIES_VIDEO_ID.to_s, table_rows: rows_with_video)
        result = call("shinies", follow_up: ctx)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:payload]["video_id"]).to eq(SHINIES_VIDEO_ID)
      end
    end

    context "empty table_rows (unrestricted scope) → any video id passes" do
      it "empty rows → no scope filtering → resolves normally" do
        ctx    = video_list_ctx(rest: SHINIES_VIDEO_ID.to_s, table_rows: [])
        result = call("shinies", follow_up: ctx)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:payload]["video_id"]).to eq(SHINIES_VIDEO_ID)
      end
    end
  end

  # ── ⑨ Follow-up: game_list ───────────────────────────────────────────────────
  #
  # reply_target "game_list" → channel_noun? false, video_target? false → handle_game.
  # resolve_target: payload has no game_id → resolve_in_list.
  # strip_noun(follow_up.rest, GAME_NOUN_FILLERS) extracts the numeric ref.

  describe "⑨ follow-up — game_list (game id in follow_up.rest)" do
    {
      "##{SHINIES_GAME_ID}"      => SHINIES_GAME_ID,
      SHINIES_GAME_ID.to_s       => SHINIES_GAME_ID,
      "game #{SHINIES_GAME_ID}"  => SHINIES_GAME_ID,   # noun filler stripped
      "games ##{SHINIES_GAME_ID}" => SHINIES_GAME_ID   # noun filler + # form
    }.each do |rest, expected_id|
      it "rest #{rest.inspect} → Ok :system, game_id: #{expected_id}" do
        result = call("shinies", follow_up: game_list_ctx(rest: rest))
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["game_id"]).to eq(expected_id)
      end
    end

    it "blank rest → needs_ref → Result::Error" do
      result = call("shinies", follow_up: game_list_ctx(rest: ""))
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.shinies.needs_ref")
    end

    it "game noun only in rest, no id → needs_ref" do
      result = call("shinies", follow_up: game_list_ctx(rest: "game"))
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.shinies.needs_ref")
    end

    it "games noun only in rest, no id → needs_ref" do
      result = call("shinies", follow_up: game_list_ctx(rest: "games"))
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.shinies.needs_ref")
    end

    context "game id NOT in table_rows scope → nil → not found" do
      let(:rows_without_game) { [ { cells: [ { text: "#99" } ] } ] }

      it "game id outside list scope → Ok :system text event" do
        ctx    = game_list_ctx(rest: SHINIES_GAME_ID.to_s, table_rows: rows_without_game)
        result = call("shinies", follow_up: ctx)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload].key?("html")).to be(false)
      end
    end

    context "game id IS in table_rows scope → resolves normally" do
      let(:rows_with_game) { [ { cells: [ { text: "##{SHINIES_GAME_ID}" } ] } ] }

      it "game id in list scope → :system event, game_id resolved" do
        ctx    = game_list_ctx(rest: SHINIES_GAME_ID.to_s, table_rows: rows_with_game)
        result = call("shinies", follow_up: ctx)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:payload]["game_id"]).to eq(SHINIES_GAME_ID)
      end
    end

    context "empty table_rows (unrestricted scope) → any game id passes" do
      it "empty rows → no scope filtering → resolves normally" do
        ctx    = game_list_ctx(rest: SHINIES_GAME_ID.to_s, table_rows: [])
        result = call("shinies", follow_up: ctx)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:payload]["game_id"]).to eq(SHINIES_GAME_ID)
      end
    end
  end

  # ── ⑩ Follow-up: channel_list ────────────────────────────────────────────────
  #
  # reply_target "channel_list" → channel_noun? = true (reply_target.start_with?("channel"))
  # → handle_channel.
  # channel_ref = strip_noun(follow_up.rest, CHANNEL_NOUN_FILLERS).
  # Resolution: strip leading @, lowercase → SQL LOWER(REPLACE(handle,'@','')) compare.

  describe "⑩ follow-up — channel_list (@handle in follow_up.rest)" do
    {
      "@pito"           => SHINIES_CHANNEL_ID,
      "pito"            => SHINIES_CHANNEL_ID,  # no @ prefix
      "@PITO"           => SHINIES_CHANNEL_ID,  # case insensitive
      "PITO"            => SHINIES_CHANNEL_ID,  # uppercase, no @
      "channel @pito"   => SHINIES_CHANNEL_ID,  # channel noun stripped from rest
      "channels @pito"  => SHINIES_CHANNEL_ID,  # channels noun stripped from rest
      "channel pito"    => SHINIES_CHANNEL_ID,  # noun stripped, no @
      "channels PITO"   => SHINIES_CHANNEL_ID   # noun stripped, uppercase, no @
    }.each do |rest, expected_id|
      it "rest #{rest.inspect} → Ok :system, channel_id: #{expected_id}" do
        result = call("shinies", follow_up: channel_list_ctx(rest: rest))
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["channel_id"]).to eq(expected_id)
      end
    end

    it "blank rest → needs_ref → Result::Error" do
      result = call("shinies", follow_up: channel_list_ctx(rest: ""))
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.shinies.needs_ref")
    end

    it "channel noun only in rest (no handle) → needs_ref" do
      result = call("shinies", follow_up: channel_list_ctx(rest: "channel"))
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.shinies.needs_ref")
    end

    it "channels noun only in rest (no handle) → needs_ref" do
      result = call("shinies", follow_up: channel_list_ctx(rest: "channels"))
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.shinies.needs_ref")
    end

    context "channel not found (Channel.find_by returns nil)" do
      before { allow(::Channel).to receive(:find_by).and_return(nil) }

      [ "@nope", "nope", "channel @nope" ].each do |rest|
        it "rest #{rest.inspect} → Ok :system text event (channel not found)" do
          result = call("shinies", follow_up: channel_list_ctx(rest: rest))
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
          expect(result.events.first[:payload].key?("html")).to be(false)
        end
      end
    end
  end
end
