# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: `find` (recognition only, DB mocked) ──────────────────────
#
# RULE: every input is recognized — no exception. We test what the dispatcher
# UNDERSTANDS, not what executes: zero DB access, zero factories.
#
# `find` is an NL-CORPUS-ONLY tool (3.0.1 P6) — config/pito/tools.yml declares
# ONLY `description:` + `nl_examples:` for it (plus a schema-satisfying empty
# `reply: {}` stub), no `chat:`/`slash:` branch. Consequently:
#
#   • Pito::Grammar::ConfigSource#chat_specs builds one Spec PER tool that
#     declares a `chat:` key — find no longer does, so NO grammar spec named
#     :find exists at all.
#   • `parsed_intent("find …")` resolves verb → nil (nothing matches the
#     "find" token), handler → nil, `known: false` — exactly like any other
#     unrecognized word (see spec/dispatch/chat_recognition_spec.rb's "unknown
#     verbs" section).
#   • That `known: false` is the fix: it lets `Pito::Chat::Handlers::Unknown`
#     (the NL gate) see the FULL raw utterance instead of a chat: block
#     first-token-capturing "find" into a permanent tool_not_implemented dead
#     end — the 3.0.0 bug ("find vids about tekken", find's own documented
#     example, returned tool_not_implemented every time).
#
# Before 3.0.1, `find` DID resolve to a grammar spec (verb :find) with no
# registered handler, and this file pinned THAT shape (known: false via a
# handler-lookup miss, not via a missing spec). It now pins the opposite:
# `find` must never again capture the first token at all.

RSpec.describe "Dispatch matrix — find (recognition, NL-corpus-only, DB mocked)", type: :dispatch do
  # No DB access ever occurs — zero before-hooks needed.
  # `parsed_intent` is provided by spec/support/dispatch_intent.rb (auto-included).

  # ── Config invariant — find declares no chat branch ──────────────────────────
  it "config/pito/tools.yml declares no chat branch for :find" do
    expect(Pito::Dispatch::Config.tool(:find)).not_to have_key(:chat)
  end

  # ── Registry invariant — no handler is registered for :find ─────────────────
  it "Pito::Chat::Registry has no handler for :find (never did)" do
    expect(Pito::Chat::Registry.lookup(:find)).to be_nil
  end

  # ── Recognition matrix — representative inputs ───────────────────────────────
  #
  # Every input whose first token is "find" now falls straight through to the
  # unknown/NL path — no grammar spec captures it, so canonicalization never
  # happens and the handler lookup is never attempted.
  #
  # Inputs exercised:
  #   bare verb         — no args (should resolve to no verb, not :find)
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

      it "resolves to no verb (no grammar spec matches \"find\")" do
        expect(intent[:tool]).to be_nil
      end

      it "handler is nil" do
        expect(intent[:handler]).to be_nil
      end

      it "known: false (falls through to the unknown/NL path, where the NL gate can now see it)" do
        expect(intent[:known]).to be false
      end
    end
  end
end
