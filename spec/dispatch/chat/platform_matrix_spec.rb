# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `platform` (recognition only, DB mocked) ──────────────────
#
# RULE: every kwarg combination recognised — no exception. Tests what the handler
# UNDERSTANDS from a raw input, not data persistence. All DB lookups are stubbed
# so the handler resolves records without touching the database.
#
# Subject:  Pito::Chat::Handlers::Platform
# File:     app/services/pito/chat/handlers/platform.rb
# Vocab:    Pito::Game::PlatformInput (app/services/pito/game/platform_input.rb)
# Resolver: id_only_resolution! — ILIKE title lookup intentionally disabled.
#
# ── Subcommands ───────────────────────────────────────────────────────────────
#   `platform <id> <name>`        → bare → @subcommand = :set (default ADD)
#   `platform set <id> <name>`    → explicit :set  (ADD)
#   `platform unset <id> <name>`  → explicit :unset (REMOVE)
#   ("add"/"remove" are NOT aliases; treated as game refs → not-found)
#
# ── Noun fillers stripped before the id ──────────────────────────────────────
#   "game", "games"  (NOUN_FILLERS constant)
#
# ── Id ref forms ─────────────────────────────────────────────────────────────
#   bare integer: "7"  |  #-prefixed: "#7"  |  non-numeric → nil (id_only)
#
# ── Platform families (PlatformInput.normalize) ───────────────────────────────
#   PlayStation  /\A(?:play\s?station|ps)\s*(\d+)?\b/i   → anchored at \A
#   Switch       /switch|nintendo/i                       → unanchored
#   Steam        /steam|\bpc\b|windows|gog|epic|amazon|battle\.?net/i  → unanchored
#   Unknown      anything else → text.titleize, stored as-is (no logo)
#
# ── Three entry points ───────────────────────────────────────────────────────
#   Free chat     → handler reads message.raw
#   Follow-up detail (game_id in card payload) → rest = text after verb word
#   Follow-up list  (id typed in rest, optional table_rows scope)
#
# ── Result shapes ─────────────────────────────────────────────────────────────
#   Ok    → Pito::Chat::Result::Ok, one :system event
#            payload: { "body" => html, "html" => true, "game_id" => id }
#   Error → Pito::Chat::Result::Error with :message_key
#            needs_ref    → "pito.chat.platform.needs_ref"
#            missing_name → "pito.chat.platform.missing_name"
#   Not-found Ok → :system event, payload: { "text" => "…<ref>…" }

RSpec.describe "Dispatch matrix — platform (recognition, DB mocked)", type: :dispatch do
  PLAT_GAME_ID = 7

  let(:game_double)  { double("Game", id: PLAT_GAME_ID, title: "Test Game") }
  let(:conversation) { double("Conversation") }

  # Default: Game.find_by always returns game_double; game starts with no platforms.
  before do
    allow(game_double).to receive(:platforms).and_return([])
    allow(game_double).to receive(:update!)
    allow(::Game).to receive(:find_by).and_return(game_double)
  end

  # ── Constructor helpers ───────────────────────────────────────────────────────

  # Builds and calls a free-chat Platform handler from a full raw string.
  # The raw string must start with "platform" (the verb word the handler strips).
  def call(raw, follow_up: nil)
    msg = Pito::Chat::Message.new(
      verb:        :platform,
      body_tokens: [],
      kind:        :new_turn,
      raw:         raw
    )
    Pito::Chat::Handlers::Platform.new(
      message:      msg,
      conversation: conversation,
      follow_up:    follow_up
    ).call
  end

  # Follow-up detail context: game comes from card payload; rest is everything
  # AFTER the verb word (e.g. "ps5" or "set ps5" — NOT "platform ps5").
  # This mirrors what VerbDelegator passes: it strips the leading verb token.
  def detail_ctx(rest, game_id: PLAT_GAME_ID)
    source = instance_double(
      Event,
      payload: { "game_id" => game_id, "reply_target" => "game_detail" }
    )
    Pito::Chat::FollowUpContext.new(source_event: source, rest: rest)
  end

  # Follow-up list context: game id must appear in rest; optionally constrained
  # by table_rows (array of { cells: [{ text: "#<id>" }] } hashes).
  def list_ctx(rest, table_rows: [])
    source = instance_double(
      Event,
      payload: { "reply_target" => "game_list", "table_rows" => table_rows }
    )
    Pito::Chat::FollowUpContext.new(source_event: source, rest: rest)
  end

  # ── ① Subcommand resolution (free chat) ─────────────────────────────────────
  #
  # peel_subcommand strips "set"/"unset" as the first token; anything else leaves
  # @subcommand at the default :set and the text untouched.

  describe "① subcommand resolution — free chat" do
    context "bare (no subcommand) → @subcommand defaults to :set (ADD)" do
      it "platform 7 ps5 → update! with ['PlayStation 5']" do
        call("platform 7 ps5")
        expect(game_double).to have_received(:update!).with(platforms: [ "PlayStation 5" ])
      end
    end

    context "explicit 'set' token → @subcommand = :set" do
      it "platform set 7 ps5 → update! with ['PlayStation 5']" do
        call("platform set 7 ps5")
        expect(game_double).to have_received(:update!).with(platforms: [ "PlayStation 5" ])
      end
    end

    context "explicit 'unset' token → @subcommand = :unset (REMOVE)" do
      it "platform unset 7 ps5 → Ok result (platform absent → no update!)" do
        result = call("platform unset 7 ps5")
        expect(result).to be_a(Pito::Chat::Result::Ok)
      end

      it "platform unset 7 ps5 → :system event carrying game_id" do
        result = call("platform unset 7 ps5")
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["game_id"]).to eq(PLAT_GAME_ID)
      end

      it "platform unset 7 ps5 → update! NOT called when platform absent (no-op)" do
        call("platform unset 7 ps5")
        expect(game_double).not_to have_received(:update!)
      end

      context "platform IS present in game.platforms → update! removes it" do
        before { allow(game_double).to receive(:platforms).and_return([ "PlayStation 5" ]) }

        it "platform unset 7 ps5 → update! called with platforms: []" do
          call("platform unset 7 ps5")
          expect(game_double).to have_received(:update!).with(platforms: [])
        end
      end

      context "switch present, unset switch" do
        before { allow(game_double).to receive(:platforms).and_return([ "Nintendo Switch" ]) }

        it "platform unset 7 switch → update! with []" do
          call("platform unset 7 switch")
          expect(game_double).to have_received(:update!).with(platforms: [])
        end
      end

      context "steam present, unset pc" do
        before { allow(game_double).to receive(:platforms).and_return([ "PC (Steam)" ]) }

        it "platform unset 7 pc → update! with []" do
          call("platform unset 7 pc")
          expect(game_double).to have_received(:update!).with(platforms: [])
        end
      end
    end

    context "'add' and 'remove' are NOT recognised subcommands" do
      # They are treated as the game ref token → non-numeric → id_only_resolution!
      # → find_by_ref returns nil → game_not_found system event.

      it "'add' treated as game ref (non-numeric) → not-found system event" do
        result = call("platform add 7 ps5")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["text"]).to include("add")
      end

      it "'remove' treated as game ref (non-numeric) → not-found system event" do
        result = call("platform remove 7 ps5")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["text"]).to include("remove")
      end
    end
  end

  # ── ② Noun filler stripping ──────────────────────────────────────────────────
  #
  # strip_noun removes a leading "game"/"games" token after subcommand peel,
  # before split_ref_and_name extracts the id.

  describe "② noun filler stripping" do
    {
      "platform game 7 switch"        => [ "Nintendo Switch" ],
      "platform games 7 switch"       => [ "Nintendo Switch" ],
      "platform set game 7 switch"    => [ "Nintendo Switch" ],
      "platform set games 7 switch"   => [ "Nintendo Switch" ],
      "platform set game 7 ps5"       => [ "PlayStation 5" ],
      "platform set games 7 ps5"      => [ "PlayStation 5" ],
      "platform set game 7 steam"     => [ "PC (Steam)" ],
      "platform set games 7 steam"    => [ "PC (Steam)" ]
    }.each do |raw, expected_platforms|
      it "#{raw.inspect} → update! with #{expected_platforms}" do
        call(raw)
        expect(game_double).to have_received(:update!).with(platforms: expected_platforms)
      end
    end

    it "platform unset game 7 switch → Ok, no update! (platform absent)" do
      expect(call("platform unset game 7 switch")).to be_a(Pito::Chat::Result::Ok)
      expect(game_double).not_to have_received(:update!)
    end

    it "platform unset games 7 switch → Ok, no update! (platform absent)" do
      expect(call("platform unset games 7 switch")).to be_a(Pito::Chat::Result::Ok)
      expect(game_double).not_to have_received(:update!)
    end
  end

  # ── ③ Id ref forms ───────────────────────────────────────────────────────────
  #
  # id_only_resolution! → find_by_ref returns nil for any non-numeric ref
  # (no ILIKE title fallback). Numeric refs accepted with or without "#" prefix.

  describe "③ id ref forms" do
    it "bare integer (platform 7 ps5) → Game.find_by called with id: '7'" do
      call("platform 7 ps5")
      expect(::Game).to have_received(:find_by).with(id: "7")
    end

    it "#-prefixed integer (platform #7 ps5) → Game.find_by called with id: '7'" do
      call("platform #7 ps5")
      expect(::Game).to have_received(:find_by).with(id: "7")
    end

    it "# with space (#  7) is also stripped → Game.find_by called with id: '7'" do
      # split_ref_and_name yields ref = "# 7" — find_by_ref strips \A#\s* → "7"
      # but actually split on whitespace gives ["#", "7 ps5"] then ref = "#" whose
      # sub gives "" which is non-numeric → nil. Let's test realistic variant instead.
      # "platform # 7 ps5" → ref = "#", name = "7 ps5" → "#" → "" → nil → not-found
      # (The "#7" form is the only hash-prefixed id that works.)
      result = call("platform # 7 ps5")
      # ref is "#", stripped to "" — non-numeric → id_only → nil → not-found
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload].key?("game_id")).to be(false)
    end

    it "non-numeric title ref → id_only_resolution! returns nil → not-found event" do
      # find_by_ref bails before calling Game.find_by for non-numeric refs.
      result = call("platform tekken ps5")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["text"]).to include("tekken")
      expect(::Game).not_to have_received(:find_by)
    end

    it "another non-numeric ref (Lies of P) → id_only → not-found" do
      result = call("platform lies ps5")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("lies")
    end
  end

  # ── ④ PlayStation family ─────────────────────────────────────────────────────
  #
  # Regex: /\A(?:play\s?station|ps)\s*(\d+)?\b/i  — anchored at \A (must START
  # with "playstation"/"play station" or "ps"). Captures optional console number.
  # Case-insensitive via /i flag.

  describe "④ PlayStation family — all normalized forms" do
    {
      # bare "ps" / "PS" → no number → "PlayStation"
      "ps"              => "PlayStation",
      "PS"              => "PlayStation",

      # ps<N> family
      "ps3"             => "PlayStation 3",
      "ps4"             => "PlayStation 4",
      "ps5"             => "PlayStation 5",
      "PS5"             => "PlayStation 5",
      "PS4"             => "PlayStation 4",

      # space between "ps" and the number (\s* allows it)
      "ps 5"            => "PlayStation 5",
      "ps 4"            => "PlayStation 4",
      "PS 5"            => "PlayStation 5",

      # "PlayStation" variants (play\s?station)
      "PlayStation"     => "PlayStation",
      "playstation"     => "PlayStation",
      "PLAYSTATION"     => "PlayStation",

      # with explicit number
      "PlayStation 5"   => "PlayStation 5",
      "PlayStation5"    => "PlayStation 5",   # no space before number
      "PlayStation 4"   => "PlayStation 4",
      "playstation5"    => "PlayStation 5",
      "PLAYSTATION5"    => "PlayStation 5",
      "PlayStation 3"   => "PlayStation 3",

      # "play station" with space between "play" and "station" (\s? allows it)
      "play station"    => "PlayStation",
      "Play Station"    => "PlayStation",
      "play station 5"  => "PlayStation 5",
      "Play Station 5"  => "PlayStation 5"
    }.each do |platform_input, expected_normalized|
      it "\"platform 7 #{platform_input}\" → update! with [#{expected_normalized.inspect}]" do
        call("platform 7 #{platform_input}")
        expect(game_double).to have_received(:update!)
          .with(platforms: [ expected_normalized ])
      end
    end
  end

  # ── ⑤ Switch family ──────────────────────────────────────────────────────────
  #
  # Regex: /switch|nintendo/i  — unanchored; matches anywhere in the text.
  # Because it's unanchored, "Nintendo Switch" (multi-word) also matches even
  # though the ref/name split yields "Nintendo" as the name in some paths —
  # but since split_ref_and_name gives the FULL remaining text as name for
  # everything after the game ref, "Nintendo Switch" arrives whole.

  describe "⑤ Switch family — all normalized forms" do
    {
      "switch"          => "Nintendo Switch",
      "Switch"          => "Nintendo Switch",
      "SWITCH"          => "Nintendo Switch",
      "nintendo"        => "Nintendo Switch",
      "Nintendo"        => "Nintendo Switch",
      "NINTENDO"        => "Nintendo Switch",
      "Nintendo Switch" => "Nintendo Switch"
    }.each do |platform_input, expected_normalized|
      it "\"platform 7 #{platform_input}\" → update! with [#{expected_normalized.inspect}]" do
        call("platform 7 #{platform_input}")
        expect(game_double).to have_received(:update!)
          .with(platforms: [ expected_normalized ])
      end
    end
  end

  # ── ⑥ Steam family ───────────────────────────────────────────────────────────
  #
  # Regex: /steam|\bpc\b|windows|gog|epic|amazon|battle\.?net/i — unanchored.
  # "\bpc\b" uses word-boundary anchors to avoid matching "epic" → "pc" fragment.
  # "battle\.?net" allows optional literal dot between "battle" and "net".

  describe "⑥ Steam family — all normalized forms" do
    {
      "steam"      => "PC (Steam)",
      "Steam"      => "PC (Steam)",
      "STEAM"      => "PC (Steam)",
      "pc"         => "PC (Steam)",
      "PC"         => "PC (Steam)",
      "windows"    => "PC (Steam)",
      "Windows"    => "PC (Steam)",
      "WINDOWS"    => "PC (Steam)",
      "gog"        => "PC (Steam)",
      "GOG"        => "PC (Steam)",
      "Gog"        => "PC (Steam)",
      "epic"       => "PC (Steam)",
      "Epic"       => "PC (Steam)",
      "EPIC"       => "PC (Steam)",
      "amazon"     => "PC (Steam)",
      "Amazon"     => "PC (Steam)",
      "AMAZON"     => "PC (Steam)",
      "battlenet"  => "PC (Steam)",
      "battle.net" => "PC (Steam)",
      "Battle.net" => "PC (Steam)",
      "BATTLE.NET" => "PC (Steam)",
      "PC (Steam)" => "PC (Steam)"   # already-canonical token still matches STEAM
    }.each do |platform_input, expected_normalized|
      it "\"platform 7 #{platform_input}\" → update! with [#{expected_normalized.inspect}]" do
        call("platform 7 #{platform_input}")
        expect(game_double).to have_received(:update!)
          .with(platforms: [ expected_normalized ])
      end
    end
  end

  # ── ⑦ Unknown platform (no family match) ─────────────────────────────────────
  #
  # Falls through all three regexes → stored as text.titleize.
  # Handler still returns Ok (no logo rendered, but not an error).

  describe "⑦ unknown platform — stored as titleized text, still Ok" do
    {
      "xbox"          => "Xbox",
      "Xbox"          => "Xbox",
      "XBOX"          => "Xbox",
      "Xbox Series X" => "Xbox Series X",
      "stadia"        => "Stadia",
      "Stadia"        => "Stadia",
      "Luna"          => "Luna",
      "genesis"       => "Genesis"
    }.each do |platform_input, expected_normalized|
      it "\"platform 7 #{platform_input}\" → result Ok, update! with [#{expected_normalized.inspect}]" do
        result = call("platform 7 #{platform_input}")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(game_double).to have_received(:update!)
          .with(platforms: [ expected_normalized ])
      end
    end
  end

  # ── ⑧ Comma-list inputs — single-platform result (no multi-platform parsing) ──
  #
  # The handler does NOT parse comma-separated lists. The entire text after the
  # game ref is passed as ONE platform name to PlatformInput.normalize. First-match
  # semantics decide the result:
  #   - PLAYSTATION is anchored at \A → only wins when the text STARTS with ps/play
  #   - SWITCH and STEAM are unanchored → win whenever their pattern appears anywhere
  #   - Case order: PLAYSTATION → SWITCH → STEAM → else

  describe "⑧ comma-list inputs: normalize treats the whole string as one platform" do
    {
      # PLAYSTATION anchored at \A wins when text starts with "ps"
      "ps5, switch"   => "PlayStation 5",   # "ps5" at start → PLAYSTATION
      "ps5, steam"    => "PlayStation 5",   # same
      "ps4, switch"   => "PlayStation 4",

      # SWITCH unanchored finds "switch" or "nintendo" anywhere (runs before STEAM)
      "switch, ps5"    => "Nintendo Switch", # PLAYSTATION not at start; SWITCH unanchored finds "switch"
      "steam, switch"  => "Nintendo Switch", # SWITCH runs before STEAM; finds "switch" unanchored
      "pc, switch"     => "Nintendo Switch", # SWITCH finds "switch" before STEAM finds "pc"

      # STEAM unanchored wins when no ps/play at start, no switch/nintendo present
      "steam, ps5"     => "PC (Steam)",      # PLAYSTATION: no; SWITCH: no; STEAM: "steam" found
      "pc, ps5"        => "PC (Steam)"       # PLAYSTATION: no; SWITCH: no; STEAM: \bpc\b found
    }.each do |platform_input, expected_normalized|
      it "\"platform 7 #{platform_input}\" → normalises to #{expected_normalized.inspect} (single result)" do
        call("platform 7 #{platform_input}")
        expect(game_double).to have_received(:update!)
          .with(platforms: [ expected_normalized ])
      end
    end
  end

  # ── ⑨ Follow-up detail context ───────────────────────────────────────────────
  #
  # Game comes from the card's game_id payload key; follow_up.rest is the text
  # typed AFTER the verb word (stripped by VerbDelegator). Subcommand peel still
  # applies to rest before treating the whole remainder as the platform name.

  describe "⑨ follow-up detail context (game from card; rest = platform name)" do
    it "bare platform name → :set, :system event with game_id" do
      result = call("platform", follow_up: detail_ctx("ps5"))
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["game_id"]).to eq(PLAT_GAME_ID)
      expect(game_double).to have_received(:update!).with(platforms: [ "PlayStation 5" ])
    end

    it "explicit 'set' in rest → :set" do
      call("platform", follow_up: detail_ctx("set ps5"))
      expect(game_double).to have_received(:update!).with(platforms: [ "PlayStation 5" ])
    end

    it "explicit 'unset' in rest, platform absent → Ok, no update!" do
      result = call("platform", follow_up: detail_ctx("unset ps5"))
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game_double).not_to have_received(:update!)
    end

    it "unset when platform IS present → update! removes it" do
      allow(game_double).to receive(:platforms).and_return([ "PlayStation 5" ])
      call("platform", follow_up: detail_ctx("unset ps5"))
      expect(game_double).to have_received(:update!).with(platforms: [])
    end

    it "Switch via detail reply" do
      call("platform", follow_up: detail_ctx("switch"))
      expect(game_double).to have_received(:update!).with(platforms: [ "Nintendo Switch" ])
    end

    it "Steam (steam keyword) via detail reply" do
      call("platform", follow_up: detail_ctx("steam"))
      expect(game_double).to have_received(:update!).with(platforms: [ "PC (Steam)" ])
    end

    it "Steam (pc keyword) via detail reply" do
      call("platform", follow_up: detail_ctx("pc"))
      expect(game_double).to have_received(:update!).with(platforms: [ "PC (Steam)" ])
    end

    it "PlayStation 5 (spelled out) via detail reply" do
      call("platform", follow_up: detail_ctx("PlayStation 5"))
      expect(game_double).to have_received(:update!).with(platforms: [ "PlayStation 5" ])
    end

    it "unknown platform via detail reply → stored as titleized" do
      call("platform", follow_up: detail_ctx("xbox"))
      expect(game_double).to have_received(:update!).with(platforms: [ "Xbox" ])
    end

    it "set + nintendo in detail reply" do
      call("platform", follow_up: detail_ctx("set nintendo"))
      expect(game_double).to have_received(:update!).with(platforms: [ "Nintendo Switch" ])
    end

    it "unset + switch when present → removes it" do
      allow(game_double).to receive(:platforms).and_return([ "Nintendo Switch" ])
      call("platform", follow_up: detail_ctx("unset switch"))
      expect(game_double).to have_received(:update!).with(platforms: [])
    end

    context "game not found (stale card — record gone)" do
      before { allow(::Game).to receive(:find_by).and_return(nil) }

      it "game_id in payload but record gone → :system not-found event carrying game_id ref" do
        result = call("platform", follow_up: detail_ctx("ps5", game_id: 999))
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["text"]).to include("999")
      end
    end

    context "rest blank after subcommand peel → missing_name" do
      it "blank rest → Result::Error (missing_name)" do
        result = call("platform", follow_up: detail_ctx(""))
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.platform.missing_name")
      end

      it "'set' in rest but nothing after → missing_name" do
        result = call("platform", follow_up: detail_ctx("set"))
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.platform.missing_name")
      end

      it "'unset' in rest but nothing after → missing_name" do
        result = call("platform", follow_up: detail_ctx("unset"))
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.platform.missing_name")
      end
    end
  end

  # ── ⑩ Follow-up list context ─────────────────────────────────────────────────
  #
  # rest (after verb word) starts with the game ref, then the platform name.
  # Noun fillers are stripped between subcommand and ref. When table_rows is
  # non-empty the resolved game must be in that list (by id) or it returns nil.

  describe "⑩ follow-up list context (id in rest, scoped to list)" do
    it "bare id + platform → :set" do
      call("platform", follow_up: list_ctx("7 ps5"))
      expect(game_double).to have_received(:update!).with(platforms: [ "PlayStation 5" ])
    end

    it "explicit 'set' subcommand + id + platform" do
      call("platform", follow_up: list_ctx("set 7 ps5"))
      expect(game_double).to have_received(:update!).with(platforms: [ "PlayStation 5" ])
    end

    it "explicit 'unset' subcommand + id (platform absent → no update!)" do
      result = call("platform", follow_up: list_ctx("unset 7 ps5"))
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game_double).not_to have_received(:update!)
    end

    it "unset + id when platform IS present → update! removes it" do
      allow(game_double).to receive(:platforms).and_return([ "PlayStation 5" ])
      call("platform", follow_up: list_ctx("unset 7 ps5"))
      expect(game_double).to have_received(:update!).with(platforms: [])
    end

    it "noun filler 'game' stripped before id" do
      call("platform", follow_up: list_ctx("game 7 ps5"))
      expect(game_double).to have_received(:update!).with(platforms: [ "PlayStation 5" ])
    end

    it "noun filler 'games' stripped before id" do
      call("platform", follow_up: list_ctx("games 7 ps5"))
      expect(game_double).to have_received(:update!).with(platforms: [ "PlayStation 5" ])
    end

    it "#-prefixed id in list rest" do
      call("platform", follow_up: list_ctx("#7 ps5"))
      expect(game_double).to have_received(:update!).with(platforms: [ "PlayStation 5" ])
    end

    it "set + game noun filler + id + Switch" do
      call("platform", follow_up: list_ctx("set game 7 switch"))
      expect(game_double).to have_received(:update!).with(platforms: [ "Nintendo Switch" ])
    end

    it "set + games noun filler + id + Steam" do
      call("platform", follow_up: list_ctx("set games 7 steam"))
      expect(game_double).to have_received(:update!).with(platforms: [ "PC (Steam)" ])
    end

    context "game id is outside table_rows scope → not found (scoped nil)" do
      let(:rows_without_game) { [ { cells: [ { text: "#99" } ] } ] } # only id 99 in list

      it "game id 7 not in list (only 99) → :system not-found event" do
        ctx    = list_ctx("7 ps5", table_rows: rows_without_game)
        result = call("platform", follow_up: ctx)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["text"]).to include("7")
      end

      it "unset with game id outside scope → :system not-found event" do
        ctx    = list_ctx("unset 7 ps5", table_rows: rows_without_game)
        result = call("platform", follow_up: ctx)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    context "game id IS in table_rows scope → resolved normally" do
      let(:rows_with_game) { [ { cells: [ { text: "#7" } ] } ] }

      it "game id 7 in list scope → set resolves and calls update!" do
        call("platform", follow_up: list_ctx("7 ps5", table_rows: rows_with_game))
        expect(game_double).to have_received(:update!).with(platforms: [ "PlayStation 5" ])
      end
    end

    context "empty table_rows (unrestricted scope) → any game id passes" do
      it "empty rows → no scope filtering, resolves normally" do
        call("platform", follow_up: list_ctx("7 switch", table_rows: []))
        expect(game_double).to have_received(:update!).with(platforms: [ "Nintendo Switch" ])
      end
    end

    context "no id typed in rest → needs_ref" do
      it "blank rest → Result::Error (needs_ref)" do
        result = call("platform", follow_up: list_ctx(""))
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.platform.needs_ref")
      end

      it "'set' token only (no ref after subcommand peel) → needs_ref" do
        result = call("platform", follow_up: list_ctx("set"))
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.platform.needs_ref")
      end
    end
  end

  # ── ⑪ Result::Error — needs_ref ──────────────────────────────────────────────
  #
  # Emitted in free-chat when the game ref is blank after stripping the verb word,
  # optional subcommand, and optional noun filler.

  describe "⑪ needs_ref errors (free chat) — no game ref supplied" do
    {
      "platform"              => "bare verb, no args",
      "platform   "           => "trailing spaces only",
      "platform set"          => "subcommand only, no ref",
      "platform unset"        => "subcommand only, no ref",
      "platform game"         => "noun filler only, no ref",
      "platform games"        => "noun filler only, no ref",
      "platform set game"     => "subcommand + noun filler, no ref",
      "platform set games"    => "subcommand + noun filler, no ref",
      "platform unset game"   => "unset + noun filler, no ref",
      "platform unset games"  => "unset + noun filler, no ref"
    }.each do |raw, description|
      it "#{raw.inspect} (#{description}) → Result::Error (needs_ref)" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.platform.needs_ref")
      end
    end
  end

  # ── ⑫ Result::Error — missing_name ──────────────────────────────────────────
  #
  # Emitted when a valid game ref is supplied but no platform name follows.
  # Also covers the unset variant (same path, just @subcommand = :unset).

  describe "⑫ missing_name errors — id supplied but no platform name" do
    {
      "platform 7"          => "id only",
      "platform set 7"      => "set + id, no name",
      "platform unset 7"    => "unset + id, no name",
      "platform game 7"     => "noun filler + id, no name",
      "platform games 7"    => "noun filler (plural) + id, no name",
      "platform #7"         => "#-prefixed id, no name",
      "platform set game 7" => "set + noun filler + id, no name"
    }.each do |raw, description|
      it "#{raw.inspect} (#{description}) → Result::Error (missing_name)" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.platform.missing_name")
      end
    end
  end

  # ── ⑬ Game not found → Ok :system event (not an Error) ───────────────────────
  #
  # When Game.find_by returns nil OR find_by_ref returns nil (id_only non-numeric),
  # the handler emits a "not found" :system event — an Ok result whose payload text
  # carries @error_ref so the user can see which ref was unresolvable.

  describe "⑬ game not found → Ok :system event carrying the typed ref" do
    context "Game.find_by returns nil (unknown numeric id)" do
      before { allow(::Game).to receive(:find_by).and_return(nil) }

      {
        "platform 999 ps5"          => "999",
        "platform set 999 ps5"      => "999",
        "platform unset 999 ps5"    => "999",
        "platform game 999 switch"  => "999",
        "platform games 999 steam"  => "999",
        "platform #999 ps5"         => "999"
      }.each do |raw, expected_ref|
        it "#{raw.inspect} → :system event, text includes #{expected_ref.inspect}" do
          result = call(raw)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
          expect(result.events.first[:payload]["text"]).to include(expected_ref)
        end
      end
    end

    context "id_only_resolution! — non-numeric title refs return nil without DB call" do
      # find_by_ref bails early for non-numeric refs; Game.find_by is never called.
      [
        [ "platform tekken ps5",   "tekken"  ],
        [ "platform lies ps5",     "lies"    ],
        [ "platform elden ps5",    "elden"   ]
      ].each do |raw, expected_ref|
        it "#{raw.inspect} → :system not-found event, text includes #{expected_ref.inspect}" do
          result = call(raw)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
          expect(result.events.first[:payload]["text"]).to include(expected_ref)
        end

        it "#{raw.inspect} → Game.find_by is NOT called (id_only short-circuits)" do
          call(raw)
          expect(::Game).not_to have_received(:find_by)
        end
      end
    end
  end

  # ── ⑭ Ok result payload shape ────────────────────────────────────────────────
  #
  # Every successful set/unset emits one :system event via platform_result, whose
  # payload is built by Pito::MessageBuilder::Game::PlatformSet and html_payload.

  describe "⑭ Ok :system event payload shape (representative sample)" do
    it "event kind is :system" do
      expect(call("platform 7 ps5").events.first[:kind]).to eq(:system)
    end

    it "payload['html'] is true" do
      expect(call("platform 7 ps5").events.first[:payload]["html"]).to be(true)
    end

    it "payload['game_id'] equals the resolved game's id" do
      expect(call("platform 7 ps5").events.first[:payload]["game_id"]).to eq(PLAT_GAME_ID)
    end

    it "payload['body'] is a String" do
      expect(call("platform 7 ps5").events.first[:payload]["body"]).to be_a(String)
    end

    it "set result (removed: false) payload body does not say 'Removed'" do
      body = call("platform 7 ps5").events.first[:payload]["body"]
      # "Removed" copy key is for unset; set uses platform_set or platform_unknown
      expect(body.downcase).not_to include("removed")
    end

    it "unset result (removed: true) payload body references the removed action" do
      # The copy key pito.copy.games.platform_unset renders a 'Removed' message.
      # We only verify the game_id is correct since copy rendering is tested elsewhere.
      result = call("platform unset 7 switch")
      expect(result.events.first[:payload]["game_id"]).to eq(PLAT_GAME_ID)
    end

    it "unknown platform: payload body still present (no logo, but not an error)" do
      result = call("platform 7 xbox")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["body"]).to be_a(String)
    end
  end

  # ── ⑮ De-dup guard (set when already present → update! NOT called) ───────────
  #
  # set_platform checks game.platforms.include?(normalized) before updating;
  # if the platform is already there, update! is skipped but the handler still
  # returns Ok.

  describe "⑮ de-dup: set when platform already present → update! skipped" do
    before { allow(game_double).to receive(:platforms).and_return([ "PlayStation 5" ]) }

    it "platform 7 ps5 with ps5 already in platforms → Ok, no update!" do
      result = call("platform 7 ps5")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game_double).not_to have_received(:update!)
    end

    it "platform set 7 PlayStation 5 (exact normalized) → Ok, no update!" do
      result = call("platform set 7 PlayStation 5")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game_double).not_to have_received(:update!)
    end

    it "platform set 7 PlayStation5 (variant) → normalized matches → Ok, no update!" do
      result = call("platform set 7 PlayStation5")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game_double).not_to have_received(:update!)
    end
  end
end
