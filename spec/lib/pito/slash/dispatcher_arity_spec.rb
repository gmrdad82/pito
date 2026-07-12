# frozen_string_literal: true

# Dispatcher generic positional-arity guard.
#
# The guard rejects invocations where invocation.args.size > positional capacity
# derived from the command's grammar spec. kv slots are excluded from the count;
# any repeatable or :free slot makes capacity unbounded (guard never fires).
#
# Commands with no grammar spec are skipped (not validated).
# Handlers that declare `self.validates_own_arity = true` are also skipped.

require "rails_helper"

RSpec.describe Pito::Slash::Dispatcher, "arity guard", type: :service do
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

  # ── /config — capacity 3 (provider + optional state + optional effect) ───────

  describe "/config" do
    it "accepts '/config google' (1 arg, capacity 3)" do
      result = dispatch("/config google")
      expect(too_many_args_error?(result)).to be(false)
    end

    it "accepts '/config sound on' (2 args, capacity 3)" do
      result = dispatch("/config sound on")
      expect(too_many_args_error?(result)).to be(false)
    end

    it "accepts '/config fx scramble' (2 args, capacity 3)" do
      result = dispatch("/config fx scramble")
      expect(too_many_args_error?(result)).to be(false)
    end

    it "accepts '/config google client_id=x' (1 positional arg; kv doesn't count)" do
      result = dispatch("/config google client_id=x")
      expect(too_many_args_error?(result)).to be(false)
    end

    it "rejects '/config google a b c' (4 positional args > capacity 3)" do
      result = dispatch("/config google a b c")
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.errors.too_many_args")
    end

    it "too_many_args error interpolates the tool" do
      result = dispatch("/config google a b c")
      expect(result.message_args[:tool]).to eq(:config)
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
      # and routes to HelpBuilder. The arity guard is never reached.
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
      # The command has no handler (handler-less); dispatcher returns unknown_tool error.
      # That's fine — we're testing the guard doesn't fire.
      result = dispatch("/login 123456")
      if result.is_a?(Pito::Slash::Result::Error)
        expect(result.message_key).not_to eq("pito.slash.errors.too_many_args")
      end
    end
  end

  # ── /themes — 0 positional slots, dispatcher guard fires for extra args ──────

  describe "/themes — zero positional slots (generic guard applies)" do
    it "accepts '/themes' (no args)" do
      result = dispatch("/themes")
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:payload][:sidebar_open]).to eq("theme")
    end
  end
end
