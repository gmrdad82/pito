# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `price` (recognition only, DB mocked) ─────────────────────
#
# RULE: every input combination recognised — no exception. All DB lookups are
# stubbed (zero factories).
#
# Subject:  Pito::Chat::Handlers::Price
#           (app/services/pito/chat/handlers/price.rb)
#
# ── Two entry points, two behaviors ──────────────────────────────────────────
#
# `call` now gates on `follow_up?` FIRST, before any parsing:
#
#   no follow-up context (free chat — every typed form: bare `price`, `price
#   set …`, `price unset …`, implicit `price <id> <amount>`)
#     → the typed setter moved to the consolidated `update` verb. Returns
#       `Result::Error` (message_key "pito.chat.update.moved", args: { example:
#       "update game price 12 59.99" }) IMMEDIATELY — parse_args/resolve_game/
#       parse_amount never run, `::Game.find_by` and `game.update!` never
#       called. Every typed form moves, with no exception.
#
#   follow-up context present (reply path — `#g3 price 20` on a game_detail
#   card is handled inline in follow_up/handlers/game_detail.rb and never
#   reaches this handler at all; a game_list reply routes through
#   VerbDelegator, which reconstructs the full "price …" string as message.raw
#   and attaches a FollowUpContext, then calls this handler exactly as chat
#   used to)
#     → `follow_up?` is true, so `moved` is skipped and the pre-existing
#       parse_args → set/unset/resolve_game/parse_amount pipeline runs
#       unchanged: same subcommand rules, same id-only game resolution, same
#       BigDecimal amount parsing, same Ok/Error result shapes.
#
# Parsing (parse_args — reads message.raw only, reply path only):
#   Strips "price", splits into [sub, ref, raw_amount].
#   sub "set"   → set(ref, raw_amount)
#   sub "unset" → unset(ref)
#   anything else (including nil, or a non-set/unset first token) → implicit
#     set: `set(sub, ref)` (sub read as the game ref, ref as the amount)
#
# Game resolution (resolve_game — id-only, no ILIKE):
#   Numeric ref (#N or N) → ::Game.find_by(id: N_string)   → record or nil
#   Non-numeric ref        → nil immediately (no DB call)
#
# Amount parsing (parse_amount):
#   BigDecimal(raw).round(2), must be ≥ 0; ArgumentError/TypeError → nil
#   0 = free (valid); negative → nil → needs_ref
#
# Result shapes (reply path only):
#   moved         → Result::Error, message_key "pito.chat.update.moved"
#   set success   → Result::Ok, event[:kind] = :system, payload["html"] = true
#   unset success → Result::Ok, event[:kind] = :system, payload["text"] contains title
#   not_found     → Result::Ok, event[:kind] = :system, payload["text"] contains ref
#   needs_ref     → Result::Error, message_key "pito.chat.price.needs_ref"
#
# Sections
#   A — typed forms (no follow-up) → moved, no parsing, no DB call [compact table]
#   B — reply path (FollowUpContext): chat-verb ignore-context regression (needs_ref)
#   C — reply path (FollowUpContext): set/unset/not-found/shape parity, unchanged
RSpec.describe "Dispatch matrix — price (recognition, DB mocked)", type: :dispatch do
  PRICE_GAME_ID = 42

  let(:game)         { double("Game", id: PRICE_GAME_ID, title: "Pragmata", price: BigDecimal("59.99")) }
  let(:conversation) { double("Conversation") }

  # Default stubs: ::Game.find_by returns game for id "42", nil otherwise.
  # Rendering helpers are stubbed to avoid shimmer/HTML concerns in the
  # recognition tests (only the shape assertions in section C need them real).
  before do
    allow(::Game).to receive(:find_by).and_return(nil)
    allow(::Game).to receive(:find_by).with(id: PRICE_GAME_ID.to_s).and_return(game)
    allow(game).to receive(:update!)
    allow(Pito::Games::PriceGlyphs).to receive(:html).and_return("<span>coins</span>")
    allow(Pito::Copy).to receive(:render_html).and_return("<p>price set ok</p>".html_safe)
  end

  # Build and invoke a Price handler from a raw string.
  # Price reads ONLY message.raw inside parse_args, so a minimal stub suffices.
  def handler_for(raw, follow_up: nil)
    Pito::Chat::Handlers::Price.new(
      message:      instance_double(Pito::Chat::Message, raw: raw),
      conversation: conversation,
      follow_up:    follow_up
    )
  end

  def call(raw, follow_up: nil)
    handler_for(raw, follow_up:).call
  end

  # Builds a FollowUpContext as though the user replied to a game_detail card
  # for the canonical game (PRICE_GAME_ID). Mirrors VerbDelegator: message.raw
  # carries the FULL "price …" string (verb included), a FollowUpContext is
  # attached alongside it.
  def game_detail_ctx(rest: "")
    source_event = instance_double(
      Event,
      payload: { "game_id" => PRICE_GAME_ID, "reply_target" => "game_detail" }
    )
    Pito::Chat::FollowUpContext.new(source_event: source_event, rest: rest)
  end

  # ── A. Typed forms (free chat, no follow-up) → moved (compact table) ────────
  #
  # `call` gates on `follow_up?` before parse_args ever runs. Every typed form
  # — bare verb, set, unset, implicit set, unknown subcommand, uppercased,
  # #-prefixed ref, negative/non-numeric amount, extra tokens — moves, with NO
  # exception: same Error, same message_key/args, zero DB calls.
  describe "A — typed forms (no follow-up) → moved, before any parsing" do
    {
      "price"                    => "bare verb, no tokens",
      "price   "                 => "bare verb with trailing spaces",
      "price set"                => "set, no ref/amount",
      "price set 42 59.99"       => "set, valid ref + amount (still moves)",
      "price set #42 59.99"      => "set, #-prefixed ref (still moves)",
      "price set 42 -5"          => "set, negative amount (still moves)",
      "price set 42 free"        => "set, non-numeric amount (still moves)",
      "price set pragmata 9.99"  => "set, non-numeric ref (still moves)",
      "price unset"              => "unset, no ref",
      "price unset 42"           => "unset, valid ref (still moves)",
      "price unset #42"          => "unset, #-prefixed ref (still moves)",
      "price 42 59.99"           => "implicit set, numeric id + amount",
      "price #42 59.99"          => "implicit set, #-prefixed id + amount",
      "price 42"                 => "implicit set, id only, no amount",
      "price bump #42 9.99"      => "unrecognised subcommand-shaped word",
      "price SET 42 59.99"       => "uppercased subcommand",
      "price UNSET 42"           => "uppercased subcommand",
      "price 99999 9.99"         => "implicit set, unknown id"
    }.each do |raw, label|
      it "#{raw.inspect} (#{label}) → moved (Error), no DB call" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.update.moved")
        expect(result.message_args).to eq({ example: "update game price 12 59.99" })
        expect(::Game).not_to have_received(:find_by)
        expect(game).not_to have_received(:update!)
      end
    end
  end

  # ── B. Reply path (FollowUpContext) — chat-verb regression, unchanged ───────
  #
  # A FollowUpContext whose reconstructed raw omits the game ref (`price set
  # 40` → sub="set", ref="40", raw_amount=nil; `price unset` → sub="unset",
  # ref=nil) still yields needs_ref through the (unchanged) parse pipeline —
  # `follow_up?` only decides whether `moved` is skipped, it does not make the
  # handler adopt the card's game_id itself (parse_args still reads only
  # message.raw). Verbatim from the pre-"moved" matrix.
  describe "B — follow-up context present → parse pipeline runs (needs_ref), unchanged" do
    it "#handle price set 40 (FollowUpContext present) → Error (needs_ref), no update" do
      fu     = game_detail_ctx(rest: "set 40")
      result = call("price set 40", follow_up: fu)
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.price.needs_ref")
      expect(game).not_to have_received(:update!)
    end

    it "#handle price unset (FollowUpContext present) → Error (needs_ref), no update" do
      fu     = game_detail_ctx(rest: "unset")
      result = call("price unset", follow_up: fu)
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.price.needs_ref")
      expect(game).not_to have_received(:update!)
    end
  end

  # ── C. Reply path (FollowUpContext) — set/unset/not-found/shape parity ─────
  #
  # The game_list reply delegates through VerbDelegator, which attaches a
  # FollowUpContext alongside the FULL "price …" string as message.raw — so
  # the handler resolves the game/amount from message.raw exactly as the old
  # (pre-"moved") chat path did. These confirm that pipeline is byte-identical
  # to before: same set/unset/resolve_game/parse_amount behavior, same result
  # shapes, still reachable and still green.
  describe "C — follow-up context present → set/unset/not-found/shape parity, unchanged" do
    def fu_for(raw)
      game_detail_ctx(rest: raw.sub(/\Aprice\b\s*/i, ""))
    end

    it '"price set 42 59.99" → Ok, update!(price: BigDecimal)' do
      result = call("price set 42 59.99", follow_up: fu_for("price set 42 59.99"))
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game).to have_received(:update!).with(price: BigDecimal("59.99"))
    end

    it '"price set 42 8.999" → Ok, rounds to 2dp (9.00)' do
      result = call("price set 42 8.999", follow_up: fu_for("price set 42 8.999"))
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game).to have_received(:update!).with(price: BigDecimal("9.00"))
    end

    it '"price set 42 0" → Ok, update!(price: 0) (free)' do
      result = call("price set 42 0", follow_up: fu_for("price set 42 0"))
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game).to have_received(:update!).with(price: BigDecimal("0"))
    end

    it '"price set 42 -5" (negative amount) → Error (needs_ref), no update' do
      result = call("price set 42 -5", follow_up: fu_for("price set 42 -5"))
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.price.needs_ref")
      expect(game).not_to have_received(:update!)
    end

    it '"price set pragmata 9.99" (non-numeric ref) → Ok not-found, no update' do
      result = call("price set pragmata 9.99", follow_up: fu_for("price set pragmata 9.99"))
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("pragmata")
      expect(game).not_to have_received(:update!)
    end

    it '"price set 99999 9.99" (unknown id) → Ok not-found naming the id, no update' do
      result = call("price set 99999 9.99", follow_up: fu_for("price set 99999 9.99"))
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("99999")
      expect(game).not_to have_received(:update!)
    end

    it '"price unset 42" → Ok, update!(price: nil)' do
      result = call("price unset 42", follow_up: fu_for("price unset 42"))
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game).to have_received(:update!).with(price: nil)
    end

    it '"price unset 42" → confirmation text includes the game title' do
      result = call("price unset 42", follow_up: fu_for("price unset 42"))
      expect(result.events.first[:payload]["text"]).to include("Pragmata")
    end

    it '"price 42 59.99" (implicit set) → Ok, update!(price: BigDecimal)' do
      result = call("price 42 59.99", follow_up: fu_for("price 42 59.99"))
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game).to have_received(:update!).with(price: BigDecimal("59.99"))
    end

    it '"price set 42 59.99" → :system event, payload html: true, body String (Ok shape)' do
      result = call("price set 42 59.99", follow_up: fu_for("price set 42 59.99"))
      event  = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload]["html"]).to be(true)
      expect(event[:payload]["body"]).to be_a(String)
      expect(result.events.size).to eq(1)
      expect(result.consume).to be(true)
    end

    it '"price unset 42" → :system event, payload text String (Ok shape)' do
      result = call("price unset 42", follow_up: fu_for("price unset 42"))
      event  = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload]["text"]).to be_a(String)
      expect(result.events.size).to eq(1)
    end

    it '"price set 42 9.99" → Game.find_by called with id: "42"' do
      call("price set 42 9.99", follow_up: fu_for("price set 42 9.99"))
      expect(::Game).to have_received(:find_by).with(id: "42")
    end

    it '"price set #42 9.99" (#-prefixed ref) → Game.find_by called with id: "42"' do
      call("price set #42 9.99", follow_up: fu_for("price set #42 9.99"))
      expect(::Game).to have_received(:find_by).with(id: "42")
    end
  end
end
