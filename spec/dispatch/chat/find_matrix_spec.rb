# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `find` (recognition only, DB mocked) ──────────────────────
#
# RULE: every input is recognized — no exception. We test what the dispatcher
# UNDERSTANDS, not what executes: zero DB access, zero factories.
#
# `find` is a GRAMMAR-ONLY verb — it exists in the :chat grammar
# (lib/pito/grammar/specs.rb, Spec name: :find, slots: chat_shared_slots) but
# has NO handler class registered in Pito::Chat::Registry. Consequently:
#
#   • `parsed_intent("find …")` resolves verb → :find (via grammar lookup),
#     but handler → nil (nothing registered for :find).
#   • `known: false` — the dispatcher treats grammar-only verbs without a
#     handler as unresolvable; they fall through to the unknown/NL path
#     (Pito::Chat::Handlers::Unknown).
#
# This mirrors the same pattern as slash handler-less specs (:login, :logout,
# :connect), except here it is in the :chat namespace.

RSpec.describe "Dispatch matrix — find (recognition, grammar-only, DB mocked)", type: :dispatch do
  # No DB access ever occurs — zero before-hooks needed.
  # `parsed_intent` is provided by spec/support/dispatch_intent.rb (auto-included).

  # ── Registry invariant — no handler is registered for :find ─────────────────
  it "Pito::Chat::Registry has no handler for :find" do
    expect(Pito::Chat::Registry.lookup(:find)).to be_nil
  end

  # ── Recognition matrix — all representative inputs ───────────────────────────
  #
  # Every input whose first token is "find" resolves via the grammar spec to
  # canonical verb :find, then fails the handler lookup → known: false.
  #
  # Inputs exercised:
  #   bare verb         — no args (should also return :find, not nil verb)
  #   title-style arg   — free-text game title ("elden ring")
  #   id-style arg      — hash-id reference ("#5")
  #   noun+tag arg      — entity noun + genre tag ("games rpg")

  {
    "find"           => "bare verb — no arguments",
    "find elden ring" => "title-style free-text argument",
    "find #5"        => "hash-id reference argument",
    "find games rpg" => "noun + genre tag argument"
  }.each do |input, description|
    describe "#{input.inspect} (#{description})" do
      subject(:intent) { parsed_intent(input) }

      it "routes to :chat stack" do
        expect(intent[:stack]).to eq(:chat)
      end

      it "resolves verb to :find (grammar spec matched)" do
        expect(intent[:verb]).to eq(:find)
      end

      it "handler is nil (no handler registered for :find)" do
        expect(intent[:handler]).to be_nil
      end

      it "known: false (grammar-only verb → falls through to unknown/NL path)" do
        expect(intent[:known]).to be false
      end
    end
  end
end
