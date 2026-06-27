# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `/new` (recognition, DB mocked) ──────────────────────────
#
# RULE: every input form the grammar recognises — no exception. Zero factories,
# zero DB writes. No Conversation is ever created — these specs operate at the
# grammar / Dispatcher layer only.
#
# `/new` is a handler-less slash command: it has a grammar spec
# (auth: :authenticated_only, zero slots) but NO handler class in
# Pito::Slash::Registry. In production the controller intercepts it
# synchronously via `new_command?` → `handle_new` (which calls
# Conversation.create! and navigates the browser). The Dispatcher is never
# called.
#
# When the Dispatcher IS called directly (tested here in isolation), it
# follows this priority order (lib/pito/slash/dispatcher.rb):
#   1. parse  → Result::Error if parse fails (unreachable for valid input)
#   2. help_requested? → HelpBuilder  (fires BEFORE handler lookup)
#   3. handler_class lookup → nil → Result::Error(:unknown_verb)
#
# NOTE: The arity guard lives AFTER the handler lookup and is therefore
# NEVER reached for /new. Extra positional args produce :unknown_verb,
# NOT :too_many_args.
RSpec.describe "Dispatch matrix — new (recognition, DB mocked)", type: :dispatch do
  let(:conversation) { double("conversation") }

  def dispatch(raw)
    Pito::Slash::Dispatcher.call(input: raw, conversation:, authenticated: true)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 0. Grammar / auth-tier recognition
  #
  # Asserted via parsed_intent (grammar layer only — no handler executed,
  # no Conversation created).
  # ═══════════════════════════════════════════════════════════════════════════
  describe "grammar recognition" do
    [
      "/new",
      "/new   ",
      "/new foo",
      "/new --help",
      "/NEW",
      "/New",
      "/NEW   "
    ].each do |input|
      it "#{input.inspect} → stack :slash, verb :new, known: true" do
        intent = parsed_intent(input)
        expect(intent[:stack]).to eq(:slash)
        expect(intent[:verb]).to eq(:new)
        expect(intent[:known]).to be(true)
      end
    end

    it "auth tier is :authenticated_only (bare verb)" do
      expect(parsed_intent("/new")[:auth]).to eq(:authenticated_only)
    end

    it "auth tier is :authenticated_only (uppercase form)" do
      expect(parsed_intent("/NEW")[:auth]).to eq(:authenticated_only)
    end

    it "auth tier is :authenticated_only (mixed case)" do
      expect(parsed_intent("/New")[:auth]).to eq(:authenticated_only)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 1. Dispatcher — handler-less: always returns unknown_verb
  #
  # No handler class is registered for :new. When the Dispatcher is called
  # directly it returns Result::Error(:unknown_verb) for every non-help input.
  # No conversation is created, no navigation is triggered.
  # ═══════════════════════════════════════════════════════════════════════════
  describe "dispatcher — handler-less (unknown_verb)" do
    {
      "bare verb"           => "/new",
      "trailing spaces"     => "/new   ",
      "extra arg"           => "/new foo",
      "multiple extra args" => "/new foo bar"
    }.each do |label, raw|
      context "#{label} (#{raw.inspect})" do
        it "returns Result::Error" do
          expect(dispatch(raw)).to be_a(Pito::Slash::Result::Error)
        end

        it "message_key is 'pito.slash.errors.unknown_verb'" do
          expect(dispatch(raw).message_key).to eq("pito.slash.errors.unknown_verb")
        end

        it "message_args includes verb: :new" do
          expect(dispatch(raw).message_args[:verb]).to eq(:new)
        end
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 2. Extra args → unknown_verb, NOT too_many_args
  #
  # The arity guard (pito.slash.errors.too_many_args) is only reached after a
  # successful handler class lookup. Since /new has no handler class, extra
  # positional args fall through to the unknown_verb branch instead.
  # This also confirms that no Conversation.create! is triggered.
  # ═══════════════════════════════════════════════════════════════════════════
  describe "extra args → unknown_verb (arity guard not applicable)" do
    it "/new foo → Result::Error with unknown_verb (not too_many_args)" do
      result = dispatch("/new foo")
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.errors.unknown_verb")
    end

    it "/new foo → message_key is NOT too_many_args" do
      expect(dispatch("/new foo").message_key).not_to eq("pito.slash.errors.too_many_args")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 3. --help / -h intercept (Dispatcher-level)
  #
  # The Dispatcher intercepts --help BEFORE the handler lookup — and crucially
  # BEFORE the controller's `new_command?` fast-path (the controller's
  # `help_flag?` guard routes --help forms to the async Dispatcher instead of
  # the create-conversation path). No Conversation is created for any --help form.
  #
  # Regex: /\s--help\b|\s-h\b/ — a leading space is required.
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
      "bare --help" => "/new --help",
      "short -h"    => "/new -h"
    }.each do |label, raw|
      context "#{label} (#{raw.inspect})" do
        it "calls HelpBuilder (handler lookup and Conversation.create! bypassed)" do
          expect(Pito::Slash::HelpBuilder).to receive(:call)
          dispatch(raw)
        end

        it "returns the HelpBuilder result (Result::Ok)" do
          expect(dispatch(raw)).to eq(help_result)
        end
      end
    end

    it "no leading space: /new--help → HelpBuilder NOT called (regex requires \\s)" do
      # The lexer may tokenize /new--help as a single unknown verb → Result::Error;
      # either way, HelpBuilder is never reached and no conversation is created.
      dispatch("/new--help")
      expect(Pito::Slash::HelpBuilder).not_to have_received(:call)
    end
  end
end
