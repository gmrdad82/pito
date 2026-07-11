# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `platform` (recognition only, DB mocked) ──────────────────
#
# Subject:  Pito::Chat::Handlers::Platform
# File:     app/services/pito/chat/handlers/platform.rb
# Vocab:    Pito::Games::PlatformInput (app/services/pito/game/platform_input.rb)
# Resolver: id_only_resolution! — ILIKE title lookup intentionally disabled.
#
# ── Behavior change ───────────────────────────────────────────────────────────
# The typed setter moved to the consolidated `update` verb. In free chat (no
# follow-up context) EVERY typed form — bare `platform <id> <name>`, explicit
# `platform set/unset <id> <name>`, or a bare `platform` with no args — now
# short-circuits to Result::Error("pito.chat.update.moved") BEFORE any
# resolution runs. No DB call is ever made from free chat. See § ① below.
#
# Reply forms (`#<handle> platform [set|unset] <game-id> ps5` off a game_list
# card, or `#<handle> platform [set|unset] ps5` off a game_detail card) reach
# this handler through the follow-up pipeline with `follow_up?` true, which
# bypasses the moved short-circuit entirely — those behave EXACTLY as before
# (§ ⑨ detail context, § ⑩ list context; unchanged).
#
# ── Subcommands (reply paths only — see § ⑨/⑩) ──────────────────────────────
#   `platform <id> <name>`        → bare → @subcommand = :set (default ADD)
#   `platform set <id> <name>`    → explicit :set  (ADD)
#   `platform unset <id> <name>`  → explicit :unset (REMOVE)
#   ("add"/"remove" are NOT aliases; treated as game refs → not-found)
#
# ── Noun fillers stripped before the id (reply paths) ────────────────────────
#   "game", "games"  (NOUN_FILLERS constant)
#
# ── Id ref forms (reply paths) ───────────────────────────────────────────────
#   bare integer: "7"  |  #-prefixed: "#7"  |  non-numeric → nil (id_only)
#
# ── Platform families (PlatformInput.normalize) ───────────────────────────────
#   PlayStation  /\A(?:play\s?station|ps)\s*(\d+)?\b/i   → anchored at \A
#   Switch       /switch|nintendo/i                       → unanchored
#   Steam        /steam|\bpc\b|windows|gog|epic|amazon|battle\.?net/i  → unanchored
#   Unknown      anything else → text.titleize, stored as-is (no logo)
#
# ── Result shapes ─────────────────────────────────────────────────────────────
#   Typed (free chat) → Pito::Chat::Result::Error
#            message_key "pito.chat.update.moved", message_args: { example: … }
#   Reply Ok    → Pito::Chat::Result::Ok, one :system event
#            payload: { "body" => html, "html" => true, "game_id" => id }
#   Reply Error → Pito::Chat::Result::Error with :message_key
#            needs_ref    → "pito.chat.platform.needs_ref"
#            missing_name → "pito.chat.platform.missing_name"
#   Reply Not-found Ok → :system event, payload: { "text" => "…<ref>…" }

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

  # ── ① Typed forms (free chat) — moved to `update`, no DB touch ──────────────
  #
  # Every typed shape (bare add, explicit set/unset, noun-filler variants, any
  # id form, any platform family, malformed/missing args) short-circuits in
  # `call` via `return moved unless follow_up?` BEFORE resolve_game_and_name
  # runs — so Game.find_by is NEVER invoked from free chat, regardless of what
  # the rest of the raw string looks like. § ⑨ and § ⑩ below cover the
  # follow_up? branch (reply forms), which is completely unaffected and still
  # resolves/mutates exactly as before.

  describe "① typed forms (free chat) — Result::Error(pito.chat.update.moved), no DB call" do
    {
      "platform"                  => "bare verb, no args",
      "platform   "               => "bare verb, trailing spaces only",
      "platform 7 ps5"            => "bare add form (default :set)",
      "platform set 7 ps5"        => "explicit 'set' subcommand",
      "platform unset 7 ps5"      => "explicit 'unset' subcommand",
      "platform game 7 switch"    => "noun filler 'game' + switch family",
      "platform games 7 steam"    => "noun filler 'games' + steam family",
      "platform #7 ps5"           => "#-prefixed id",
      "platform tekken ps5"       => "non-numeric ref (would 404 pre-change)",
      "platform 999 ps5"          => "unknown numeric id",
      "platform 7"                => "id only, no platform name",
      "platform set"              => "subcommand only, no ref",
      "platform add 7 ps5"        => "'add' is not a subcommand, still moved",
      "platform 7 xbox"           => "unknown platform family"
    }.each do |raw, description|
      it "#{raw.inspect} (#{description}) → moved, no DB call" do
        result = call(raw)

        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.update.moved")
        expect(result.message_args).to eq(example: "update game platform 12 ps5")
        expect(::Game).not_to have_received(:find_by)
        expect(game_double).not_to have_received(:update!)
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
end
