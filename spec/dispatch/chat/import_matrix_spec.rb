# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `import` (recognition only, DB mocked) ──────────────────
#
# RULE: every kwarg combination recognized — no exception. Tests what the handler
# UNDERSTANDS from a raw input, not data persistence. All DB lookups are stubbed
# so the handler resolves records without touching the database.
#
# Subject: Pito::Chat::Handlers::Import
#          (app/services/pito/chat/handlers/import.rb)
#
# Three dispatch branches (evaluated in order):
#
#   1. raw matches /\bgames?\b/i  → handle_import_game(raw)
#        Opens the IGDB import sidebar.
#        → Result::Ok, events: [{ kind: :system, payload: {
#             sidebar_open: "games_import",
#             prefill:      <title extracted after stripping "import game[s] ">,
#             text:         I18n.t("pito.slash.games.import.opening") } }]
#
#   2. raw matches /\b(?:vid|video)s?\b/i → handle_import_videos(raw)
#        Alias for `sync videos`. Resolves channel scope, emits a sync confirmation.
#        Scope priority: `for @handle` clause in raw > shift+tab `channel:` kwarg >
#                        @all / blank → "all channels"
#        → Result::Ok, events: [{ kind: :confirmation, payload: {
#             "command" => "sync_videos", "channel_ids" => <resolved ids> } }]
#        Unknown handle:
#        → Result::Ok, events: [{ kind: :system, payload: <error text> }]
#
#   3. Neither noun matched
#        → Result::Error (message_key: "pito.chat.import.usage_hint", message_args: {})
#
# Title extraction (game branch):
#   parse_import_game_title: strip raw, then sub /\Aimport\s+games?\s*/i → strip.
#
# FOR_HANDLE_RE: /\bfor\s+(@\S+)/i — `for @handle` clause overrides shift+tab.
#
# normalized_handle: strips leading `@+` before Channel.find_by call.
RSpec.describe "Dispatch matrix — import (recognition, DB mocked)", type: :dispatch do
  IMPORT_CH_ID = 11

  let(:channel_double) { double("Channel", id: IMPORT_CH_ID, handle: "@pito") }
  let(:conversation)   { double("Conversation", id: 9) }

  # Default stubs: Channel lookup succeeds; HandleGenerator (used by
  # Pito::FollowUp.make_followupable! inside the builder) is short-circuited.
  before do
    allow(Pito::HandleGenerator).to receive(:call).and_return("mock-handle")
    allow(::Channel).to receive(:find_by).and_return(channel_double)
  end

  # Build and invoke the Import handler from a raw input string.
  # `channel:` simulates the shift+tab channel scope (@handle, @all, nil, "").
  def call(raw, channel: nil)
    Pito::Chat::Handlers::Import.new(
      message:      instance_double(Pito::Chat::Message, raw: raw),
      conversation: conversation,
      channel:      channel
    ).call
  end

  # ── Bare `import` / unrecognized noun → Result::Error (usage hint) ─────────
  #
  # None of the branch regexes match, so the handler falls to the else branch
  # and returns Result::Error with the usage hint i18n key.
  describe "bare / unknown noun → Result::Error (usage_hint)" do
    {
      "import"             => "bare verb, no noun",
      "import   "          => "bare verb with trailing spaces only",
      "import something"   => "unknown noun token",
      "import channel"     => "channel noun (not game or vid/video)",
      "import channels"    => "plural channel noun — still not a game or video",
      "import foobar"      => "arbitrary unknown token",
      "import sync"        => "adjacent verb word, not a recognized noun",
      "import 123"         => "bare numeric token, no noun",
      "import #5"          => "hash-prefixed id, no noun",
      "import all"         => "scope word only, no noun",
      "import for @pito"   => "for clause only, no noun (video never matched)"
    }.each do |raw, desc|
      it "#{raw.inspect} (#{desc}) → Result::Error with usage_hint key" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.import.usage_hint")
        expect(result.message_args).to eq({})
      end
    end
  end

  # ── import game[s] (no title) → :system, sidebar_open, prefill: "" ─────────
  #
  # When the raw ends at the game noun (with optional trailing whitespace),
  # parse_import_game_title strips "import game[s] " and returns "".
  describe "import game[s] bare (no title) → :system, sidebar_open: 'games_import', prefill: ''" do
    {
      "import game"   => "singular, default case",
      "import games"  => "plural, default case",
      "import GAME"   => "uppercase singular",
      "import GAMES"  => "uppercase plural",
      "import Game"   => "title-case singular",
      "import Games"  => "title-case plural",
      "import game "  => "trailing single space (stripped)",
      "import game  " => "trailing multiple spaces (stripped)",
      "import games " => "plural with trailing space"
    }.each do |raw, desc|
      it "#{raw.inspect} (#{desc}) → :system, prefill: ''" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event = result.events.first
        expect(event[:kind]).to eq(:system)
        expect(event[:payload][:sidebar_open]).to eq("games_import")
        expect(event[:payload][:prefill]).to eq("")
      end
    end
  end

  # ── import game[s] <title> → :system, sidebar_open, prefill: <title> ────────
  #
  # Everything after stripping /\Aimport\s+games?\s*/i and final .strip becomes
  # the prefill — even multi-word, punctuated, or mixed-case titles.
  describe "import game[s] <title> → :system, prefill: <extracted title>" do
    {
      "import game Elden Ring"                      => "Elden Ring",
      "import games Hollow Knight"                  => "Hollow Knight",
      "import game Elden Ring: Shadow of the Erdtree" => "Elden Ring: Shadow of the Erdtree",
      "import GAME Elden Ring"                      => "Elden Ring",
      "import GAMES something"                      => "something",
      "import game  Elden Ring  "                   => "Elden Ring",   # extra inner/outer spaces
      "import game a"                               => "a",             # single-char title
      "import game The Legend of Zelda"             => "The Legend of Zelda",
      "import game dark souls 3"                    => "dark souls 3",
      "import games a b c d e"                      => "a b c d e",    # multi-word title
      "import game Disco Elysium - The Final Cut"   => "Disco Elysium - The Final Cut",
      "import game 123"                             => "123",           # numeric title
      "import game #5"                              => "#5",            # hash-ref as title
      "import games   leading spaces title"         => "leading spaces title"
    }.each do |raw, expected_prefill|
      it "#{raw.inspect} → prefill: #{expected_prefill.inspect}" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event = result.events.first
        expect(event[:kind]).to eq(:system)
        expect(event[:payload][:sidebar_open]).to eq("games_import")
        expect(event[:payload][:prefill]).to eq(expected_prefill)
      end
    end
  end

  # ── game path: :system payload includes opening text from i18n ───────────────
  describe "game path :system payload includes the sidebar opening text" do
    it "text key resolves to the I18n value for 'pito.slash.games.import.opening'" do
      result = call("import game")
      text   = result.events.first[:payload][:text]
      expect(text).to eq(I18n.t("pito.slash.games.import.opening"))
      expect(text).to be_present
    end

    it "opening text is the same regardless of whether a title is supplied" do
      text_bare   = call("import game").events.first[:payload][:text]
      text_titled = call("import game Elden Ring").events.first[:payload][:text]
      expect(text_bare).to eq(text_titled)
    end
  end

  # ── game detection priority — game branch fires first if raw has "game" ──────
  #
  # When raw contains both a game noun AND a video noun, the game branch wins
  # because the if/elsif checks game before video.
  describe "game branch fires first when raw contains both 'game' and video noun" do
    it "'import game videos' → game branch: sidebar_open, prefill: 'videos'" do
      result = call("import game videos")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload][:sidebar_open]).to eq("games_import")
      expect(event[:payload][:prefill]).to eq("videos")
    end

    it "'import game vids' → game branch: prefill: 'vids'" do
      result = call("import game vids")
      event = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload][:prefill]).to eq("vids")
    end
  end

  # ── game path: Channel is never consulted (scope irrelevant) ─────────────────
  describe "game path never consults Channel (channel scope is irrelevant)" do
    it "channel: '@pito' → still opens sidebar (no DB call for channel)" do
      expect(::Channel).not_to receive(:find_by)
      result = call("import game Elden Ring", channel: "@pito")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload][:sidebar_open]).to eq("games_import")
    end

    it "channel: nil → still opens sidebar" do
      expect(::Channel).not_to receive(:find_by)
      result = call("import game", channel: nil)
      expect(result.events.first[:kind]).to eq(:system)
    end
  end

  # ── import vid[eo][s] all four noun forms → :confirmation ────────────────────
  #
  # The video regex /\b(?:vid|video)s?\b/i matches all four canonical spellings.
  describe "all four video noun forms → :confirmation, command: 'sync_videos'" do
    {
      "import vid"    => "singular vid",
      "import vids"   => "plural vids",
      "import video"  => "singular video",
      "import videos" => "plural videos"
    }.each do |raw, desc|
      it "#{raw.inspect} (#{desc}), channel: nil → :confirmation, channel_ids: []" do
        result = call(raw, channel: nil)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event = result.events.first
        expect(event[:kind]).to eq(:confirmation)
        expect(event[:payload]["command"]).to eq("sync_videos")
        expect(event[:payload]["channel_ids"]).to eq([])
      end
    end
  end

  # ── video noun is case-insensitive ────────────────────────────────────────────
  describe "video noun matching is case-insensitive (regex flag /i)" do
    {
      "import VID"    => "uppercase VID",
      "import VIDS"   => "uppercase VIDS",
      "import VIDEO"  => "uppercase VIDEO",
      "import VIDEOS" => "uppercase VIDEOS",
      "import Vid"    => "title-case Vid",
      "import Vids"   => "title-case Vids",
      "import Video"  => "title-case Video",
      "import Videos" => "title-case Videos",
      "import viD"    => "mixed-case viD",
      "import viDeOs" => "mixed-case viDeOs"
    }.each do |raw, desc|
      it "#{raw.inspect} (#{desc}) → :confirmation" do
        result = call(raw, channel: nil)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:confirmation)
        expect(result.events.first[:payload]["command"]).to eq("sync_videos")
      end
    end
  end

  # ── shift+tab scope @all / nil / blank → all channels ────────────────────────
  #
  # resolved_channel_handle returns nil when channel: is nil, "", or "@all"
  # (case-insensitive). Nil handle → scope "all channels", channel_ids: [].
  describe "shift+tab scope @all / nil / blank → all channels (channel_ids: [])" do
    [ nil, "", "@all", "@ALL", "@All", "@aLL" ].each do |ch_scope|
      it "import videos, channel: #{ch_scope.inspect} → channel_ids: []" do
        result = call("import videos", channel: ch_scope)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:confirmation)
        expect(result.events.first[:payload]["channel_ids"]).to eq([])
        expect(result.events.first[:payload]["scope_label"]).to eq("all channels")
      end
    end

    it "all four noun forms produce channel_ids: [] with channel: nil" do
      %w[vid vids video videos].each do |noun|
        result = call("import #{noun}", channel: nil)
        expect(result.events.first[:payload]["channel_ids"]).to eq([])
      end
    end
  end

  # ── shift+tab @handle → specific channel ──────────────────────────────────────
  #
  # resolved_channel_handle returns the handle string when channel: is a non-@all value.
  # Channel.find_by is called with the normalized handle (no leading @).
  describe "shift+tab @handle → specific channel (channel_ids: [IMPORT_CH_ID])" do
    it "import videos, channel: '@pito' → channel_ids: [IMPORT_CH_ID]" do
      result = call("import videos", channel: "@pito")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["channel_ids"]).to eq([ IMPORT_CH_ID ])
    end

    it "all four noun forms obey the shift+tab @handle" do
      %w[vid vids video videos].each do |noun|
        result = call("import #{noun}", channel: "@pito")
        expect(result.events.first[:payload]["channel_ids"]).to eq([ IMPORT_CH_ID ])
      end
    end
  end

  # ── `for @handle` clause in raw overrides shift+tab scope ─────────────────────
  #
  # FOR_HANDLE_RE = /\bfor\s+(@\S+)/i extracts the handle from raw text.
  # It takes priority over the shift+tab channel: kwarg via the `||` in resolve_scope.
  describe "'for @handle' clause in raw overrides the shift+tab channel scope" do
    it "import videos for @pito, channel: nil → resolves @pito, channel_ids: [IMPORT_CH_ID]" do
      result = call("import videos for @pito", channel: nil)
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
      expect(event[:payload]["channel_ids"]).to eq([ IMPORT_CH_ID ])
    end

    it "import videos for @pito, channel: '@all' → for clause wins, channel_ids: [IMPORT_CH_ID]" do
      result = call("import videos for @pito", channel: "@all")
      expect(result.events.first[:payload]["channel_ids"]).to eq([ IMPORT_CH_ID ])
    end

    it "import videos for @pito, channel: '@other' → for clause wins over shift+tab" do
      result = call("import videos for @pito", channel: "@other")
      expect(result.events.first[:payload]["channel_ids"]).to eq([ IMPORT_CH_ID ])
    end

    it "all four noun forms respect the 'for @handle' clause" do
      %w[vid vids video videos].each do |noun|
        result = call("import #{noun} for @pito", channel: nil)
        expect(result.events.first[:kind]).to eq(:confirmation)
        expect(result.events.first[:payload]["channel_ids"]).to eq([ IMPORT_CH_ID ])
      end
    end

    it "'FOR' is case-insensitive in the for clause regex" do
      result = call("import videos FOR @pito", channel: nil)
      expect(result.events.first[:payload]["channel_ids"]).to eq([ IMPORT_CH_ID ])
    end

    it "'for' with multiple spaces before @handle still matches" do
      result = call("import videos for  @pito", channel: nil)
      expect(result.events.first[:payload]["channel_ids"]).to eq([ IMPORT_CH_ID ])
    end
  end

  # ── Channel.find_by: handle normalization (leading @ stripped) ───────────────
  #
  # normalized_handle strips /\A@+/ before the find_by call. This is verified for
  # both the shift+tab path and the for-clause path.
  describe "Channel.find_by is called with the normalized handle (leading @ stripped)" do
    it "shift+tab '@pito' → find_by called with 'pito', not '@pito'" do
      expect(::Channel).to receive(:find_by)
        .with("LOWER(REPLACE(handle, '@', '')) = LOWER(?)", "pito")
        .and_return(channel_double)
      call("import videos", channel: "@pito")
    end

    it "'for @pito' clause → find_by called with 'pito'" do
      expect(::Channel).to receive(:find_by)
        .with("LOWER(REPLACE(handle, '@', '')) = LOWER(?)", "pito")
        .and_return(channel_double)
      call("import videos for @pito", channel: nil)
    end

    it "Channel.find_by is never called when scope is nil / @all" do
      expect(::Channel).not_to receive(:find_by)
      call("import videos", channel: nil)
    end

    it "Channel.find_by is never called when scope is @all" do
      expect(::Channel).not_to receive(:find_by)
      call("import videos", channel: "@all")
    end
  end

  # ── Unknown channel handle → Result::Ok with :system event ───────────────────
  #
  # When Channel.find_by returns nil, resolve_scope returns [nil, nil, error_result].
  # The handler emits a :system event (not :confirmation).
  describe "unknown channel handle → Result::Ok :system event (not :confirmation)" do
    before { allow(::Channel).to receive(:find_by).and_return(nil) }

    it "shift+tab @unknown → :system event, not :confirmation" do
      result = call("import videos", channel: "@unknown")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload]).not_to include("command")
    end

    it "'for @unknown' clause → :system event" do
      result = call("import videos for @unknown", channel: nil)
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "all four noun forms emit :system on not-found shift+tab handle" do
      %w[vid vids video videos].each do |noun|
        result = call("import #{noun}", channel: "@nope")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    it "all four noun forms emit :system on not-found 'for @handle' clause" do
      %w[vid vids video videos].each do |noun|
        result = call("import #{noun} for @nope", channel: nil)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end
  end

  # ── Confirmation payload shape (all channels path) ────────────────────────────
  describe "confirmation payload shape — all channels scope" do
    it "payload includes all expected keys with correct values" do
      result  = call("import videos", channel: nil)
      payload = result.events.first[:payload]
      aggregate_failures do
        expect(payload["command"]).to eq("sync_videos")
        expect(payload["scope_label"]).to eq("all channels")
        expect(payload["channel_ids"]).to eq([])
        expect(payload["video_ids"]).to eq([])
        expect(payload["html"]).to eq(false)
        expect(payload["conversation_id"]).to eq(conversation.id)
      end
    end

    it "payload is follow-up-able (reply_handle + reply_target stamped by make_followupable!)" do
      result  = call("import videos", channel: nil)
      payload = result.events.first[:payload]
      aggregate_failures do
        expect(payload["reply_handle"]).to eq("mock-handle")
        expect(payload["reply_target"]).to eq("confirmation")
      end
    end
  end

  # ── Confirmation payload shape (specific channel path) ────────────────────────
  describe "confirmation payload shape — specific channel scope" do
    it "payload scope_label is the channel handle, channel_ids contains the channel id" do
      result  = call("import videos", channel: "@pito")
      payload = result.events.first[:payload]
      aggregate_failures do
        expect(payload["command"]).to eq("sync_videos")
        expect(payload["scope_label"]).to eq(channel_double.handle) # "@pito"
        expect(payload["channel_ids"]).to eq([ IMPORT_CH_ID ])
        expect(payload["video_ids"]).to eq([])
        expect(payload["html"]).to eq(false)
        expect(payload["conversation_id"]).to eq(conversation.id)
      end
    end

    it "for-clause path produces the same payload shape" do
      result  = call("import videos for @pito", channel: nil)
      payload = result.events.first[:payload]
      expect(payload["command"]).to eq("sync_videos")
      expect(payload["channel_ids"]).to eq([ IMPORT_CH_ID ])
    end
  end

  # ── Result::Ok consume: default (true) ────────────────────────────────────────
  describe "Result::Ok consume: flag" do
    it "import game → consume: true (default)" do
      result = call("import game")
      expect(result.consume).to eq(true)
    end

    it "import videos (all channels) → consume: true" do
      result = call("import videos", channel: nil)
      expect(result.consume).to eq(true)
    end

    it "import videos (specific channel) → consume: true" do
      result = call("import videos", channel: "@pito")
      expect(result.consume).to eq(true)
    end
  end

  # ── Single event per result ───────────────────────────────────────────────────
  describe "exactly one event per Result::Ok" do
    it "import game → exactly 1 event" do
      expect(call("import game").events.size).to eq(1)
    end

    it "import videos (all channels) → exactly 1 event" do
      expect(call("import videos", channel: nil).events.size).to eq(1)
    end

    it "import videos (specific channel) → exactly 1 event" do
      expect(call("import videos", channel: "@pito").events.size).to eq(1)
    end
  end
end
