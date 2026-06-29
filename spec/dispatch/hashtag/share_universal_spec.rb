# frozen_string_literal: true

require "rails_helper"

# ── Share universal verbs — autosuggest surfaces share/revoke/unshare ─────────
#
# RULE: share/revoke/unshare must appear in the suggestions engine's action
# palette for ANY live reply_handle event, regardless of the event's reply_target.
# These verbs are universal — they don't belong to any specific handler.
#
# This spec uses the suggestions engine directly (via #follow_up_actions_with_target
# exposed through the public Engine.call interface) to assert that:
#   1. share/revoke/unshare appear in the palette for an event with nil reply_target.
#   2. share/revoke/unshare appear in the palette for an event with "video_detail"
#      reply_target (in addition to video_detail's own actions).
#   3. unfold is NOT offered by the normal suggestions engine — it is only a
#      route at POST /share/:uuid/unfold, not a hashtag action.
#   4. An unknown handle still returns no actions (guard against false positives).
#
# Pattern mirrors spec/dispatch/hashtag/video_detail_matrix_spec.rb.

RSpec.describe "Share universal verbs — autosuggest surface", type: :service do
  before(:all) { Pito::FollowUp::Registry.register_all! }

  let(:conversation) { Conversation.create! }
  let(:turn) { conversation.turns.create!(position: 1, input_kind: :chat, input_text: "hi") }

  def call(input, cursor: nil)
    cursor ||= input.length
    Pito::Suggestions::Engine.call(input:, cursor:, conversation:)
  end

  # ── nil reply_target (no specific handler) ──────────────────────────────────

  describe "event with nil reply_target (no registered handler)" do
    let(:handle) { "bare-abc123" }

    before do
      Event.create_with_position!(
        conversation:, turn:, kind: :system,
        payload: { "reply_handle" => handle, "body" => "a bare shareable message" }
        # NOTE: no reply_target — universal actions should still surface
      )
    end

    subject(:labels) { call("##{handle} ")[:menu_items].map { |i| i[:label] } }

    it "includes 'share' in the palette" do
      expect(labels).to include("share")
    end

    it "includes 'revoke' in the palette" do
      expect(labels).to include("revoke")
    end

    it "includes 'unshare' in the palette" do
      expect(labels).to include("unshare")
    end

    it "does NOT include 'unfold' in the palette (unfold is share-page-only)" do
      expect(labels).not_to include("unfold")
    end
  end

  # ── video_detail reply_target — universal verbs appended to specific actions ─

  describe "event with video_detail reply_target" do
    let(:handle) { "vd-share-789" }

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

    it "includes 'revoke' alongside video_detail actions" do
      expect(labels).to include("revoke")
    end

    it "includes 'unshare' alongside video_detail actions" do
      expect(labels).to include("unshare")
    end

    it "still includes video_detail-specific actions (rm, reindex, etc.)" do
      expect(labels).to include("rm", "reindex", "link", "unlink")
    end

    it "does NOT include duplicate share entries" do
      expect(labels.count("share")).to eq(1)
    end
  end

  # ── game_list reply_target — universal verbs appended to specific actions ────

  describe "event with game_list reply_target" do
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
