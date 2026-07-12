# frozen_string_literal: true

require "rails_helper"

# ── Universal reply per-verb opt-out (G-universal-reply) ────────────────────────
#
# The universal share / unshare|revoke reply actions are offered on every
# followupable event UNLESS the verb that produced it declares
# `universal_reply: false` in config/pito/tools.yml (the `sync` verb is the
# worked example). This suite pins the whole mechanism end to end:
#
#   1. Pito::Dispatch::UniversalReply — the per-verb gate + origin_tool deriver.
#   2. Pito::Share::UniversalActions.tools_for — the palette respects the gate.
#   3. Pito::Share::UniversalActions.intercept? — dispatch short-circuit respects it
#      (and never overrides a verb's own declared reply tokens).
#   4. Pito::Share::UniversalActions#call — the server-side guard refuses a typed
#      `#handle share` on an opted-out message even if the palette were bypassed.
#   5. Pito::Dispatch::Finalizer#persist — the origin_verb stamp + withheld handle.
#   6. Pito::Dispatch::Matrix.mode_for — declared verb tokens resolve BEFORE the
#      universal set is consulted.
RSpec.describe "Universal reply per-verb opt-out", type: :dispatch do
  before do
    Pito::Dispatch::Config.reload!
    Pito::Dispatch::Matrix.reload!
  end

  let(:conversation) { Conversation.create! }

  def make_turn(input_kind:, input_text:)
    conversation.turns.create!(
      position: Turn.next_position_for(conversation),
      input_kind: input_kind,
      input_text: input_text
    )
  end

  def make_event(kind: :system, payload: {})
    turn = make_turn(input_kind: :chat, input_text: "hi")
    Event.create_with_position!(conversation:, turn:, kind:, payload:)
  end

  # ── 1. Pito::Dispatch::UniversalReply ──────────────────────────────────────────

  describe Pito::Dispatch::UniversalReply do
    describe ".opted_out?" do
      it "is true for 'sync' (declares universal_reply: false in the real tools.yml)" do
        expect(described_class.opted_out?("sync")).to be(true)
      end

      it "is false for 'list' (no opt-out declared)" do
        expect(described_class.opted_out?("list")).to be(false)
      end

      it "is false for nil" do
        expect(described_class.opted_out?(nil)).to be(false)
      end

      it "is false for a blank string" do
        expect(described_class.opted_out?("")).to be(false)
      end

      it "is false for an unknown/invented verb (KeyError rescued)" do
        expect(described_class.opted_out?("totally_bogus_verb_xyz")).to be(false)
      end
    end

    describe ".origin_tool" do
      it "resolves a chat turn 'sync channels' to 'sync'" do
        turn = make_turn(input_kind: :chat, input_text: "sync channels")
        expect(described_class.origin_tool(turn)).to eq("sync")
      end

      it "resolves a chat turn 'ls' to 'list' (alias canonicalized by the chat parser)" do
        turn = make_turn(input_kind: :chat, input_text: "ls")
        expect(described_class.origin_tool(turn)).to eq("list")
      end

      it "resolves a hashtag turn '#g3 price 20' to 'price'" do
        turn = make_turn(input_kind: :hashtag, input_text: "#g3 price 20")
        expect(described_class.origin_tool(turn)).to eq("price")
      end

      it "resolves a slash turn '/config' to 'config'" do
        turn = make_turn(input_kind: :slash, input_text: "/config")
        expect(described_class.origin_tool(turn)).to eq("config")
      end

      it "returns nil for a blank input_text" do
        blank_turn = Turn.new(conversation:, position: 1, input_kind: :chat, input_text: "")
        expect(described_class.origin_tool(blank_turn)).to be_nil
      end

      it "returns nil for a nil turn" do
        expect(described_class.origin_tool(nil)).to be_nil
      end
    end

    describe ".allowed_for?" do
      it "is false for an event whose origin_verb is 'sync' (opted out)" do
        event = make_event(payload: { "origin_verb" => "sync" })
        expect(described_class.allowed_for?(event)).to be(false)
      end

      it "is true for an event whose origin_verb is 'list'" do
        event = make_event(payload: { "origin_verb" => "list" })
        expect(described_class.allowed_for?(event)).to be(true)
      end

      it "is true for an event with no origin_verb key (pre-existing rows default to allowed)" do
        event = make_event(payload: { "text" => "hello" })
        expect(described_class.allowed_for?(event)).to be(true)
      end
    end
  end

  # ── 2. Pito::Share::UniversalActions.tools_for ─────────────────────────────────

  describe "Pito::Share::UniversalActions.tools_for" do
    it "offers nothing ([]) for a :system event whose origin_verb is 'sync'" do
      event = make_event(kind: :system, payload: { "origin_verb" => "sync" })
      expect(Pito::Share::UniversalActions.tools_for(event)).to eq([])
    end

    it "includes 'share' for the same shape of event when origin_verb is 'list'" do
      event = make_event(kind: :system, payload: { "origin_verb" => "list" })
      expect(Pito::Share::UniversalActions.tools_for(event)).to include("share")
    end
  end

  # ── 3. Pito::Share::UniversalActions.intercept? ────────────────────────────────

  describe "Pito::Share::UniversalActions.intercept?" do
    it "is true for 'share' on an event with no origin_verb and no reply_target" do
      event = make_event(payload: { "text" => "hello" })
      expect(Pito::Share::UniversalActions.intercept?("share", event:)).to be(true)
    end

    it "is false for 'share' on an event whose origin_verb is 'sync' (opted out)" do
      event = make_event(payload: { "origin_verb" => "sync" })
      expect(Pito::Share::UniversalActions.intercept?("share", event:)).to be(false)
    end

    it "is false for a nonsense token that isn't a universal tool at all" do
      event = make_event(payload: { "text" => "hello" })
      expect(Pito::Share::UniversalActions.intercept?("nonsense", event:)).to be(false)
    end

    # Precedence when a reply_target declares "share" itself (a verb's own
    # declaration always wins over the universal set) is exercised at the Matrix
    # level below ("Pito::Dispatch::Matrix.mode_for precedence") — no reply_target
    # in the current tools.yml redeclares "share" as its own reply action, so
    # there's nothing to construct here; the Matrix example covers the same
    # precedence rule this method leans on (`actions_for(target).include?(token)`).
  end

  # ── 4. Pito::Share::UniversalActions#call server-side guard ───────────────────

  describe "Pito::Share::UniversalActions#call — server-side opt-out guard" do
    it "refuses share on a source_event stamped origin_tool 'sync' with not_available" do
      event  = make_event(payload: { "origin_verb" => "sync", "text" => "hello" })
      result = Pito::Share::UniversalActions.new.call(source_event: event, rest: "share", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.copy.share.not_available")
    end
  end

  # ── 5. Pito::Dispatch::Finalizer#persist ───────────────────────────────────────

  describe Pito::Dispatch::Finalizer do
    let(:finalizer) { described_class.new(conversation:) }

    it "persisting under a chat turn 'sync channels' leaves payload WITHOUT reply_handle and WITH origin_tool 'sync'" do
      turn      = make_turn(input_kind: :chat, input_text: "sync channels")
      persisted = finalizer.persist(events: [ { kind: :system, payload: { "text" => "synced" } } ], turn:)
      payload   = persisted.first.payload

      expect(payload["reply_handle"]).to be_nil
      expect(payload["origin_tool"]).to eq("sync")
    end

    it "persisting under a chat turn 'list games' stamps BOTH reply_handle and origin_tool 'list'" do
      turn      = make_turn(input_kind: :chat, input_text: "list games")
      persisted = finalizer.persist(events: [ { kind: :system, payload: { "text" => "here you go" } } ], turn:)
      payload   = persisted.first.payload

      expect(payload["reply_handle"]).to be_present
      expect(payload["origin_tool"]).to eq("list")
    end
  end

  # ── 6. Pito::Dispatch::Matrix.mode_for precedence ──────────────────────────────

  describe "Pito::Dispatch::Matrix.mode_for precedence — declared tokens beat universals" do
    it "price (declared on game_detail) resolves to its verb-declared mode (:append)" do
      expect(Pito::Dispatch::Matrix.mode_for("game_detail", action: "price")).to eq(:append)
    end

    it "share (universal, not declared on game_detail) still resolves to :append (the universal fallback)" do
      expect(Pito::Dispatch::Matrix.mode_for("game_detail", action: "share")).to eq(:append)
    end

    # A stronger witness for the SAME precedence rule, where the declared mode and
    # the universal fallback actually differ: `sort` is declared :mutate on
    # game_list, while `share` (universal) is :append on every target. If the
    # declared-token path did not run first, "sort" would fall through to the
    # universal/base-mode branches and this would NOT be :mutate.
    it "sort (declared :mutate on game_list) does not get overridden by the universal :append" do
      expect(Pito::Dispatch::Matrix.mode_for("game_list", action: "sort")).to eq(:mutate)
      expect(Pito::Dispatch::Matrix.mode_for("game_list", action: "share")).to eq(:append)
    end
  end
end
