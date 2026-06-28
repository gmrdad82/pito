# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `/logout` (recognition, DB mocked) ───────────────────────
#
# RULE: every input form the grammar recognises — no exception. Zero factories,
# zero DB writes.
#
# `/logout` is a handler-less slash command: it has a grammar spec
# (auth: :authenticated_only, zero slots) but NO handler class in
# Pito::Slash::Registry. In production the controller intercepts it
# synchronously via `logout_command?` → `handle_logout` — the Dispatcher is
# never called.
#
# When the Dispatcher IS called directly (tested here in isolation), it
# follows this priority order (lib/pito/slash/dispatcher.rb):
#   1. parse  → Result::Error if parse fails (unreachable for valid input)
#   2. help_requested? → HelpBuilder  (fires BEFORE handler lookup)
#   3. handler_class lookup → nil → Result::Error(:unknown_verb)
#
# NOTE: The arity guard lives AFTER the handler lookup and is therefore
# NEVER reached for /logout. Extra positional args produce :unknown_verb,
# NOT :too_many_args.
RSpec.describe "Dispatch matrix — logout (recognition, DB mocked)", type: :dispatch do
  let(:conversation) { double("conversation") }

  def dispatch(raw)
    Pito::Slash::Dispatcher.call(input: raw, conversation:, authenticated: true)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 0. Grammar / auth-tier recognition
  #
  # Asserted via parsed_intent (grammar layer only — no handler executed).
  # ═══════════════════════════════════════════════════════════════════════════
  describe "grammar recognition" do
    [
      "/logout",
      "/logout   ",
      "/logout foo",
      "/logout --help",
      "/LOGOUT",
      "/Logout",
      "/LOGOUT   "
    ].each do |input|
      it "#{input.inspect} → stack :slash, verb :logout, known: true" do
        intent = parsed_intent(input)
        expect(intent[:stack]).to eq(:slash)
        expect(intent[:verb]).to eq(:logout)
        expect(intent[:known]).to be(true)
      end
    end

    # `exit` + `quit` are aliases of /logout (owner-added) — canonicalise to :logout.
    [ "/exit", "/quit", "/EXIT", "/Quit" ].each do |input|
      it "#{input.inspect} (alias) → verb :logout, known: true" do
        intent = parsed_intent(input)
        expect(intent[:stack]).to eq(:slash)
        expect(intent[:verb]).to eq(:logout)
        expect(intent[:known]).to be(true)
      end
    end

    it "the logout grammar spec declares the exit + quit aliases" do
      spec = Pito::Grammar::Registry.spec(namespace: :slash, name: :logout)
      expect(spec.aliases).to include(:exit, :quit)
    end

    it "auth tier is :authenticated_only (bare verb)" do
      expect(parsed_intent("/logout")[:auth]).to eq(:authenticated_only)
    end

    it "auth tier is :authenticated_only (uppercase form)" do
      expect(parsed_intent("/LOGOUT")[:auth]).to eq(:authenticated_only)
    end

    it "auth tier is :authenticated_only (mixed case)" do
      expect(parsed_intent("/Logout")[:auth]).to eq(:authenticated_only)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 1. Dispatcher — handler-less: always returns unknown_verb
  #
  # No handler class is registered for :logout, so the Dispatcher returns
  # Result::Error(:unknown_verb) for every non-help input. The arity guard
  # is bypassed (it is unreachable without a handler class).
  # ═══════════════════════════════════════════════════════════════════════════
  describe "dispatcher — handler-less (unknown_verb)" do
    {
      "bare verb"           => "/logout",
      "trailing spaces"     => "/logout   ",
      "extra arg"           => "/logout foo",
      "multiple extra args" => "/logout foo bar"
    }.each do |label, raw|
      context "#{label} (#{raw.inspect})" do
        it "returns Result::Error" do
          expect(dispatch(raw)).to be_a(Pito::Slash::Result::Error)
        end

        it "message_key is 'pito.slash.errors.unknown_verb'" do
          expect(dispatch(raw).message_key).to eq("pito.slash.errors.unknown_verb")
        end

        it "message_args includes verb: :logout" do
          expect(dispatch(raw).message_args[:verb]).to eq(:logout)
        end
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 2. Extra args → unknown_verb, NOT too_many_args
  #
  # The arity guard (pito.slash.errors.too_many_args) is only reached after a
  # successful handler class lookup. Since /logout has no handler class, extra
  # positional args fall through to the unknown_verb branch instead.
  # ═══════════════════════════════════════════════════════════════════════════
  describe "extra args → unknown_verb (arity guard not applicable)" do
    it "/logout foo → Result::Error with unknown_verb (not too_many_args)" do
      result = dispatch("/logout foo")
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.errors.unknown_verb")
    end

    it "/logout foo → message_key is NOT too_many_args" do
      expect(dispatch("/logout foo").message_key).not_to eq("pito.slash.errors.too_many_args")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 3. --help / -h intercept (Dispatcher-level)
  #
  # The Dispatcher intercepts --help BEFORE the handler lookup, so HelpBuilder
  # is called even for handler-less commands — this is the only Result::Ok path
  # through the Dispatcher for /logout.
  #
  # Regex: /\s--help\b|\s-h\b/ — a leading space is required; no-space form
  # (/logout--help) does NOT trigger the intercept.
  #
  # HelpBuilder is stubbed to avoid I18n rendering.
  # ═══════════════════════════════════════════════════════════════════════════
  describe "--help / -h intercept (Dispatcher-level)" do
    let(:help_result) do
      Pito::Slash::Result::Ok.new(events: [ { kind: "system", payload: { text: "help" } } ])
    end

    before do
      allow(Pito::Slash::HelpBuilder).to receive(:call).and_return(help_result)
    end

    {
      "bare --help" => "/logout --help",
      "short -h"    => "/logout -h"
    }.each do |label, raw|
      context "#{label} (#{raw.inspect})" do
        it "calls HelpBuilder (handler lookup bypassed)" do
          expect(Pito::Slash::HelpBuilder).to receive(:call)
          dispatch(raw)
        end

        it "returns the HelpBuilder result (Result::Ok)" do
          expect(dispatch(raw)).to eq(help_result)
        end
      end
    end

    it "no leading space: /logout--help → HelpBuilder NOT called (regex requires \\s)" do
      # The lexer may tokenize /logout--help as a single unknown verb → Result::Error;
      # either way, HelpBuilder is never reached.
      dispatch("/logout--help")
      expect(Pito::Slash::HelpBuilder).not_to have_received(:call)
    end
  end
end
