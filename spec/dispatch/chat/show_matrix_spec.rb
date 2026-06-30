# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `show` (recognition only, DB mocked) ──────────────────────
#
# RULE: every kwarg combination is recognized — no exception. Tests what the
# handler UNDERSTANDS from a raw input. All DB lookups and builder calls are
# stubbed — zero factories.
#
# Subject:  Pito::Chat::Handlers::Show  (app/services/pito/chat/handlers/show.rb)
# Resolver: id_only_resolution! — title (ILIKE) lookups are intentionally disabled.
#
# Branches:
#   channel branch — CHANNEL_NOUN_FILLERS (channel / channels) in body_tokens
#   video branch   — VIDEO_NOUN_FILLERS (vid / vids / video / videos) in body_tokens
#                    OR follow_up reply_target starts with "video"
#   game branch    — default fallthrough; also follow_up reply_target doesn't start "video"
#
# Follow-up scope:
#   video_list  — declares "show" → resolves a vid among the list's table_rows
#   game_list   — declares "show" → resolves a game among the list's table_rows
#   channel_list — declares only "shinies" — "show" is NOT reachable via this target;
#                  asserted against Pito::FollowUp::Registry directly
#
# Events on success (first event always :system detail):
#   video:   [:system video_detail, :enhanced analytics pending]
#            (+ :enhanced LinkedGame between them when a linked game is present)
#   game:    [:system game_detail, :enhanced SimilarGames, :enhanced Channels]
#            (+ :enhanced LinkedVideos between SimilarGames/Channels when linked videos exist,
#             + :enhanced analytics after Channels when linked videos exist)
#   channel: [:system channel_detail, :enhanced analytics pending]
#            (+ :enhanced Channel::Videos between them when the channel has videos)
#
# Not-found: Result::Ok, consume: false
# No ref:    Result::Error, message_key: "pito.chat.show.needs_ref"

RSpec.describe "Dispatch matrix — show (recognition, DB mocked)", type: :dispatch do
  SHOW_VID_ID  = 5
  SHOW_GAME_ID = 9
  SHOW_CHAN_ID = 11

  # Conversation double: stats_period fallback used by analytics_period helper
  let(:conversation) { double("Conversation", stats_period: "28d") }

  # Lean doubles — only the association accessors the handler checks in conditionals
  let(:video_double) do
    dbl = double("Video", id: SHOW_VID_ID)
    allow(dbl).to receive(:linked_games).and_return(double("Games", first: nil))
    dbl
  end

  let(:game_double) do
    dbl = double("Game", id: SHOW_GAME_ID)
    allow(dbl).to receive(:linked_videos).and_return(double("Videos", any?: false))
    dbl
  end

  let(:channel_double) do
    dbl = double("Channel", id: SHOW_CHAN_ID)
    allow(dbl).to receive(:videos).and_return(double("Vids", any?: false))
    dbl
  end

  # Build and call a Show handler from a raw string (free-chat path).
  # body_tokens are constructed from the words after the verb; message.raw is the
  # full string (used by extract_ref_from to strip verb + noun before the id).
  def make_handler(raw, follow_up: nil)
    parts       = raw.strip.split(/\s+/)
    body_words  = parts[1..]
    body_tokens = body_words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: true)
    end
    msg = Pito::Chat::Message.new(
      verb:        :show,
      body_tokens: body_tokens,
      kind:        :new_turn,
      raw:         raw
    )
    Pito::Chat::Handlers::Show.new(
      message:      msg,
      conversation: conversation,
      follow_up:    follow_up
    )
  end

  def call(raw, follow_up: nil)
    make_handler(raw, follow_up:).call
  end

  before do
    # Avoid the HandleGenerator's DB query (conversation.events)
    allow(Pito::HandleGenerator).to receive(:call).and_return("mock-show-1234")

    # DB lookups: return the matching type double for any find_by call
    allow(::Video).to   receive(:find_by).and_return(video_double)
    allow(::Game).to    receive(:find_by).and_return(game_double)
    allow(::Channel).to receive(:find_by).and_return(channel_double)

    # Builder stubs: return minimal identifying payloads (avoids ViewComponent + i18n)
    allow(Pito::MessageBuilder::Video::Detail).to receive(:call).and_return(
      "reply_target" => "video_detail",
      "video_id"     => SHOW_VID_ID,
      "reply_handle" => "mock-show-1234",
      "html"         => true
    )
    allow(Pito::MessageBuilder::Game::Detail).to receive(:call).and_return(
      "reply_target" => "game_detail",
      "game_id"      => SHOW_GAME_ID,
      "reply_handle" => "mock-show-1234",
      "html"         => true
    )
    allow(Pito::MessageBuilder::Channel::Detail).to receive(:call).and_return(
      "reply_target" => "channel_detail",
      "channel_id"   => SHOW_CHAN_ID,
      "reply_handle" => "mock-show-1234",
      "html"         => true
    )
    allow(Pito::MessageBuilder::Analytics::Enhanced).to receive(:pending).and_return(
      "analytics" => { "status" => "pending" }
    )
    allow(Pito::MessageBuilder::Game::Enhanced).to receive(:call).and_return(
      "body" => "<game-enhanced/>"
    )
    allow(Pito::MessageBuilder::Game::SimilarGames).to receive(:call).and_return(
      "body" => "<game-similar-games/>", "reply_target" => "game_similar",
      "reply_handle" => "mock-show-sim1"
    )
    allow(Pito::MessageBuilder::Game::Channels).to receive(:pending).and_return(
      "body" => "<game-channels/>", "reply_target" => "game_channels",
      "reply_handle" => "mock-show-chan1"
    )
    allow(Pito::MessageBuilder::Game::LinkedVideos).to receive(:call).and_return(
      "reply_target" => "game_linked_videos", "reply_handle" => "mock-show-5678",
      "game_id" => SHOW_GAME_ID
    )
    allow(Pito::MessageBuilder::Video::LinkedGame).to receive(:call).and_return(
      "reply_target" => "game_detail", "reply_handle" => "mock-show-5678"
    )
    allow(Pito::MessageBuilder::Channel::Videos).to receive(:call).and_return(
      "reply_target" => "video_list", "reply_handle" => "mock-show-5678"
    )
    # not-found text builder (video_not_found / game_not_found / channel_not_found)
    allow(Pito::MessageBuilder::Text).to receive(:call).and_return("text" => "not found")
  end

  # ── Video branch — all four noun fillers × both id forms ─────────────────────
  #
  # video_target? is true whenever a body token matches vid/vids/video/videos.
  # id_only_resolution!: leading `#` is stripped; only digits are accepted.

  describe "video noun — all fillers (vid/vids/video/videos) × id forms (#N and N)" do
    {
      "show vid ##{SHOW_VID_ID}"    => SHOW_VID_ID,
      "show vid #{SHOW_VID_ID}"     => SHOW_VID_ID,
      "show vids ##{SHOW_VID_ID}"   => SHOW_VID_ID,
      "show vids #{SHOW_VID_ID}"    => SHOW_VID_ID,
      "show video ##{SHOW_VID_ID}"  => SHOW_VID_ID,
      "show video #{SHOW_VID_ID}"   => SHOW_VID_ID,
      "show videos ##{SHOW_VID_ID}" => SHOW_VID_ID,
      "show videos #{SHOW_VID_ID}"  => SHOW_VID_ID
    }.each do |raw, expected_id|
      it "#{raw.inspect} → :system, reply_target: 'video_detail', video_id: #{expected_id}" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:system)
        expect(event[:payload]["reply_target"]).to eq("video_detail")
        expect(event[:payload]["video_id"]).to eq(expected_id)
      end
    end
  end

  # ── Video: non-numeric ref → not-found (id_only_resolution! fast path) ────────
  #
  # find_by_ref returns nil immediately for non-numeric refs — no DB call.
  # Verify the fast path: Video.find_by must NOT be called.

  describe "video — non-numeric ref → not-found (id_only_resolution!, no DB call)" do
    [
      "show vid some-title",
      "show video my gaming highlights",
      "show vids abc"
    ].each do |raw|
      it "#{raw.inspect} → not-found (consume: false, :system event, no video_id)" do
        expect(::Video).not_to receive(:find_by)
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.consume).to be(false)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["video_id"]).to be_nil
      end
    end
  end

  # ── Video: find_by returns nil → not-found ────────────────────────────────────

  describe "video — find_by returns nil → not-found (consume: false)" do
    before { allow(::Video).to receive(:find_by).and_return(nil) }

    {
      "show vid #99"    => nil,
      "show vids #99"   => nil,
      "show video #99"  => nil,
      "show videos #99" => nil,
      "show vid 99"     => nil
    }.each do |raw, _|
      it "#{raw.inspect} → consume: false, :system not-found event" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.consume).to be(false)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["video_id"]).to be_nil
      end
    end
  end

  # ── Game branch — both noun fillers × both id forms ───────────────────────────

  describe "game noun — both fillers (game/games) × id forms (#N and N)" do
    {
      "show game ##{SHOW_GAME_ID}"   => SHOW_GAME_ID,
      "show game #{SHOW_GAME_ID}"    => SHOW_GAME_ID,
      "show games ##{SHOW_GAME_ID}"  => SHOW_GAME_ID,
      "show games #{SHOW_GAME_ID}"   => SHOW_GAME_ID
    }.each do |raw, expected_id|
      it "#{raw.inspect} → :system, reply_target: 'game_detail', game_id: #{expected_id}" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:system)
        expect(event[:payload]["reply_target"]).to eq("game_detail")
        expect(event[:payload]["game_id"]).to eq(expected_id)
      end
    end
  end

  # ── No entity noun in free chat → NO GUESS → unknown_entity (huh) ─────────────
  #
  # Owner 2026-06-29: in free chat the 2nd token IS the entity — a bare id
  # (`show 123`), a hash id (`show #123`), or an unknown word (`show foo`) is NEVER
  # silently treated as a game. With neither channel_noun? nor video_target? nor an
  # EXPLICIT game_noun? (and not a follow-up), the handler returns a Result::Error
  # rendering the generic `pito.copy.huh` dictionary (NOT `pito.chat.show.needs_ref`,
  # NOT the game branch). DB is never touched.

  describe "no entity noun (bare id / hash id / unknown word) → unknown_entity (huh), no guess" do
    [
      "show ##{SHOW_GAME_ID}",
      "show #{SHOW_GAME_ID}",
      "show foo",
      "show lies-of-p"
    ].each do |raw|
      it "#{raw.inspect} → Result::Error rendering a pito.copy.huh variant (no DB call, not the game branch)" do
        expect(::Game).not_to receive(:find_by)
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).not_to eq("pito.chat.show.needs_ref")
        expect(I18n.t("pito.copy.huh")).to include(result.message_key)
      end
    end
  end

  # ── Game: non-numeric ref → not-found (id_only_resolution!) ──────────────────

  describe "game — non-numeric ref → not-found (id_only_resolution!, no DB call)" do
    [
      "show game lies-of-p",
      "show games some title"
    ].each do |raw|
      it "#{raw.inspect} → not-found (consume: false, no DB call)" do
        expect(::Game).not_to receive(:find_by)
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.consume).to be(false)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end
  end

  # ── Game: find_by returns nil → not-found ────────────────────────────────────

  describe "game — find_by returns nil → not-found (consume: false)" do
    before { allow(::Game).to receive(:find_by).and_return(nil) }

    {
      "show game #99"  => nil,
      "show games #99" => nil,
      "show game 99"   => nil
    }.each do |raw, _|
      it "#{raw.inspect} → consume: false, :system not-found event" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.consume).to be(false)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["game_id"]).to be_nil
      end
    end
  end

  # ── Channel branch — both noun fillers × @handle variants ────────────────────
  #
  # channel_noun? checks body_tokens for "channel"/"channels".
  # resolve_channel strips `@` and lowercases before DB lookup (::Channel.find_by
  # with a LOWER(REPLACE(...)) SQL condition, stubbed to return channel_double).

  describe "channel noun — both fillers (channel/channels) × @-prefix variants" do
    {
      "show channel @gmrdad82"  => SHOW_CHAN_ID,  # canonical @handle
      "show channel gmrdad82"   => SHOW_CHAN_ID,  # @-agnostic
      "show channel @GMRDAD82"  => SHOW_CHAN_ID,  # case-insensitive
      "show channels @gmrdad82" => SHOW_CHAN_ID,  # plural filler
      "show channels gmrdad82"  => SHOW_CHAN_ID   # plural + bare handle
    }.each do |raw, expected_id|
      it "#{raw.inspect} → :system, reply_target: 'channel_detail', channel_id: #{expected_id}" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event  = result.events.first
        expect(event[:kind]).to eq(:system)
        expect(event[:payload]["reply_target"]).to eq("channel_detail")
        expect(event[:payload]["channel_id"]).to eq(expected_id)
      end
    end
  end

  # ── Channel: find_by returns nil → not-found (consume: false) ────────────────

  describe "channel — find_by returns nil → not-found (consume: false)" do
    before { allow(::Channel).to receive(:find_by).and_return(nil) }

    [
      "show channel @nope",
      "show channels @unknown"
    ].each do |raw|
      it "#{raw.inspect} → consume: false, :system not-found event" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.consume).to be(false)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end
  end

  # ── Noun-only (no id) → Result::Error (needs_ref) ────────────────────────────
  #
  # An EXPLICIT entity noun with no id still names the entity → its needs_ref:
  #   - "show vid" (no id)    → video branch → extract_ref strips "vid" → "" → :needs_ref
  #   - "show game" (no id)   → game branch  → extract_ref strips "game" → "" → :needs_ref
  # (bare `show` and `show channel` are NOT here — see the no-guess + channel-needs-ref
  # blocks below. Owner 2026-06-29: no entity noun ⇒ never the game picker.)

  describe "noun-only input (explicit entity, no id) → Result::Error (needs_ref)" do
    [
      "show vid",
      "show vids",
      "show video",
      "show videos",
      "show game",
      "show games"
    ].each do |raw|
      it "#{raw.inspect} → Result::Error, message_key: pito.chat.show.needs_ref" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.show.needs_ref")
      end
    end
  end

  # Regression (owner 2026-06-29): a bare `show channel` (no @handle, no channel
  # scope) reads as a CHANNEL — its own channel needs-ref (a Result::Ok rendering
  # `pito.chat.show.channel_needs_ref`) — NOT the game picker (Result::Error
  # `pito.chat.show.needs_ref`). The bug was it being perceived as a game.
  # (MessageBuilder::Text is stubbed in the suite-wide `before`, so we assert the
  # COPY KEY routed to it, not the rendered string.)
  describe "bare `show channel`/`show channels` → channel needs-ref (never the game Error)" do
    [ "show channel", "show channels" ].each do |raw|
      it "#{raw.inspect} → Result::Ok rendering the channel needs-ref copy (not the game needs_ref)" do
        expect(Pito::MessageBuilder::Text).to receive(:call)
          .with("pito.chat.show.channel_needs_ref").and_return("text" => "Which channel?")

        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result).not_to be_a(Pito::Chat::Result::Error)
        expect(result.consume).to eq(false)
      end
    end
  end

  # ── Follow-up: video_list source ─────────────────────────────────────────────
  #
  # video_list declares "show" in its actions (verified below). Replying
  # `#<handle> show 5` routes through VerbDelegator → Show handler with a
  # FollowUpContext. In follow-up mode, video_target? reads reply_target (not
  # body_tokens): "video_list".start_with?("video") → true → video branch.
  # resolve_target sees no video_id in the list payload → resolve_in_list, which
  # reads table_rows to scope the resolution to rows visible to the user.

  describe "follow-up: video_list source + show <id>" do
    let(:video_list_source) do
      instance_double(
        Event,
        payload: {
          "reply_target" => "video_list",
          "table_rows"   => [
            { "cells" => [ { "text" => "##{SHOW_VID_ID}" } ] }
          ]
        }
      )
    end

    def show_from_video_list(rest)
      ctx = Pito::Chat::FollowUpContext.new(source_event: video_list_source, rest: rest)
      # channel_noun? checks body_tokens even in follow-up mode; empty → false
      msg = instance_double(Pito::Chat::Message, body_tokens: [])
      Pito::Chat::Handlers::Show.new(
        message:      msg,
        conversation: conversation,
        follow_up:    ctx
      ).call
    end

    it "video_list declares 'show' as an action (Registry contract)" do
      Pito::FollowUp::Registry.register_all!
      expect(Pito::FollowUp::Registry.actions_for("video_list")).to include("show")
    end

    it "show #{SHOW_VID_ID} → resolves vid from list rows → :system video_detail" do
      result = show_from_video_list(SHOW_VID_ID.to_s)
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["reply_target"]).to eq("video_detail")
    end

    it "show ##{SHOW_VID_ID} (hash-prefixed id) → same resolution" do
      result = show_from_video_list("##{SHOW_VID_ID}")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["reply_target"]).to eq("video_detail")
    end

    it "id not present in list table_rows → not-found (consume: false)" do
      # The record exists in DB but was not in the list the user replied to
      allow(::Video).to receive(:find_by).and_return(double("Video", id: 999))
      result = show_from_video_list("999")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.consume).to be(false)
    end

    it "empty rest (no ref after noun strip) → needs_ref" do
      result = show_from_video_list("")
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.show.needs_ref")
    end
  end

  # ── Follow-up: game_list source ───────────────────────────────────────────────
  #
  # game_list declares "show" in its actions. reply_target "game_list" does NOT
  # start with "video" → game branch. Same list-row scoping as video_list above.

  describe "follow-up: game_list source + show <id>" do
    let(:game_list_source) do
      instance_double(
        Event,
        payload: {
          "reply_target" => "game_list",
          "table_rows"   => [
            { "cells" => [ { "text" => "##{SHOW_GAME_ID}" } ] }
          ]
        }
      )
    end

    def show_from_game_list(rest)
      ctx = Pito::Chat::FollowUpContext.new(source_event: game_list_source, rest: rest)
      msg = instance_double(Pito::Chat::Message, body_tokens: [])
      Pito::Chat::Handlers::Show.new(
        message:      msg,
        conversation: conversation,
        follow_up:    ctx
      ).call
    end

    it "game_list declares 'show' as an action (Registry contract)" do
      Pito::FollowUp::Registry.register_all!
      expect(Pito::FollowUp::Registry.actions_for("game_list")).to include("show")
    end

    it "show #{SHOW_GAME_ID} → resolves game from list rows → :system game_detail" do
      result = show_from_game_list(SHOW_GAME_ID.to_s)
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["reply_target"]).to eq("game_detail")
    end

    it "show ##{SHOW_GAME_ID} (hash-prefixed id) → same resolution" do
      result = show_from_game_list("##{SHOW_GAME_ID}")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["reply_target"]).to eq("game_detail")
    end

    it "id not present in list table_rows → not-found (consume: false)" do
      allow(::Game).to receive(:find_by).and_return(double("Game", id: 999))
      result = show_from_game_list("999")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.consume).to be(false)
    end

    it "empty rest (no ref) → needs_ref" do
      result = show_from_game_list("")
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.show.needs_ref")
    end
  end

  # ── channel_list: show is NOT a declared action ───────────────────────────────
  #
  # channel_list declares only "shinies". VerbDelegator gates "show" out before
  # the Show handler is invoked — the gate is the Registry.actions_for check.
  # We assert the Registry fact directly instead of simulating the gated path.

  describe "channel_list: show is NOT a reachable action" do
    before { Pito::FollowUp::Registry.register_all! }

    it "channel_list actions do not include 'show'" do
      expect(Pito::FollowUp::Registry.actions_for("channel_list")).not_to include("show")
    end

    it "channel_list declares exactly ['shinies', 'analyze']" do
      expect(Pito::FollowUp::Registry.actions_for("channel_list")).to eq([ "shinies", "analyze" ])
    end
  end

  # ── Ordinal selectors: show first|last game (Phase FL) ───────────────────────
  #
  # `show {first|last} [<genre>] game` — resolved via OrdinalResolver (stubbed).
  # The handler routes ordinal forms BEFORE id resolution; no numeric ref is parsed.
  # Channel scope is passed via the handler's `channel` param (shift+tab).

  describe "ordinal game forms — recognition and routing" do
    before do
      allow(Pito::Chat::OrdinalResolver).to receive(:call)
        .with(hash_including(entity: :game))
        .and_return(game_double)
    end

    {
      "show first game"        => :first,
      "show last game"         => :last,
      "show first games"       => :first,
      "show last games"        => :last,
      "show first rpg game"    => :first,
      "show last rpg game"     => :last,
      "show last shooter game" => :last,
      "show first"             => :first,   # no noun → game branch default
      "show last"              => :last
    }.each do |raw, expected_ordinal|
      it "#{raw.inspect} → OrdinalResolver called with ordinal: #{expected_ordinal}, emits :system game_detail" do
        expect(Pito::Chat::OrdinalResolver).to receive(:call)
          .with(hash_including(entity: :game, ordinal: expected_ordinal))
          .and_return(game_double)
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event = result.events.first
        expect(event[:kind]).to eq(:system)
        expect(event[:payload]["reply_target"]).to eq("game_detail")
      end
    end

    it "show first rpg game → OrdinalResolver receives Role-playing genre filter" do
      expect(Pito::Chat::OrdinalResolver).to receive(:call)
        .with(hash_including(entity: :game, filters: hash_including(genre: "Role-playing")))
        .and_return(game_double)
      call("show first rpg game")
    end

    it "show last shooter game → OrdinalResolver receives Shooter genre filter" do
      expect(Pito::Chat::OrdinalResolver).to receive(:call)
        .with(hash_including(entity: :game, filters: hash_including(genre: "Shooter")))
        .and_return(game_double)
      call("show last shooter game")
    end

    describe "channel scope forwarded from handler channel attr (shift+tab)" do
      def call_with_channel(raw, channel_val)
        parts       = raw.strip.split(/\s+/)
        body_words  = parts[1..]
        body_tokens = body_words.each_with_index.map do |w, i|
          Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: true)
        end
        msg = Pito::Chat::Message.new(verb: :show, body_tokens: body_tokens, kind: :new_turn, raw: raw)
        Pito::Chat::Handlers::Show.new(message: msg, conversation: conversation,
                                        follow_up: nil, channel: channel_val).call
      end

      it "passes channel_scope to OrdinalResolver from the handler channel attr" do
        expect(Pito::Chat::OrdinalResolver).to receive(:call)
          .with(hash_including(entity: :game, channel_scope: "@testchan"))
          .and_return(game_double)
        call_with_channel("show last game", "@testchan")
      end

      it "@all channel_scope is forwarded as-is" do
        expect(Pito::Chat::OrdinalResolver).to receive(:call)
          .with(hash_including(entity: :game, channel_scope: "@all"))
          .and_return(game_double)
        call_with_channel("show last game", "@all")
      end
    end

    describe "OrdinalResolver returns nil → not-found (consume: false)" do
      before do
        allow(Pito::Chat::OrdinalResolver).to receive(:call)
          .with(hash_including(entity: :game))
          .and_return(nil)
      end

      [
        "show first game",
        "show last game",
        "show last rpg game"
      ].each do |raw|
        it "#{raw.inspect} → consume: false, :system not-found event, no game_id" do
          result = call(raw)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.consume).to be(false)
          expect(result.events.first[:kind]).to eq(:system)
          expect(result.events.first[:payload]["game_id"]).to be_nil
        end
      end
    end
  end

  # ── Ordinal selectors: show first|last vid (Phase FL) ────────────────────────
  #
  # `show {first|last} [<privacy>] vid` — resolved via OrdinalResolver (stubbed).
  # Default privacy: :published when no privacy word present (alias rule).

  describe "ordinal video forms — recognition and routing" do
    before do
      allow(Pito::Chat::OrdinalResolver).to receive(:call)
        .with(hash_including(entity: :video))
        .and_return(video_double)
    end

    {
      "show first vid"           => :first,
      "show last vid"            => :last,
      "show first video"         => :first,
      "show last video"          => :last,
      "show first vids"          => :first,
      "show last vids"           => :last,
      "show last published vid"  => :last,
      "show first published vid" => :first,
      "show last unlisted vid"   => :last,
      "show first unlisted vid"  => :first,
      "show last private vid"    => :last
    }.each do |raw, expected_ordinal|
      it "#{raw.inspect} → OrdinalResolver called with ordinal: #{expected_ordinal}, emits :system video_detail" do
        expect(Pito::Chat::OrdinalResolver).to receive(:call)
          .with(hash_including(entity: :video, ordinal: expected_ordinal))
          .and_return(video_double)
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event = result.events.first
        expect(event[:kind]).to eq(:system)
        expect(event[:payload]["reply_target"]).to eq("video_detail")
      end
    end

    it "show last vid → OrdinalResolver receives default :published privacy (alias rule)" do
      expect(Pito::Chat::OrdinalResolver).to receive(:call)
        .with(hash_including(entity: :video, filters: hash_including(privacy: :published)))
        .and_return(video_double)
      call("show last vid")
    end

    it "show last published vid → OrdinalResolver receives :published privacy" do
      expect(Pito::Chat::OrdinalResolver).to receive(:call)
        .with(hash_including(entity: :video, filters: hash_including(privacy: :published)))
        .and_return(video_double)
      call("show last published vid")
    end

    it "show last unlisted vid → OrdinalResolver receives :unlisted privacy" do
      expect(Pito::Chat::OrdinalResolver).to receive(:call)
        .with(hash_including(entity: :video, filters: hash_including(privacy: :unlisted)))
        .and_return(video_double)
      call("show last unlisted vid")
    end

    it "show last private vid → OrdinalResolver receives :privacy_status_private" do
      expect(Pito::Chat::OrdinalResolver).to receive(:call)
        .with(hash_including(entity: :video, filters: hash_including(privacy: :privacy_status_private)))
        .and_return(video_double)
      call("show last private vid")
    end

    describe "OrdinalResolver returns nil → not-found (consume: false)" do
      before do
        allow(Pito::Chat::OrdinalResolver).to receive(:call)
          .with(hash_including(entity: :video))
          .and_return(nil)
      end

      [
        "show last vid",
        "show first vid",
        "show last unlisted vid",
        "show last published vid"
      ].each do |raw|
        it "#{raw.inspect} → consume: false, :system not-found event, no video_id" do
          result = call(raw)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.consume).to be(false)
          expect(result.events.first[:kind]).to eq(:system)
          expect(result.events.first[:payload]["video_id"]).to be_nil
        end
      end
    end
  end

  # ── Follow-up: game_similar source + show <id> ────────────────────────────────
  #
  # game_similar declares "show" in its actions (verified via Registry).
  # When the GameSimilar handler calls this, it dispatches free-chat
  # "show game #<id>" — no follow_up context — so Show takes the game branch
  # by body_tokens (game noun present), not by reply_target.

  describe "follow-up: game_similar — registry and action declaration" do
    before { Pito::FollowUp::Registry.register_all! }

    it "game_similar declares 'show' as an action" do
      expect(Pito::FollowUp::Registry.actions_for("game_similar")).to include("show")
    end

    it "game_similar is registered in the Registry" do
      expect(Pito::FollowUp::Registry.for("game_similar")).to eq(Pito::FollowUp::Handlers::GameSimilar)
    end
  end

  # ── Follow-up: game_channels source + show @handle ────────────────────────────
  #
  # game_channels declares "show" in its actions. When the GameChannels handler
  # calls this, it dispatches free-chat "show channel @handle" — no follow_up
  # context — so Show takes the channel branch by body_tokens ("channel" present).

  describe "follow-up: game_channels — registry and action declaration" do
    before { Pito::FollowUp::Registry.register_all! }

    it "game_channels declares 'show' as an action" do
      expect(Pito::FollowUp::Registry.actions_for("game_channels")).to include("show")
    end

    it "game_channels is registered in the Registry" do
      expect(Pito::FollowUp::Registry.for("game_channels")).to eq(Pito::FollowUp::Handlers::GameChannels)
    end
  end

  # ── Follow-up: game_linked_videos source + show <id> ─────────────────────────
  #
  # game_linked_videos declares "show" and "unlink" in its actions.
  # The GameLinkedVideos handler dispatches "show vid #<id>" as free-chat
  # (no follow_up context) so Show takes the VIDEO branch by body_tokens.

  describe "follow-up: game_linked_videos — registry and action declaration" do
    before { Pito::FollowUp::Registry.register_all! }

    it "game_linked_videos declares 'show' as an action" do
      expect(Pito::FollowUp::Registry.actions_for("game_linked_videos")).to include("show")
    end

    it "game_linked_videos declares 'unlink' as an action" do
      expect(Pito::FollowUp::Registry.actions_for("game_linked_videos")).to include("unlink")
    end

    it "game_linked_videos is registered in the Registry" do
      expect(Pito::FollowUp::Registry.for("game_linked_videos")).to eq(Pito::FollowUp::Handlers::GameLinkedVideos)
    end
  end
end
