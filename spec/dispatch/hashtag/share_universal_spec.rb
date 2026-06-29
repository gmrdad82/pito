# frozen_string_literal: true

require "rails_helper"

# ── Share universal verbs — autosuggest palette gating ───────────────────────
#
# RULE: `share` is ALWAYS offered on any live reply_handle event. `revoke` and
# `unshare` are offered ONLY when a Share row exists for that event.
#
# After a successful `share` → all three verbs appear in the palette.
# After `revoke` (or before any share) → only `share` appears.
#
# This spec drives the suggestions engine directly (via Engine.call) to assert
# the autosuggest surface. Pattern mirrors spec/dispatch/hashtag/*_matrix_spec.rb.

RSpec.describe "Share universal verbs — autosuggest surface", type: :service do
  before(:all) { Pito::FollowUp::Registry.register_all! }

  let(:conversation) { Conversation.create! }
  let(:turn) { conversation.turns.create!(position: 1, input_kind: :chat, input_text: "hi") }

  def call(input, cursor: nil)
    cursor ||= input.length
    Pito::Suggestions::Engine.call(input:, cursor:, conversation:)
  end

  # ── event with no Share (un-shared) ─────────────────────────────────────────

  describe "un-shared event (no Share record)" do
    let(:handle) { "bare-abc123" }

    before do
      Event.create_with_position!(
        conversation:, turn:, kind: :system,
        payload: { "reply_handle" => handle, "body" => "a bare shareable message" }
        # no reply_target — universal actions still surface
      )
    end

    subject(:labels) { call("##{handle} ")[:menu_items].map { |i| i[:label] } }

    it "includes 'share' in the palette" do
      expect(labels).to include("share")
    end

    it "does NOT include 'revoke' when no Share exists" do
      expect(labels).not_to include("revoke")
    end

    it "does NOT include 'unshare' when no Share exists" do
      expect(labels).not_to include("unshare")
    end

    it "does NOT include 'unfold' in the palette (unfold is share-page-only)" do
      expect(labels).not_to include("unfold")
    end
  end

  # ── event WITH a Share (shared) ──────────────────────────────────────────────

  describe "shared event (Share record exists)" do
    let(:handle) { "shared-def456" }
    let!(:event) do
      Event.create_with_position!(
        conversation:, turn:, kind: :system,
        payload: { "reply_handle" => handle, "body" => "shared message" }
      )
    end

    before { Share.create!(event:, conversation:) }

    subject(:labels) { call("##{handle} ")[:menu_items].map { |i| i[:label] } }

    it "includes 'share' in the palette" do
      expect(labels).to include("share")
    end

    it "includes 'revoke' when a Share exists" do
      expect(labels).to include("revoke")
    end

    it "includes 'unshare' when a Share exists" do
      expect(labels).to include("unshare")
    end

    it "does NOT include duplicate share entries" do
      expect(labels.count("share")).to eq(1)
    end

    it "does NOT include 'unfold' (unfold is share-page-only)" do
      expect(labels).not_to include("unfold")
    end
  end

  # ── video_detail reply_target — universal verbs appended to specific actions ─

  describe "video_detail event with no Share" do
    let(:handle) { "vd-unshared-789" }

    before do
      Event.create_with_position!(
        conversation:, turn:, kind: :system,
        payload: {
          "reply_handle" => handle,
          "reply_target" => "video_detail",
          "video_id"     => 99
        }
      )
    end

    subject(:labels) { call("##{handle} ")[:menu_items].map { |i| i[:label] } }

    it "includes 'share' alongside video_detail actions" do
      expect(labels).to include("share")
    end

    it "does NOT include 'revoke' (no Share exists)" do
      expect(labels).not_to include("revoke")
    end

    it "does NOT include 'unshare' (no Share exists)" do
      expect(labels).not_to include("unshare")
    end

    it "still includes video_detail-specific actions (rm, reindex, etc.)" do
      expect(labels).to include("rm", "reindex", "link", "unlink")
    end
  end

  describe "video_detail event WITH a Share" do
    let(:handle) { "vd-share-789" }
    let!(:event) do
      Event.create_with_position!(
        conversation:, turn:, kind: :system,
        payload: {
          "reply_handle" => handle,
          "reply_target" => "video_detail",
          "video_id"     => 99
        }
      )
    end

    before { Share.create!(event:, conversation:) }

    subject(:labels) { call("##{handle} ")[:menu_items].map { |i| i[:label] } }

    it "includes 'share' alongside video_detail actions" do
      expect(labels).to include("share")
    end

    it "includes 'revoke' alongside video_detail actions (Share exists)" do
      expect(labels).to include("revoke")
    end

    it "includes 'unshare' alongside video_detail actions (Share exists)" do
      expect(labels).to include("unshare")
    end

    it "still includes video_detail-specific actions (rm, reindex, etc.)" do
      expect(labels).to include("rm", "reindex", "link", "unlink")
    end

    it "does NOT include duplicate share entries" do
      expect(labels.count("share")).to eq(1)
    end
  end

  # ── game_list reply_target — spot-check ──────────────────────────────────────

  describe "game_list event with no Share" do
    let(:handle) { "gl-share-456" }

    before do
      Event.create_with_position!(
        conversation:, turn:, kind: :system,
        payload: {
          "reply_handle" => handle,
          "reply_target" => "game_list",
          "body"         => "games"
        }
      )
    end

    subject(:labels) { call("##{handle} ")[:menu_items].map { |i| i[:label] } }

    it "includes 'share' alongside game_list actions" do
      expect(labels).to include("share")
    end

    it "does NOT include 'revoke' (no Share)" do
      expect(labels).not_to include("revoke")
    end

    it "includes game_list-specific actions (show, with, without)" do
      expect(labels).to include("show", "with", "without")
    end
  end

  # ── unknown handle — no false positives ─────────────────────────────────────

  describe "unknown handle (no live follow-up event)" do
    it "returns no menu items for an unrecognised handle" do
      result = call("#no-such-handle-9999 ")
      expect(result[:menu_items]).to be_empty
    end
  end

  # ── consumed event — no actions offered ─────────────────────────────────────

  describe "consumed event" do
    let(:handle) { "consumed-zzz" }

    before do
      Event.create_with_position!(
        conversation:, turn:, kind: :system,
        payload: {
          "reply_handle"    => handle,
          "reply_consumed"  => true,
          "body"            => "already consumed"
        }
      )
    end

    it "returns no menu items when the source event is consumed" do
      result = call("##{handle} ")
      expect(result[:menu_items]).to be_empty
    end
  end
end
