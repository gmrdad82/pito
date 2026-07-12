# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::ActionDispatcher do
  # Isolate with a fresh registry snapshot.
  around do |example|
    saved = Pito::ActionRegistry.instance_variable_get(:@registry).dup
    Pito::ActionRegistry.reset!
    example.run
    Pito::ActionRegistry.instance_variable_set(:@registry, saved)
  end

  def define_simple(name, confirmation: nil)
    Pito::ActionRegistry.define(
      name,
      path:     -> { "/#{name}" },
      method:   :post,
      i18n_key: "pito.actions.#{name}",
      confirmation: confirmation
    )
  end

  # ── Unknown action ────────────────────────────────────────────────────────

  describe ".dispatch — unknown action name" do
    it "returns status: :error with code: :unknown_action" do
      result = described_class.dispatch(:nonexistent)
      expect(result.status).to eq(:error)
      expect(result.error[:code]).to eq(:unknown_action)
    end

    it "is not a success" do
      result = described_class.dispatch(:nonexistent)
      expect(result.success?).to be false
    end
  end

  # ── Confirmation gate ──────────────────────────────────────────────────────

  describe ".dispatch — action with confirmation, confirm: false (default)" do
    before do
      define_simple(:destructive, confirmation: { title: "Really?", danger: true })
    end

    it "returns status: :confirmation_required" do
      result = described_class.dispatch(:destructive)
      expect(result.status).to eq(:confirmation_required)
    end

    it "is confirmation_required?" do
      result = described_class.dispatch(:destructive)
      expect(result.confirmation_required?).to be true
    end

    it "payload includes the action name" do
      result = described_class.dispatch(:destructive)
      expect(result.payload[:action]).to eq(:destructive)
    end

    it "payload includes danger flag" do
      result = described_class.dispatch(:destructive)
      expect(result.payload[:danger]).to be true
    end
  end

  # ── Confirmed execution ───────────────────────────────────────────────────

  describe ".dispatch — action with confirmation, confirm: true" do
    before do
      define_simple(:exec_action, confirmation: { title: "Sure?" })
    end

    it "does not return confirmation_required" do
      # The execution path raises NotImplementedError (stub not wired yet);
      # we assert it proceeds past the confirmation gate.
      result = begin
        described_class.dispatch(:exec_action, {}, confirm: true)
      rescue NotImplementedError
        # Expected — execution stub not yet wired.
        :raised_not_implemented
      end
      expect(result).to eq(:raised_not_implemented)
    end
  end

  # ── No-confirmation action ────────────────────────────────────────────────

  describe ".dispatch — action without confirmation" do
    before { define_simple(:safe_action) }

    it "proceeds to execution (does not stop at confirmation gate)" do
      result = begin
        described_class.dispatch(:safe_action)
      rescue NotImplementedError
        :raised_not_implemented
      end
      expect(result).to eq(:raised_not_implemented)
    end
  end

  # ── Result struct helpers ─────────────────────────────────────────────────

  describe "Result" do
    it "success? is true when error is nil" do
      r = Pito::ActionDispatcher::Result.new(status: :completed, payload: {}, error: nil)
      expect(r.success?).to be true
    end

    it "success? is false when error is present" do
      r = Pito::ActionDispatcher::Result.new(status: :error, payload: nil,
                                              error: { code: :unknown_action })
      expect(r.success?).to be false
    end

    it "confirmation_required? is true only for :confirmation_required status" do
      r = Pito::ActionDispatcher::Result.new(status: :confirmation_required, payload: {})
      expect(r.confirmation_required?).to be true
      r2 = Pito::ActionDispatcher::Result.new(status: :completed, payload: {})
      expect(r2.confirmation_required?).to be false
    end
  end
end
