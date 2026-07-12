# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `sync` (recognition only, DB mocked) ──────────────────────
#
# RULE: every kwarg combination is recognized — no exception. Tests what the
# handler UNDERSTANDS from a raw input. All DB lookups and builder calls are
# stubbed — zero factories.
#
# Subject: Pito::Chat::Handlers::Sync
#   lib/pito/chat/handlers/sync.rb
#
# Branches:
#   channels branch  — CHANNEL_NOUN_FILLERS in raw (channel/channels, no leading -)
#   video branch     — VIDEO_NOUN_FILLERS in raw (vid/vids/video/videos, no leading -)
#   game branch      — `game(s)` in raw WITH an #id → direct id-based game sync
#   needs_ref        — bare sync, --flag forms, `sync game` WITHOUT an #id
#
# Video branch sub-cases:
#   #id(s) present           → ids win; scope ignored; video_ids: [ids], channel_ids: []
#   `only <ids>` (legacy)    → same behaviour as #id form
#   no ids, @all/blank scope → channel_ids: [], video_ids: []
#   no ids, @handle scope    → channel_ids: [resolved_id], video_ids: []
#   no ids, unknown handle   → :system error event
#
# Channel branch sub-cases:
#   no `with` clause                   → sync_channel, with_items: []
#   `with` vid/vids/video/videos alias → sync_channel_videos, with_items: ["videos"]
#   `with` only unknown tokens         → silently dropped; sync_channel, with_items: []
#   `with` videos + unknown tokens     → sync_channel_videos, unknown dropped
#   @handle scope                      → channel_ids: [resolved_id]
#   unknown handle                     → :system error event
#
# Follow-up (`#<handle> sync` on a detail card):
#   video_detail   → sync_videos, video_ids: [source.video_id], channel_ids: []
#   channel_detail → sync_channel, channel_ids: [source.channel_id], with_items: []
#   game_detail    → sync_game, game_id: source.game_id
#   trailing args always ignored (context is unambiguous)
#   unknown target → needs_ref Error
#
# Registry: sync declared as action on video_detail / channel_detail / game_detail

RSpec.describe "Dispatch matrix — sync (recognition, DB mocked)", type: :dispatch do
  SYNC_VID_ID  = 5
  SYNC_CHAN_ID = 7
  SYNC_GAME_ID = 3

  # DB-free conversation double (conversation.id is stored in confirmation payloads)
  let(:conversation) { double("Conversation", id: 99) }

  # Typed doubles for DB lookups — is_a? stubs satisfy the handler's guard checks
  let(:channel_double) do
    dbl = double("Channel", id: SYNC_CHAN_ID, handle: "@pito", title: "PITO")
    allow(dbl).to receive(:is_a?).with(::Channel).and_return(true)
    dbl
  end

  let(:video_double) do
    dbl = double("Video", id: SYNC_VID_ID)
    allow(dbl).to receive(:is_a?).with(::Video).and_return(true)
    dbl
  end

  let(:game_double) do
    dbl = double("Game", id: SYNC_GAME_ID, title: "Hollow Knight")
    allow(dbl).to receive(:is_a?).with(::Game).and_return(true)
    dbl
  end

  before do
    # Avoid the HandleGenerator DB query (conversation.events uniqueness check).
    allow(Pito::HandleGenerator).to receive(:call).and_return("mock-sync-h1")

    # DB stubs — any find_by returns the appropriate typed double.
    allow(::Channel).to receive(:find_by).and_return(channel_double)
    allow(::Video).to  receive(:find_by).and_return(video_double)
    allow(::Game).to   receive(:find_by).and_return(game_double)

    # Builder stubs — capture parsed args and echo back the key payload fields.
    # This verifies the handler's routing/parsing without triggering i18n or DB.
    allow(Pito::MessageBuilder::Sync::VideosConfirmation).to receive(:call) do |_, channel_ids:, video_ids:, conversation:|
      { "command" => "sync_videos", "channel_ids" => channel_ids, "video_ids" => video_ids }
    end

    allow(Pito::MessageBuilder::Sync::ChannelConfirmation).to receive(:call) do |_, channel_ids:, with_items:, conversation:|
      { "command" => "sync_channel", "channel_ids" => channel_ids, "with_items" => Array(with_items).map(&:to_s) }
    end

    allow(Pito::MessageBuilder::Sync::ChannelVideosConfirmation).to receive(:call) do |_, channel_ids:, with_items:, conversation:|
      { "command" => "sync_channel_videos", "channel_ids" => channel_ids, "with_items" => Array(with_items).map(&:to_s) }
    end

    allow(Pito::MessageBuilder::Sync::GameConfirmation).to receive(:call) do |game, conversation:|
      { "command" => "sync_game", "game_id" => game.id }
    end

    # Text builder: used by resolve_scope to emit a "channel not found" error payload.
    allow(Pito::MessageBuilder::Text).to receive(:call).and_return({ "body" => "not found" })
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  # Build + call a free-chat Sync handler from a raw string.
  # `raw` is the full input including the "sync" verb (mirrors what the dispatcher sees).
  def make_handler(raw, channel: nil)
    parts       = raw.strip.split(/\s+/)
    body_words  = parts[1..]  # everything after the verb
    body_tokens = body_words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: true)
    end
    msg = Pito::Chat::Message.new(
      tool: :sync, body_tokens: body_tokens, kind: :new_turn, raw: raw
    )
    Pito::Chat::Handlers::Sync.new(
      message: msg, conversation: conversation, channel: channel
    )
  end

  def call(raw, channel: nil)
    make_handler(raw, channel:).call
  end

  def payload_of(raw, channel: nil)
    call(raw, channel:).events.first[:payload]
  end

  # Simulate a `#<handle> sync` reply on a detail card (follow-up path).
  # Trailing `rest` is always ignored by the handler — the source event's
  # reply_target fixes which entity is targeted unambiguously.
  def sync_follow_up(source_payload, rest: "")
    source_event = instance_double(Event, payload: source_payload)
    ctx          = Pito::Chat::FollowUpContext.new(source_event:, rest:)
    msg          = instance_double(Pito::Chat::Message)
    Pito::Chat::Handlers::Sync.new(
      message: msg, conversation: conversation, follow_up: ctx
    ).call
  end

  # ── 1. Video noun aliases — bare, @all scope ──────────────────────────────────
  #
  # All four VIDEO_NOUN_FILLERS, no ids, @all (or blank) scope:
  #   command: sync_videos, channel_ids: [], video_ids: []

  describe "video noun — all four aliases, bare (no ids, @all scope)" do
    %w[vid vids video videos].each do |noun|
      it "sync #{noun} @all → sync_videos, channel_ids: [], video_ids: []" do
        p = payload_of("sync #{noun}", channel: "@all")
        expect(p["command"]).to eq("sync_videos")
        expect(p["channel_ids"]).to eq([])
        expect(p["video_ids"]).to   eq([])
      end
    end
  end

  # ── 2. Video noun — nil / blank channel scope behaves like @all ───────────────

  describe "video noun — nil scope → treats as @all (channel_ids: [])" do
    it "sync vids (nil scope) → sync_videos, channel_ids: [], video_ids: []" do
      p = payload_of("sync vids")
      expect(p["command"]).to eq("sync_videos")
      expect(p["channel_ids"]).to eq([])
      expect(p["video_ids"]).to   eq([])
    end

    it "sync videos (nil scope) → sync_videos, channel_ids: [], video_ids: []" do
      p = payload_of("sync videos")
      expect(p["command"]).to eq("sync_videos")
      expect(p["channel_ids"]).to eq([])
    end
  end

  # ── 3. Video noun — @handle scope, no ids ────────────────────────────────────
  #
  # No #ids in input → obey shift+tab channel scope.
  # resolve_scope finds the channel and returns [ch.id].

  describe "video noun — @handle scope → resolved channel_ids, video_ids: []" do
    %w[vid vids video videos].each do |noun|
      it "sync #{noun} @pito scope → channel_ids: [#{SYNC_CHAN_ID}], video_ids: []" do
        p = payload_of("sync #{noun}", channel: "@pito")
        expect(p["command"]).to eq("sync_videos")
        expect(p["channel_ids"]).to eq([ SYNC_CHAN_ID ])
        expect(p["video_ids"]).to   eq([])
      end
    end
  end

  # ── 4. Video noun + #ids — ids win, scope entirely ignored ───────────────────
  #
  # When hash-prefixed ids are present, video_ids carries them and
  # channel_ids is always [] regardless of the shift+tab scope.

  describe "video noun + #ids — ids win, channel_ids always []" do
    {
      "sync vids #1"          => [ 1 ],
      "sync vids #1,#2"       => [ 1, 2 ],
      "sync vids #1 #2"       => [ 1, 2 ],
      "sync vid #5"           => [ 5 ],
      "sync video #5"         => [ 5 ],
      "sync videos #5,#6"     => [ 5, 6 ],
      "sync videos #1,#2,#3"  => [ 1, 2, 3 ],
      "sync vids #1, #2"      => [ 1, 2 ],    # space after comma still parsed
      "sync vids #10 #20 #30" => [ 10, 20, 30 ]
    }.each do |raw, ids|
      it "#{raw.inspect} → video_ids: #{ids.inspect}, channel_ids: []" do
        p = payload_of(raw, channel: "@all")
        expect(p["command"]).to eq("sync_videos")
        expect(p["video_ids"]).to   eq(ids)
        expect(p["channel_ids"]).to eq([])
      end
    end

    it "ids win — @pito scope is ignored; channel_ids: []" do
      p = payload_of("sync vids ##{SYNC_VID_ID}", channel: "@pito")
      expect(p["channel_ids"]).to eq([])
      expect(p["video_ids"]).to   eq([ SYNC_VID_ID ])
    end
  end

  # ── 5. Video noun + `only <ids>` legacy clause ───────────────────────────────
  #
  # ONLY_RE: \bonly\b\s+([\d,\s]+) — accepted as a legacy id form.
  # When present, behaves identically to the #id form.

  describe "video noun + `only <ids>` (legacy clause)" do
    {
      "sync videos only 1"      => [ 1 ],
      "sync videos only 1,2"    => [ 1, 2 ],
      "sync vids only 1,2,3"    => [ 1, 2, 3 ],
      "sync vid only 42"        => [ 42 ],
      "sync video only 1, 2"    => [ 1, 2 ],
      "sync videos only 10,20"  => [ 10, 20 ]
    }.each do |raw, ids|
      it "#{raw.inspect} → video_ids: #{ids.inspect}, channel_ids: []" do
        p = payload_of(raw)
        expect(p["command"]).to eq("sync_videos")
        expect(p["video_ids"]).to   eq(ids)
        expect(p["channel_ids"]).to eq([])
      end
    end
  end

  # ── 6. Video noun — unknown @handle → system error event ─────────────────────
  #
  # resolve_scope: Channel.find_by returns nil → emits a :system error event
  # (NOT a confirmation) — the handler returns a Result::Ok with :system kind.

  describe "video noun — unknown @handle → :system error, no confirmation" do
    before { allow(::Channel).to receive(:find_by).and_return(nil) }

    it "sync vids @ghost → :system error event, no command in payload" do
      result = call("sync vids", channel: "@ghost")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["command"]).to be_nil
    end

    %w[vid video videos].each do |noun|
      it "sync #{noun} @unknown → :system error (all video aliases)" do
        result = call("sync #{noun}", channel: "@unknown")
        expect(result.events.first[:kind]).to eq(:system)
      end
    end
  end

  # ── 7. Channels noun — bare, @all/blank scope ─────────────────────────────────
  #
  # Both CHANNEL_NOUN_FILLERS: channel + channels.
  # No `with` clause → command: sync_channel, with_items: [], channel_ids: []

  describe "channel noun — bare, @all/blank scope → sync_channel" do
    %w[channel channels].each do |noun|
      it "sync #{noun} (nil scope) → sync_channel, channel_ids: [], with_items: []" do
        p = payload_of("sync #{noun}")
        expect(p["command"]).to eq("sync_channel")
        expect(p["channel_ids"]).to eq([])
        expect(p["with_items"]).to  eq([])
      end

      it "sync #{noun} @all → sync_channel, channel_ids: [], with_items: []" do
        p = payload_of("sync #{noun}", channel: "@all")
        expect(p["command"]).to eq("sync_channel")
        expect(p["channel_ids"]).to eq([])
        expect(p["with_items"]).to  eq([])
      end
    end
  end

  # ── 8. Channels noun — @handle scope ─────────────────────────────────────────

  describe "channel noun — @handle scope → channel_ids: [resolved_id]" do
    %w[channel channels].each do |noun|
      it "sync #{noun} @pito → channel_ids: [#{SYNC_CHAN_ID}], with_items: []" do
        p = payload_of("sync #{noun}", channel: "@pito")
        expect(p["command"]).to eq("sync_channel")
        expect(p["channel_ids"]).to eq([ SYNC_CHAN_ID ])
        expect(p["with_items"]).to  eq([])
      end
    end
  end

  # ── 9. Channels with <videos-alias> — all four WITH_ITEMS_VOCAB tokens ────────
  #
  # WITH_ITEMS_VOCAB: "vid"|"vids"|"video"|"videos" → :videos
  # Any of these triggers ChannelVideosConfirmation (command: sync_channel_videos).

  describe "channels with <videos-alias> → sync_channel_videos, with_items: ['videos']" do
    %w[vid vids video videos].each do |alias_noun|
      it "sync channels with #{alias_noun} → sync_channel_videos, with_items: ['videos']" do
        p = payload_of("sync channels with #{alias_noun}")
        expect(p["command"]).to eq("sync_channel_videos")
        expect(p["with_items"]).to  eq([ "videos" ])
        expect(p["channel_ids"]).to eq([])
      end

      it "sync channel with #{alias_noun} (singular noun) → sync_channel_videos" do
        p = payload_of("sync channel with #{alias_noun}")
        expect(p["command"]).to eq("sync_channel_videos")
      end
    end

    it "sync channels with vids @pito → channel_ids: [#{SYNC_CHAN_ID}], sync_channel_videos" do
      p = payload_of("sync channels with vids", channel: "@pito")
      expect(p["command"]).to eq("sync_channel_videos")
      expect(p["channel_ids"]).to eq([ SYNC_CHAN_ID ])
      expect(p["with_items"]).to  eq([ "videos" ])
    end
  end

  # ── 10. Channels with unknown tokens — silently dropped ──────────────────────
  #
  # Unknown tokens are not in WITH_ITEMS_VOCAB → filter_map drops them.
  # Result depends on whether :videos survives after dropping unknowns.

  describe "channels with unknown items → dropped" do
    it "sync channels with analytics (unknown) → sync_channel, with_items: []" do
      p = payload_of("sync channels with analytics")
      expect(p["command"]).to eq("sync_channel")
      expect(p["with_items"]).to eq([])
    end

    it "sync channels with foo,bar (all unknown) → sync_channel, with_items: []" do
      p = payload_of("sync channels with foo,bar")
      expect(p["command"]).to eq("sync_channel")
      expect(p["with_items"]).to eq([])
    end

    it "sync channels with videos,analytics → keeps videos, drops analytics" do
      p = payload_of("sync channels with videos,analytics")
      expect(p["command"]).to eq("sync_channel_videos")
      expect(p["with_items"]).to eq([ "videos" ])
    end

    it "sync channels with analytics,videos → videos kept regardless of position" do
      p = payload_of("sync channels with analytics,videos")
      expect(p["command"]).to eq("sync_channel_videos")
      expect(p["with_items"]).to eq([ "videos" ])
    end

    it "sync channels with videos,foo,bar → unknown tokens stripped, :videos survives" do
      p = payload_of("sync channels with videos,foo,bar")
      expect(p["command"]).to eq("sync_channel_videos")
      expect(p["with_items"]).to eq([ "videos" ])
    end
  end

  # ── 11. Channels — unknown @handle → system error event ──────────────────────

  describe "channel noun — unknown @handle → :system error, no confirmation" do
    before { allow(::Channel).to receive(:find_by).and_return(nil) }

    it "sync channels @nope → :system error event" do
      result = call("sync channels", channel: "@nope")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "sync channel @nope → :system error event" do
      result = call("sync channel", channel: "@nope")
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "sync channels with videos @nope → :system error (error before with_items)" do
      result = call("sync channels with videos", channel: "@nope")
      expect(result.events.first[:kind]).to eq(:system)
    end
  end

  # ── 11b. Channels — inline @handle scopes to that channel ────────────────────
  #
  # `sync channel @handle` typed directly scopes to that one channel (overriding
  # the shift+tab scope) so an image-fallback click is self-contained. `@all`
  # inline is not a specific handle → all channels.

  describe "channel noun — inline @handle overrides shift+tab scope" do
    it "sync channel @pito (no shift+tab) → channel_ids: [#{SYNC_CHAN_ID}]" do
      p = payload_of("sync channel @pito")
      expect(p["command"]).to eq("sync_channel")
      expect(p["channel_ids"]).to eq([ SYNC_CHAN_ID ])
    end

    it "inline @pito beats a shift+tab @all scope" do
      p = payload_of("sync channel @pito", channel: "@all")
      expect(p["channel_ids"]).to eq([ SYNC_CHAN_ID ])
    end

    it "@all inline is not a specific handle → all channels ([])" do
      p = payload_of("sync channel @all")
      expect(p["channel_ids"]).to eq([])
    end
  end

  # ── 12. --flag forms — NOT recognized nouns ───────────────────────────────────
  #
  # Negative lookbehind (?<!-) in both channels_form? and videos_form? prevents
  # leading-dash variants from matching — they fall through to needs_ref.

  describe "--flag forms are NOT valid nouns → needs_ref Error" do
    %w[--videos --vid --vids --video --channels --channel].each do |flag|
      it "sync #{flag} → Result::Error (needs_ref)" do
        result = call("sync #{flag}")
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.sync.needs_ref")
      end
    end
  end

  # ── 13. Bare sync / unrecognized noun → needs_ref Error ──────────────────────
  #
  # `sync game` WITHOUT an `#id` is still ambiguous in free chat — game sync is
  # id-explicit (`sync game #id`, tested below) or reply-only (`#<handle> sync`
  # on a game card). Everything here falls through to needs_ref.

  describe "bare / unrecognized noun → needs_ref Error" do
    [
      "sync",
      "sync   ",
      "sync game",
      "sync game 5",
      "sync game elden ring",
      "sync games",
      "sync gamez",
      "sync foobar"
    ].each do |raw|
      it "#{raw.strip.inspect} → Result::Error (needs_ref)" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.sync.needs_ref")
      end
    end
  end

  # ── 13b. Direct game sync by id (sync game #id) ──────────────────────────────
  #
  # `sync game #id` re-syncs that one game from IGDB — the same confirmation the
  # `#<handle> sync` reply on a game card builds. Only the FIRST id is used
  # (game sync is single-target). No id → needs_ref (covered above).

  describe "game noun — direct id sync (sync game #id)" do
    it "sync game #3 → sync_game, game_id: #{SYNC_GAME_ID}" do
      p = payload_of("sync game #3")
      expect(p["command"]).to eq("sync_game")
      expect(p["game_id"]).to eq(SYNC_GAME_ID)
    end

    it "sync games #3 (plural noun) also syncs by id" do
      p = payload_of("sync games #3")
      expect(p["command"]).to eq("sync_game")
      expect(p["game_id"]).to eq(SYNC_GAME_ID)
    end

    it "uses only the FIRST id when several are given" do
      allow(::Game).to receive(:find_by).with(id: 3).and_return(game_double)
      call("sync game #3 #4")
      expect(::Game).to have_received(:find_by).with(id: 3)
    end

    it "returns needs_ref when the game id does not resolve" do
      allow(::Game).to receive(:find_by).and_return(nil)
      result = call("sync game #999")
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.sync.needs_ref")
    end
  end

  # ── 14. Follow-up: video_detail → sync_videos for the source video ────────────
  #
  # resolve_target reads video_id from the source event's payload and calls
  # Video.find_by(id:). The handler guards with video.is_a?(::Video).

  describe "follow-up: video_detail → sync_videos" do
    let(:source_payload) { { "video_id" => SYNC_VID_ID, "reply_target" => "video_detail" } }

    it "emits :confirmation, command: sync_videos, video_ids: [#{SYNC_VID_ID}], channel_ids: []" do
      result = sync_follow_up(source_payload)
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to      eq("sync_videos")
      expect(event[:payload]["video_ids"]).to    eq([ SYNC_VID_ID ])
      expect(event[:payload]["channel_ids"]).to  eq([])
    end

    it "trailing args in rest are ignored — still targets the source video" do
      result = sync_follow_up(source_payload, rest: "whatever extra args")
      expect(result.events.first[:payload]["video_ids"]).to eq([ SYNC_VID_ID ])
    end

    it "rest: 'sync' (echo of verb) is also ignored" do
      result = sync_follow_up(source_payload, rest: "sync")
      expect(result.events.first[:payload]["video_ids"]).to eq([ SYNC_VID_ID ])
    end

    it "Video.find_by returns nil → needs_ref Error" do
      allow(::Video).to receive(:find_by).and_return(nil)
      result = sync_follow_up(source_payload)
      expect(result).to be_a(Pito::Chat::Result::Error)
    end
  end

  # ── 15. Follow-up: channel_detail → sync_channel for the source channel ────────
  #
  # resolve_target reads channel_id from the payload, finds ::Channel.
  # The builder receives ch.handle.presence || ch.title.to_s as scope_label.

  describe "follow-up: channel_detail → sync_channel" do
    let(:source_payload) { { "channel_id" => SYNC_CHAN_ID, "reply_target" => "channel_detail" } }

    it "emits :confirmation, command: sync_channel, channel_ids: [#{SYNC_CHAN_ID}], with_items: []" do
      result = sync_follow_up(source_payload)
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to      eq("sync_channel")
      expect(event[:payload]["channel_ids"]).to  eq([ SYNC_CHAN_ID ])
      expect(event[:payload]["with_items"]).to   eq([])
    end

    it "trailing args in rest are ignored — still targets the source channel" do
      result = sync_follow_up(source_payload, rest: "with videos")
      expect(result.events.first[:payload]["channel_ids"]).to eq([ SYNC_CHAN_ID ])
    end

    it "Channel.find_by returns nil → needs_ref Error" do
      allow(::Channel).to receive(:find_by).and_return(nil)
      result = sync_follow_up(source_payload)
      expect(result).to be_a(Pito::Chat::Result::Error)
    end
  end

  # ── 16. Follow-up: game_detail → sync_game for the source game ───────────────
  #
  # resolve_target reads game_id from the payload. GameConfirmation receives the
  # game object (not a scope label or ids array).

  describe "follow-up: game_detail → sync_game" do
    let(:source_payload) { { "game_id" => SYNC_GAME_ID, "reply_target" => "game_detail" } }

    it "emits :confirmation, command: sync_game, game_id: #{SYNC_GAME_ID}" do
      result = sync_follow_up(source_payload)
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["command"]).to   eq("sync_game")
      expect(event[:payload]["game_id"]).to   eq(SYNC_GAME_ID)
    end

    it "trailing args in rest are ignored — still targets the source game" do
      result = sync_follow_up(source_payload, rest: "some extra text")
      expect(result.events.first[:payload]["game_id"]).to eq(SYNC_GAME_ID)
    end

    it "Game.find_by returns nil → needs_ref Error" do
      allow(::Game).to receive(:find_by).and_return(nil)
      result = sync_follow_up(source_payload)
      expect(result).to be_a(Pito::Chat::Result::Error)
    end
  end

  # ── 17. Follow-up: unknown reply_target → needs_ref Error ─────────────────────
  #
  # handle_follow_up has an else → needs_ref for any unrecognized reply_target.
  # "confirmation", list targets, and arbitrary strings all fall here.

  describe "follow-up: unknown / unsupported reply_target → needs_ref Error" do
    [
      "confirmation",
      "video_list",
      "game_list",
      "channel_list",
      "something_else",
      ""
    ].each do |target|
      it "reply_target #{target.inspect} → Result::Error" do
        result = sync_follow_up({ "reply_target" => target })
        expect(result).to be_a(Pito::Chat::Result::Error)
      end
    end
  end

  # ── 18. Registry contract — sync is a declared action ─────────────────────────
  #
  # ToolDelegator gates follow-up routing by checking
  # Pito::FollowUp::Registry.actions_for(reply_target). These assertions verify
  # the contract: `#<handle> sync` is reachable on exactly these three targets.

  describe "Registry: sync declared as follow-up action on detail-card targets" do
    before { Pito::FollowUp::Registry.register_all! }

    it "video_detail declares 'sync'" do
      expect(Pito::FollowUp::Registry.actions_for("video_detail")).to include("sync")
    end

    it "channel_detail declares 'sync'" do
      expect(Pito::FollowUp::Registry.actions_for("channel_detail")).to include("sync")
    end

    it "game_detail declares 'sync'" do
      expect(Pito::FollowUp::Registry.actions_for("game_detail")).to include("sync")
    end
  end
end
