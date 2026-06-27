# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `price` (recognition only, DB mocked) ─────────────────────
#
# RULE: every input combination recognised — no exception. All DB lookups are
# stubbed (zero factories). Asserts the parsed intent: subcommand (set/unset),
# resolved game id, and parsed amount (BigDecimal ≥ 0) or nil for unset — or
# the emitted error shape.
#
# Subject:  Pito::Chat::Handlers::Price
#           (app/services/pito/chat/handlers/price.rb)
#
# Parsing (parse_args — reads message.raw only):
#   Strips "price", splits into [sub, ref, raw_amount].
#   sub "set"   → set(ref, raw_amount)
#   sub "unset" → unset(ref)
#   anything else (including nil or a bare #ref token) → needs_ref (Error)
#
# Game resolution (resolve_game — id-only, no ILIKE):
#   Numeric ref (#N or N) → ::Game.find_by(id: N_string)   → record or nil
#   Non-numeric ref        → nil immediately (no DB call)
#
# Amount parsing (parse_amount):
#   BigDecimal(raw).round(2), must be ≥ 0; ArgumentError/TypeError → nil
#   0 = free (valid); negative → nil → needs_ref
#
# Result shapes:
#   set success   → Result::Ok, event[:kind] = :system, payload["html"] = true
#   unset success → Result::Ok, event[:kind] = :system, payload["text"] contains title
#   not_found     → Result::Ok, event[:kind] = :system, payload["text"] contains ref
#   needs_ref     → Result::Error, message_key "pito.chat.price.needs_ref"
#
# Sections
#   A — bare / missing args                   → needs_ref (Error)
#   B — unknown subcommand                    → needs_ref (Error)
#   C — `price set` valid amount forms        → Ok, game.update!(price: <BigDecimal>)
#   D — `price set` invalid amount forms      → needs_ref (Error)
#   E — `price set` game ref forms            → Ok or Ok (not-found)
#   F — bare implicit set `price #id amount`  → Ok (implicit set) [BUG CHECK]
#   G — `price unset` subcommand              → Ok, game.update!(price: nil)
#   H — not-found game (find_by → nil)        → Ok (witty not-found event)
#   I — follow-up context (game_detail card)  → Ok (game from context) [BUG CHECK]
#   J — result / event shape assertions
RSpec.describe "Dispatch matrix — price (recognition, DB mocked)", type: :dispatch do
  PRICE_GAME_ID = 42

  let(:game)         { double("Game", id: PRICE_GAME_ID, title: "Pragmata", price: BigDecimal("59.99")) }
  let(:conversation) { double("Conversation") }

  # Default stubs: ::Game.find_by returns game for id "42", nil otherwise.
  # Rendering helpers are stubbed to avoid shimmer/HTML concerns in the
  # recognition tests (only shape assertions in section J need them real).
  before do
    allow(::Game).to receive(:find_by).and_return(nil)
    allow(::Game).to receive(:find_by).with(id: PRICE_GAME_ID.to_s).and_return(game)
    allow(game).to receive(:update!)
    allow(Pito::Game::PriceGlyphs).to receive(:html).and_return("<span>coins</span>")
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
  # for the canonical game (PRICE_GAME_ID).
  def game_detail_ctx(rest: "")
    source_event = instance_double(
      Event,
      payload: { "game_id" => PRICE_GAME_ID, "reply_target" => "game_detail" }
    )
    Pito::Chat::FollowUpContext.new(source_event: source_event, rest: rest)
  end

  # ── A. Bare / missing args ────────────────────────────────────────────────────
  #
  # Every input where sub is nil, or where ref/raw_amount is absent after a
  # recognised subcommand, results in needs_ref.
  describe "A — bare / missing args → needs_ref (Error)" do
    {
      "price"         => "bare verb, no tokens",
      "price   "      => "bare verb with trailing spaces",
      "price set"     => "set with no ref and no amount",
      "price set #42" => "set with ref present but amount absent",
      "price unset"   => "unset with no ref"
    }.each do |raw, label|
      it "#{raw.inspect} (#{label})" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.price.needs_ref")
      end
    end
  end

  # ── B. Unknown subcommand ─────────────────────────────────────────────────────
  #
  # Any first token after "price " that is neither "set" nor "unset" falls to
  # the `else needs_ref` branch, including noun-words, synonyms, and typos.
  describe "B — non-set/unset first token → implicit set, non-numeric ref → not_found (Ok)" do
    # With implicit-set, any first token that isn't `set`/`unset` is treated as the
    # game id (`set(sub, ref)`). These tokens are non-numeric, so resolve_game
    # returns nil → not_found (Ok :system) naming the misread ref — NOT an Error.
    {
      "price bump #42 9.99"   => "bump",
      "price update #42 9.99" => "update",
      "price del #42"         => "del",
      "price clear #42"       => "clear",
      "price add #42 9.99"    => "add",
      "price remove #42"      => "remove",
      "price change #42 9.99" => "change"
    }.each do |raw, misread_ref|
      it "#{raw.inspect} → Ok not-found naming #{misread_ref.inspect}, no update" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["text"]).to include(misread_ref)
        expect(game).not_to have_received(:update!)
      end
    end

    # "SET" is normalised to "set" by sub&.downcase — recognised, NOT an error
    it '"price SET #42 9.99" (uppercased subcommand) is normalised → Ok' do
      result = call("price SET #42 9.99")
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end

    # "UNSET" likewise
    it '"price UNSET #42" (uppercased subcommand) is normalised → Ok' do
      result = call("price UNSET #42")
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end
  end

  # ── C. `price set` — valid amount forms ──────────────────────────────────────
  #
  # parse_amount uses BigDecimal(raw).round(2). Any non-negative value (≥ 0) is
  # accepted. 0 = free. Scientific notation works; no currency symbols.
  describe "C — price set valid amount forms → Ok, update!(price: <BigDecimal>)" do
    {
      "price set 42 59.99"  => BigDecimal("59.99"),
      "price set 42 60"     => BigDecimal("60"),
      "price set 42 60.00"  => BigDecimal("60.00"),
      "price set 42 8.5"    => BigDecimal("8.5"),    # 1 dp — round(2) is a no-op in value
      "price set 42 8.999"  => BigDecimal("9.00"),   # 3rd dp = 9 → rounds up
      "price set 42 1.004"  => BigDecimal("1.00"),   # 3rd dp = 4 → rounds down
      "price set 42 0"      => BigDecimal("0"),      # 0 = free
      "price set 42 0.00"   => BigDecimal("0.00"),   # explicit 0.00 also = free
      "price set 42 0.01"   => BigDecimal("0.01"),   # smallest non-free price
      "price set 42 1000"   => BigDecimal("1000"),   # large price
      "price set 42 1e2"    => BigDecimal("100")    # scientific notation (1×10²)
    }.each do |raw, expected_amount|
      it "#{raw.inspect} → Ok, update!(price: #{expected_amount.to_s('F')})" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(game).to have_received(:update!).with(price: expected_amount)
      end
    end

    it '"price set #42 59.99" (#-prefixed ref) → Ok, same amount' do
      result = call("price set #42 59.99")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game).to have_received(:update!).with(price: BigDecimal("59.99"))
    end

    it '"price set 42 59.99 extra tokens ignored" → Ok (only first 3 tokens matter)' do
      result = call("price set 42 59.99 some extra tokens")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game).to have_received(:update!).with(price: BigDecimal("59.99"))
    end
  end

  # ── D. `price set` — invalid amount forms ────────────────────────────────────
  #
  # Negative amounts and non-parseable tokens → parse_amount returns nil →
  # set() calls needs_ref. Currency symbols and comma-decimals are unsupported.
  describe "D — price set invalid amount forms → needs_ref (Error)" do
    {
      "price set 42 -5"     => "negative integer",
      "price set 42 -0.01"  => "negative decimal",
      "price set 42 -1000"  => "large negative",
      "price set 42 free"   => "word 'free' (non-numeric)",
      "price set 42 abc"    => "alphabetic string",
      "price set 42 €59.99" => "euro-symbol prefix (not a BigDecimal literal)",
      "price set 42 59,99"  => "comma decimal (unsupported locale format)",
      "price set 42 59.99€" => "euro-symbol suffix"
    }.each do |raw, label|
      it "#{raw.inspect} (#{label}) → Error (needs_ref)" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.price.needs_ref")
      end
    end
  end

  # ── E. `price set` — game ref forms ──────────────────────────────────────────
  #
  # resolve_game is id-only: strips a leading "#", then requires /\A\d+\z/.
  # Non-numeric refs → nil → not_found (Ok, no update).
  describe "E — price set game ref resolution" do
    it "bare numeric ref resolves game by id string" do
      call("price set 42 9.99")
      expect(::Game).to have_received(:find_by).with(id: "42")
    end

    it "#-prefixed numeric ref strips '#' and resolves by id" do
      call("price set #42 9.99")
      expect(::Game).to have_received(:find_by).with(id: "42")
    end

    it "non-numeric ref → resolve_game returns nil → not_found (Ok, no update)" do
      result = call("price set pragmata 9.99")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game).not_to have_received(:update!)
    end

    it "#-prefixed non-numeric ref → not_found (Ok, no update)" do
      result = call("price set #pragmata 9.99")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game).not_to have_received(:update!)
    end

    it "ref is a title-style word that happens to be non-numeric → not_found" do
      result = call("price set lies-of-p 9.99")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game).not_to have_received(:update!)
    end
  end

  # ── F. Implicit set — `price <id> <amount>` (no 'set' keyword) ───────────────
  #
  # Phase F: a first token that is NOT `set`/`unset` is treated as the game id
  # (`call`'s `else` branch → `set(sub, ref)`, sub=id, ref=amount). Parity with
  # the `#<handle> price <amount>` reply. A numeric id resolves the game and the
  # second token is parsed as the amount — same as explicit `price set`.
  describe "F — implicit set (no 'set' keyword) → Ok, update!(price: <BigDecimal>)" do
    {
      "price 42 59.99"  => BigDecimal("59.99"), # bare numeric id, decimal amount
      "price #42 59.99" => BigDecimal("59.99"), # #-prefixed id, decimal amount
      "price 42 60"     => BigDecimal("60"),    # integer amount
      "price 42 0"      => BigDecimal("0"),     # 0 = free
      "price 42 0.00"   => BigDecimal("0.00"),  # explicit 0.00 = free
      "price #42 8.999" => BigDecimal("9.00")  # rounds to 2dp
    }.each do |raw, expected_amount|
      it "#{raw.inspect} → Ok, update!(price: #{expected_amount.to_s('F')})" do
        result = call(raw)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(game).to have_received(:update!).with(price: expected_amount)
      end
    end

    it "implicit set resolves the game by id (find_by id: '42')" do
      call("price 42 59.99")
      expect(::Game).to have_received(:find_by).with(id: "42")
    end
  end

  # ── F2. Implicit set — error / not-found edges ───────────────────────────────
  #
  # The same amount + ref rules as explicit `set` apply to the implicit form.
  describe "F2 — implicit set edge cases" do
    it '"price 42" (id, no amount) → Error (needs_ref), no update' do
      result = call("price 42")
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.price.needs_ref")
      expect(game).not_to have_received(:update!)
    end

    it '"price 0" (single token) → Error (needs_ref), no update' do
      result = call("price 0")
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.price.needs_ref")
      expect(game).not_to have_received(:update!)
    end

    it '"price 42 -5" (implicit, negative amount) → Error (needs_ref), no update' do
      result = call("price 42 -5")
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.price.needs_ref")
      expect(game).not_to have_received(:update!)
    end

    it '"price 42 free" (implicit, non-numeric amount) → Error (needs_ref), no update' do
      result = call("price 42 free")
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.price.needs_ref")
      expect(game).not_to have_received(:update!)
    end

    it '"price 99999 9.99" (implicit, unknown id) → Ok not-found naming the id, no update' do
      allow(::Game).to receive(:find_by).and_return(nil)
      result = call("price 99999 9.99")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["text"]).to include("99999")
      expect(game).not_to have_received(:update!)
    end
  end

  # ── G. `price unset` ─────────────────────────────────────────────────────────
  #
  # Clears price to NULL. Game is resolved by numeric id only (same as set).
  # Missing ref → needs_ref. Non-numeric / not-found → not_found (Ok, no update).
  describe "G — price unset → Ok, game.update!(price: nil)" do
    it '"price unset 42" → Ok, clears price to nil' do
      result = call("price unset 42")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game).to have_received(:update!).with(price: nil)
    end

    it '"price unset #42" → Ok, #-prefix stripped, clears price' do
      result = call("price unset #42")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game).to have_received(:update!).with(price: nil)
    end

    it '"price UNSET 42" (uppercased) → Ok, normalised to unset' do
      result = call("price UNSET 42")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game).to have_received(:update!).with(price: nil)
    end

    it '"price unset" with no ref → Error (needs_ref)' do
      result = call("price unset")
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.price.needs_ref")
    end

    it '"price unset" with non-numeric ref → Ok (not-found, no update)' do
      result = call("price unset pragmata")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game).not_to have_received(:update!)
    end

    it '"price unset" with unknown numeric id → Ok (not-found, no update)' do
      result = call("price unset 99999")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(game).not_to have_received(:update!)
    end

    it "unset confirmation event text includes the game title" do
      result = call("price unset 42")
      expect(result.events.first[:payload]["text"]).to include("Pragmata")
    end
  end

  # ── H. Not-found game ────────────────────────────────────────────────────────
  #
  # When resolve_game returns nil (numeric ref but no record) the handler emits
  # a not_found Ok event that mentions the ref — NOT an Error.
  describe "H — not-found game → Ok with witty not-found event" do
    before { allow(::Game).to receive(:find_by).and_return(nil) }

    it "price set on unknown numeric id → Ok, not-found event mentions the ref" do
      result = call("price set 99999 59.99")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("99999")
    end

    it "price unset on unknown numeric id → Ok, not-found event mentions the ref" do
      result = call("price unset 99999")
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("99999")
    end
  end

  # ── I. No follow-up path in the chat Price handler ───────────────────────────
  #
  # Price REPLIES (`#handle price set 40` on a game_detail card) are served by the
  # game_detail follow-up handler, NOT by this chat verb handler. The chat Price
  # handler has no follow-up branch: it resolves the game purely from message.raw
  # via parse_args and never consults `follow_up`. So even when a FollowUpContext
  # is supplied, a reconstructed raw that omits the game ref (`price set 40` →
  # sub="set", ref="40", raw_amount=nil; `price unset` → sub="unset", ref=nil)
  # yields needs_ref — the chat handler does NOT silently adopt the card's game.
  describe "I — chat Price ignores follow-up context (replies handled elsewhere)" do
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

  # ── J. Result / event shape assertions ───────────────────────────────────────
  #
  # Verifies the exact keys, types, and semantics of every result shape the
  # handler can emit. These use the real (un-stubbed) Copy/PriceGlyphs pipeline
  # to confirm the output is well-formed, so we allow the stubs installed in the
  # outer before to remain in place (we care only about structure, not copy text).
  describe "J — result and event shape" do
    it "set success → events.first[:kind] = :system, payload has html: true and body String" do
      result = call("price set 42 59.99")
      event  = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload]["html"]).to be(true)
      expect(event[:payload]["body"]).to be_a(String)
    end

    it "set result carries exactly one event" do
      expect(call("price set 42 59.99").events.size).to eq(1)
    end

    it "unset success → events.first[:kind] = :system, payload has String text key" do
      result = call("price unset 42")
      event  = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload]["text"]).to be_a(String)
    end

    it "unset result carries exactly one event" do
      expect(call("price unset 42").events.size).to eq(1)
    end

    it "not-found result (Ok) → events.first[:kind] = :system, payload has text key" do
      allow(::Game).to receive(:find_by).and_return(nil)
      result = call("price set 99999 9.99")
      event  = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload]["text"]).to be_a(String)
    end

    it "needs_ref result → Result::Error with correct message_key and empty message_args" do
      result = call("price")
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.price.needs_ref")
      expect(result.message_args).to eq({})
    end

    it "set result has consume: true (default Ok semantics)" do
      expect(call("price set 42 59.99").consume).to be(true)
    end

    # `consume` only matters when an Ok answers a `#handle` reply; the chat Price
    # verb is never a reply, so it leaves the Ok default (true) in place — even on
    # a not-found. (The handler does not pass consume: false.)
    it "not-found result keeps consume: true (chat verb is not a reply, so consume is moot)" do
      allow(::Game).to receive(:find_by).and_return(nil)
      expect(call("price set 99999 9.99").consume).to be(true)
    end
  end
end
