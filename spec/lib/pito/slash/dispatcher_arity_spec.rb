# frozen_string_literal: true

# P5.5 — Dispatcher generic positional-arity guard.
#
# The guard rejects invocations where invocation.args.size > positional capacity
# derived from the command's grammar spec. kv slots are excluded from the count;
# any repeatable or :free slot makes capacity unbounded (guard never fires).
#
# Commands with no grammar spec are skipped (not validated).
# Handlers that declare `self.validates_own_arity = true` are also skipped.

require "rails_helper"

RSpec.describe Pito::Slash::Dispatcher, "arity guard (P5.5)", type: :service do
  let(:conversation) { Conversation.create! }

  before { Pito::Slash::Registry.register_all! }

  def dispatch(input)
    described_class.call(input:, conversation:, authenticated: true)
  end

  # Helper: returns true when the result is a too_many_args error.
  def too_many_args_error?(result)
    result.is_a?(Pito::Slash::Result::Error) &&
      result.message_key == "pito.slash.errors.too_many_args"
  end

  # ── /config — capacity 2 (provider + optional state) ────────────────────────

  describe "/config" do
    it "accepts '/config google' (1 arg, capacity 2)" do
      result = dispatch("/config google")
      expect(too_many_args_error?(result)).to be(false)
    end

    it "accepts '/config sound on' (2 args, capacity 2)" do
      result = dispatch("/config sound on")
      expect(too_many_args_error?(result)).to be(false)
    end

    it "accepts '/config google client_id=x' (1 positional arg; kv doesn't count)" do
      result = dispatch("/config google client_id=x")
      expect(too_many_args_error?(result)).to be(false)
    end

    it "rejects '/config google a b' (3 positional args > capacity 2)" do
      result = dispatch("/config google a b")
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.errors.too_many_args")
    end

    it "too_many_args error interpolates the verb" do
      result = dispatch("/config google a b")
      expect(result.message_args[:verb]).to eq(:config)
    end
  end

  # ── /help — capacity 0 (no positional slots) ─────────────────────────────────

  describe "/help" do
    it "accepts '/help' (0 args)" do
      result = dispatch("/help")
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "rejects '/help foo' (1 arg > capacity 0)" do
      result = dispatch("/help foo")
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.errors.too_many_args")
    end

    it "does NOT reject '/help --help' — intercepted before the guard as a help flag" do
      result = dispatch("/help --help")
      # --help is intercepted by help_requested? before the arity guard fires.
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "does NOT reject '/help --help --help' — raw match fires first" do
      # Both --help tokens appear in raw; help_requested? matches the first one
      # and routes to HelpRenderer. The arity guard is never reached.
      result = dispatch("/help --help --help")
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end
  end

  # ── /disconnect — capacity unbounded (dynamic :channels vocab) ───────────────

  describe "/disconnect" do
    it "accepts '/disconnect @alpha' (1 arg, channel vocab)" do
      result = dispatch("/disconnect @alpha")
      # Will get a not_found or confirmation — not a too_many_args error.
      if result.is_a?(Pito::Slash::Result::Error)
        expect(result.message_key).not_to eq("pito.slash.errors.too_many_args")
      end
    end
  end

  # ── /login — capacity unbounded (:free slot) ──────────────────────────────────

  describe "/login" do
    it "accepts '/login 123456' without triggering the arity guard" do
      # /login has a :free slot → unbounded → guard never fires.
      # The command has no handler (handler-less); dispatcher returns unknown_verb error.
      # That's fine — we're testing the guard doesn't fire.
      result = dispatch("/login 123456")
      if result.is_a?(Pito::Slash::Result::Error)
        expect(result.message_key).not_to eq("pito.slash.errors.too_many_args")
      end
    end
  end

  # ── /themes — validates_own_arity = true → dispatcher skips guard ────────────

  describe "/themes — dispatcher skips generic guard (validates_own_arity)" do
    it "routes /themes ayu-dark to the handler (not rejected by dispatcher guard)" do
      result = dispatch("/themes ayu-dark")
      # The handler accepts it (valid 1-arg form); result is Ok.
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "routes /themes ayu-dark ayu-dark to the handler for self-validation" do
      # Dispatcher guard is skipped; theme handler rejects with its own error.
      result = dispatch("/themes ayu-dark ayu-dark")
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.theme.errors.too_many_args")
    end
  end
end
