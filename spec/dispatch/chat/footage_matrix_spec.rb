# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `footage` (recognition only, DB mocked) ──────────────────
#
# RULE: every kwarg combination recognized — no exception. Tests what the footage
# handler UNDERSTANDS from a raw input, not data persistence. All DB lookups are
# stubbed so the handler resolves records without touching the database.
#
# Subject: Pito::Chat::Handlers::Footage
#          (lib/pito/chat/handlers/footage.rb)
#
# Dispatch branches (based on the first token after stripping "footage "):
#   "update" subcommand, free chat (no follow-up) → the typed setter form is
#                          RETIRED: ALWAYS Result::Error :moved
#                          ("pito.chat.update.moved"), for ANY arguments
#                          (bare, partial, invalid hours, unknown id, or a
#                          fully well-formed form). Game.find_by / game.update!
#                          are NEVER called — the branch decides on `follow_up?`
#                          alone, before any argument is even inspected.
#   "update" subcommand, follow-up context → unchanged: resolves the typed id
#                          from message.raw (not the source event), ceils hours
#                          to the next 0.5-step, calls game.update!. (This is
#                          the Chat handler's own `follow_up?` branch, exercised
#                          directly below — the actual `#<handle> footage …`
#                          reply on a game_detail card routes through the
#                          separate Pito::FollowUp::Handlers::GameDetail and is
#                          untouched by this change.)
#   anything else         → Result::Error (needs_ref usage hint)
#
# The `footage snippet` / `footage game <id>` ffprobe one-liner was RETIRED
# 2026-07-13 (moved to pito-tui, ctrl+f) — "snippet" and "game" are now just
# unrecognized subcommands like any other, covered by the needs_ref table below.
#
# Hours parsing (parse_hours, follow-up "update" path only):
#   Zero or positive value → BigDecimal, ceil UP to next 0.5 step, returned as Rational
#   Negative              → nil → needs_ref
#   Non-numeric           → ArgumentError rescued → nil → needs_ref
#
# Follow-up context:
#   Unlike handlers that use TargetResolution, Footage reads ONLY message.raw
#   (via parse_args). The follow_up context is NOT consulted for game resolution.
#   The full "footage update <id> <hours>" form is required regardless.

RSpec.describe "Dispatch matrix — footage (recognition, DB mocked)", type: :dispatch do
  FOOTAGE_GAME_ID = 5

  let(:game)         { double("Game", id: FOOTAGE_GAME_ID, title: "Elden Ring", footage_hours: 10.0) }
  let(:conversation) { double("Conversation") }

  # Default stubs: game lookup always succeeds; update! always returns true.
  before do
    allow(::Game).to receive(:find_by).and_return(game)
    allow(game).to receive(:update!).and_return(true)
  end

  # Build and invoke a Footage handler from a raw string. The handler reads ONLY
  # message.raw inside parse_args, so an instance_double with a single stub is
  # sufficient — no body_tokens or verb needed.
  def handler_for(raw, follow_up: nil)
    Pito::Chat::Handlers::Footage.new(
      message:      instance_double(Pito::Chat::Message, raw: raw),
      conversation: conversation,
      follow_up:    follow_up
    )
  end

  def call(raw, follow_up: nil)
    handler_for(raw, follow_up:).call
  end

  # ── needs_ref → Result::Error ──────────────────────────────────────────────
  #
  # Every bare or unrecognized subcommand (not "update") → Error :needs_ref.
  # "update" always moves in free chat (see below); "snippet" and "game" are
  # retired (2026-07-13, moved to pito-tui) and now just fall through here like
  # any other unrecognized word.

  describe "needs_ref → Result::Error (pito.chat.footage.needs_ref)" do
    {
      "footage"                => "bare verb, no subcommand",
      "footage   "             => "bare verb with trailing spaces",
      "footage set #5 2.5"     => "unrecognized subcommand 'set'",
      "footage #5 2.5"         => "id in subcommand slot (no 'update' keyword)",
      "footage 5 2.5"          => "bare id in subcommand slot",
      "footage 2.5"            => "only hours, no subcommand",
      "footage unknown arg"    => "arbitrary unknown subcommand",
      "footage snippet"        => "retired snippet subcommand — no longer special-cased",
      "footage game 5"         => "retired game subcommand — no longer aliases snippet"
    }.each do |raw, description|
      it "#{raw.inspect} (#{description}) → Result::Error :needs_ref" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.footage.needs_ref")
      end
    end

    it "Game.find_by is never called for the retired 'snippet'/'game' subcommands" do
      expect(::Game).not_to receive(:find_by)
      call("footage snippet")
      call("footage game 5")
    end
  end

  # ── typed form moved (free chat) → Result::Error (pito.chat.update.moved) ─
  #
  # The typed setter retired: `footage update …` in free chat (no follow-up
  # context) ALWAYS returns the "moved" error, regardless of whether the ref
  # or hours are present, missing, or invalid — `call` decides on `follow_up?`
  # alone, before parse_args' output is ever inspected. Game.find_by /
  # game.update! are NEVER called. This table collapses what used to be
  # dozens of needs-ref/not-found/update-success permutations, since every one
  # of them now short-circuits to the same moved Error.

  describe "footage update <anything> (free chat) → Result::Error (pito.chat.update.moved)" do
    {
      "footage update"                     => "bare update, no ref or hours",
      "footage update #5"                  => "ref present, hours missing",
      "footage update 5"                   => "bare numeric ref, hours missing",
      "footage update #5 -1"               => "ref present, negative hours (would have needs_ref'd)",
      "footage update #5 abc"              => "ref present, non-numeric hours",
      "footage update abc 2"               => "non-numeric ref (would have short-circuited to not_found)",
      "footage update #99 2"               => "numeric ref, unknown id (would have hit the DB before)",
      "footage update #5 2.5"              => "fully valid form (would have succeeded and updated before)",
      "footage update #5 2.5 extra tokens" => "fully valid + trailing tokens — still moved, no partial parse"
    }.each do |raw, description|
      it "#{raw.inspect} (#{description}) → Result::Error :moved, no DB call" do
        expect(::Game).not_to receive(:find_by)
        expect(game).not_to receive(:update!)
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.update.moved")
        expect(result.message_args).to eq(example: "update game footage 12 8.5")
      end
    end
  end

  # ── follow-up context (game_detail card) ──────────────────────────────────
  #
  # Footage does NOT use TargetResolution — parse_args reads only message.raw.
  # The follow_up context payload (game_id) is never consulted. The full
  # "footage update <id> <hours>" form is required even in a follow-up reply.

  describe "follow-up context — game_detail card" do
    let(:source_event) do
      instance_double(
        Event,
        payload: { "game_id" => FOOTAGE_GAME_ID, "reply_target" => "game_detail" }
      )
    end

    it "bare hours reply 'footage 3' → needs_ref (sub='3', not 'update')" do
      ctx    = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "footage 3")
      result = call("footage 3", follow_up: ctx)
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.footage.needs_ref")
    end

    it "partial 'footage update' (no id or hours) → needs_ref" do
      ctx    = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "footage update")
      result = call("footage update", follow_up: ctx)
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.footage.needs_ref")
    end

    it "'footage snippet' in follow-up context → needs_ref (retired, no longer context-free)" do
      ctx    = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "footage snippet")
      result = call("footage snippet", follow_up: ctx)
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.footage.needs_ref")
    end

    it "full 'footage update #5 3' in follow-up → resolves from typed id (NOT source payload)" do
      ctx = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "footage update #5 3")
      expect(::Game).to receive(:find_by).with(id: "5").and_return(game)
      expect(game).to receive(:update!).with(footage_hours: Rational(3, 1)).and_return(true)
      result = call("footage update #5 3", follow_up: ctx)
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "source event game_id is ignored — only typed id in raw is used for resolution" do
      other_game = double("Game", id: 99, title: "Other", footage_hours: 0.0)
      ctx = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "footage update #99 2")
      # Typed id #99, NOT the source_event's game_id (5)
      expect(::Game).to receive(:find_by).with(id: "99").and_return(other_game)
      expect(other_game).to receive(:update!).with(footage_hours: Rational(2, 1)).and_return(true)
      call("footage update #99 2", follow_up: ctx)
    end
  end
end
