# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `footage` (recognition only, DB mocked) ──────────────────
#
# RULE: every kwarg combination recognized — no exception. Tests what the footage
# handler UNDERSTANDS from a raw input, not data persistence. All DB lookups are
# stubbed so the handler resolves records without touching the database.
#
# Subject: Pito::Chat::Handlers::Footage
#          (app/services/pito/chat/handlers/footage.rb)
#
# Dispatch branches (based on the first token after stripping "footage "):
#   "update" subcommand  → resolve game by numeric id, ceil hours to 0.5-step,
#                          call game.update!, emit :system event
#   "snippet" subcommand → emit :system event with copyable ffprobe one-liner
#   anything else        → Result::Error (needs_ref usage hint)
#
# Game resolution (resolve_game):
#   Numeric ref (#N or N) → Game.find_by(id: N)   (returns record or nil → not_found)
#   Non-numeric ref        → nil immediately, no DB call (id_only resolution)
#
# Hours parsing (parse_hours):
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

  # Default stubs: game lookup always succeeds; update! always returns true;
  # Snippet builder stubbed to avoid ViewComponent rendering in recognition tests.
  before do
    allow(::Game).to receive(:find_by).and_return(game)
    allow(game).to receive(:update!).and_return(true)
    allow(Pito::MessageBuilder::Footage::Snippet).to receive(:call)
      .and_return({ "body" => "<div></div>", "html" => true })
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
  # Every input that does NOT satisfy (sub == "update") + ref.present? +
  # raw_hours.present? + parseable non-negative hours → Error :needs_ref.
  #
  # Sub-cases:
  #   A. Bare verb or wrong subcommand  → sub is nil, "set", "game", etc.
  #   B. update + missing operands      → ref or hours absent
  #   C. update + negative/non-numeric hours → parse_hours returns nil

  describe "needs_ref → Result::Error (pito.chat.footage.needs_ref)" do
    {
      # A — bare / unrecognized subcommand
      "footage"                => "bare verb, no subcommand",
      "footage   "             => "bare verb with trailing spaces",
      "footage set #5 2.5"     => "unrecognized subcommand 'set'",
      "footage game #5 2"      => "unrecognized subcommand 'game'",
      "footage #5 2.5"         => "id in subcommand slot (no 'update' keyword)",
      "footage 5 2.5"          => "bare id in subcommand slot",
      "footage 2.5"            => "only hours, no subcommand",
      "footage unknown arg"    => "arbitrary unknown subcommand",

      # B — update present but operands missing
      "footage update"         => "update, no ref, no hours",
      "footage update #5"      => "update, ref present, hours absent",
      "footage update 5"       => "update, bare numeric ref, hours absent",

      # C — update present + ref present, but hours invalid
      "footage update #5 -1"   => "negative integer hours",
      "footage update #5 -0.5" => "negative fractional hours",
      "footage update #5 -0.1" => "negative sub-half hours",
      "footage update #5 abc"  => "non-numeric hours (pure letters)",
      "footage update #5 1abc" => "non-numeric hours (mixed alphanumeric)",
      "footage update #5 1.x"  => "non-numeric hours (digit + dot + letter)",
      "footage update 5 -1"    => "bare id, negative hours"
    }.each do |raw, description|
      it "#{raw.inspect} (#{description}) → Result::Error :needs_ref" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.footage.needs_ref")
      end
    end
  end

  # ── not-found → Result::Ok (:system event) ────────────────────────────────
  #
  # Reaches the not_found path when resolve_game returns nil:
  #   - non-numeric ref   → nil immediately (no DB call)
  #   - numeric ref + no record in DB → Game.find_by → nil

  describe "not-found → Result::Ok (:system event)" do
    context "non-numeric ref (resolve_game short-circuits before any DB query)" do
      {
        "footage update abc 2"     => "plain text ref",
        "footage update my-game 2" => "hyphenated text ref",
        "footage update #abc 3"    => "#-prefixed non-numeric ref",
        "footage update game1 2"   => "alphanumeric starting with letters"
      }.each do |raw, description|
        it "#{raw.inspect} (#{description}) → :system event, Game.find_by NOT called" do
          expect(::Game).not_to receive(:find_by)
          result = call(raw)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
        end
      end
    end

    context "numeric ref, game not in DB (find_by returns nil)" do
      before { allow(::Game).to receive(:find_by).and_return(nil) }

      {
        "footage update #5 2"    => "#-prefixed id, absent from DB",
        "footage update #99 2"   => "unknown id",
        "footage update 5 2"     => "bare numeric id, absent from DB",
        "footage update 1 10"    => "bare id, larger hours",
        "footage update #5 2.5"  => "#-prefixed id with fractional hours"
      }.each do |raw, description|
        it "#{raw.inspect} (#{description}) → :system event (game not found)" do
          result = call(raw)
          expect(result).to be_a(Pito::Chat::Result::Ok)
          expect(result.events.first[:kind]).to eq(:system)
        end
      end
    end
  end

  # ── update success → Result::Ok (:system event, game.update! called) ──────
  #
  # `footage update <id> <hours>` must:
  #   1. Call Game.find_by(id: <stripped numeric id>)
  #   2. Call game.update!(footage_hours: <ceiled Rational>)
  #   3. Return Result::Ok with a :system event

  describe "footage update <id> <hours> → Result::Ok, game.update! called" do
    context "id forms" do
      it "footage update #5 2.5 → find_by id: '5', update! hours: 5/2" do
        expect(::Game).to receive(:find_by).with(id: "5").and_return(game)
        expect(game).to receive(:update!).with(footage_hours: Rational(5, 2)).and_return(true)
        result = call("footage update #5 2.5")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end

      it "footage update 5 2.5 → bare numeric id, same result (no # prefix)" do
        expect(::Game).to receive(:find_by).with(id: "5").and_return(game)
        expect(game).to receive(:update!).with(footage_hours: Rational(5, 2)).and_return(true)
        result = call("footage update 5 2.5")
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end

      it "footage update #42 10 → resolves a different numeric id" do
        game42 = double("Game", id: 42, title: "Other Game", footage_hours: 0.0)
        expect(::Game).to receive(:find_by).with(id: "42").and_return(game42)
        expect(game42).to receive(:update!).with(footage_hours: Rational(10, 1)).and_return(true)
        result = call("footage update #42 10")
        expect(result).to be_a(Pito::Chat::Result::Ok)
      end

      it "footage update #1 0.5 → id 1 resolves correctly" do
        expect(::Game).to receive(:find_by).with(id: "1").and_return(game)
        expect(game).to receive(:update!).with(footage_hours: Rational(1, 2)).and_return(true)
        call("footage update #1 0.5")
      end
    end

    context "hours rounding: every value ceils UP to the next 0.5-step (exact Rational)" do
      # parse_hours: BigDecimal ceil → half_units, then half_units / 2r (Rational)
      # Ruby simplifies Rational automatically: 2/2r → 1/1, 6/2r → 3/1, etc.
      [
        [ "0",    Rational(0,  1),  "zero → 0 (valid; zero footage is allowed)" ],
        [ "0.1",  Rational(1,  2),  "0.1 → ceils to 0.5"                        ],
        [ "0.5",  Rational(1,  2),  "0.5 → already on a half-step (exact)"       ],
        [ "0.6",  Rational(1,  1),  "0.6 → ceils to 1.0"                         ],
        [ "1",    Rational(1,  1),  "integer 1 → 1.0"                             ],
        [ "1.0",  Rational(1,  1),  "1.0 string → 1.0"                            ],
        [ "1.1",  Rational(3,  2),  "1.1 → ceils to 1.5"                          ],
        [ "1.5",  Rational(3,  2),  "1.5 → already on a half-step (exact)"        ],
        [ "1.6",  Rational(2,  1),  "1.6 → ceils to 2.0"                          ],
        [ "2.1",  Rational(5,  2),  "2.1 → ceils to 2.5"                          ],
        [ "2.5",  Rational(5,  2),  "2.5 → already on a half-step (exact)"        ],
        [ "2.75", Rational(3,  1),  "2.75 → ceils to 3.0"                         ],
        [ "3",    Rational(3,  1),  "integer 3 → 3.0"                              ],
        [ "10",   Rational(10, 1),  "integer 10 → 10.0"                            ],
        [ "12",   Rational(12, 1),  "integer 12 → 12.0"                            ],
        [ "12.3", Rational(25, 2),  "12.3 → ceils to 12.5"                         ],
        [ "12.5", Rational(25, 2),  "12.5 → already on a half-step (exact)"        ]
      ].each do |raw_hours, expected_rational, description|
        it "hours #{raw_hours.inspect}: #{description} → update!(footage_hours: #{expected_rational})" do
          expect(game).to receive(:update!).with(footage_hours: expected_rational).and_return(true)
          call("footage update #5 #{raw_hours}")
        end
      end
    end

    context "trailing tokens beyond the hours value are silently ignored (split limit 3)" do
      it "footage update #5 2.5 extra tokens → still uses 2.5" do
        expect(game).to receive(:update!).with(footage_hours: Rational(5, 2)).and_return(true)
        call("footage update #5 2.5 extra tokens")
      end

      it "footage update #5 3 second third → still uses 3" do
        expect(game).to receive(:update!).with(footage_hours: Rational(3, 1)).and_return(true)
        call("footage update #5 3 second third")
      end
    end
  end

  # ── snippet → Result::Ok (:system event) ──────────────────────────────────
  #
  # `footage snippet` emits a copyable ffprobe shell one-liner. No game lookup.

  describe "footage snippet → Result::Ok (:system event, no DB access)" do
    it "footage snippet → Result::Ok with :system event" do
      result = call("footage snippet")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "Game.find_by is never called for the snippet subcommand" do
      expect(::Game).not_to receive(:find_by)
      call("footage snippet")
    end

    it "Pito::MessageBuilder::Footage::Snippet.call is invoked once" do
      expect(Pito::MessageBuilder::Footage::Snippet).to receive(:call)
        .once.and_return({ "body" => "<div></div>", "html" => true })
      call("footage snippet")
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

    it "'footage snippet' in follow-up context → Result::Ok (snippet is context-free)" do
      ctx    = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "footage snippet")
      result = call("footage snippet", follow_up: ctx)
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
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
