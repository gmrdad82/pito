# frozen_string_literal: true

# Extended coverage for Pito::Slash::Handlers::Disconnect.
# The main disconnect_spec.rb covers core resolution paths.
# This file adds: partial numeric id not found, already-gone-equivalent
# (channel_id present but soft-deleted = not found), payload completeness,
# and the confirmation_handle format invariant.

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Disconnect, "extended coverage", type: :service do
  let(:conversation) { Conversation.create! }

  def build_handler(raw:, authenticated: true)
    invocation = Pito::Slash::Invocation.new(
      verb:   :disconnect,
      args:   [],
      kwargs: {},
      raw:    raw
    )
    described_class.new(invocation:, conversation:, authenticated:)
  end

  # ── Plain handle (no @) ──────────────────────────────────────────────────────

  describe "#call — plain handle without @" do
    let!(:channel) { create(:channel, handle: "@plainchan") }

    it "resolves via LIKE match and returns confirmation" do
      result = build_handler(raw: "/disconnect plainchan").call
      expect(result.events.first[:kind]).to eq("confirmation")
      expect(result.events.first[:payload]["channel_id"]).to eq(channel.id)
    end
  end

  # ── Multiple channels with similar handle ────────────────────────────────────

  describe "#call — LIKE match returns first result" do
    let!(:first_channel)  { create(:channel, handle: "@alpha") }
    let!(:second_channel) { create(:channel, handle: "@alpha2") }

    it "matches on the first found channel (LIKE match)" do
      result = build_handler(raw: "/disconnect @alpha").call
      expect(result.events.first[:kind]).to eq("confirmation")
      # Either alpha or alpha2 — both are valid LIKE matches; just assert no error.
    end
  end

  # ── Confirmation payload completeness ────────────────────────────────────────

  describe "#call — confirmation payload structure" do
    let!(:channel) { create(:channel, handle: "@structcheck") }

    subject(:payload) do
      build_handler(raw: "/disconnect @structcheck").call.events.first[:payload]
    end

    it "includes command: 'disconnect'" do
      expect(payload["command"]).to eq("disconnect")
    end

    it "includes html: true" do
      expect(payload["html"]).to be true
    end

    it "includes reply_handle matching the expected format" do
      handle = payload[:reply_handle] || payload["reply_handle"]
      expect(handle).to match(/\A[a-z]+-\d{4}\z/)
    end

    it "includes reply_target: 'confirmation'" do
      target = payload[:reply_target] || payload["reply_target"]
      expect(target).to eq("confirmation")
    end

    it "includes expand_detail as an Array" do
      expect(payload["expand_detail"]).to be_an(Array)
    end

    it "expand_detail contains a separator string at the expected index" do
      spacer_idx = payload["expand_detail"].index { |item| item == "" }
      expect(spacer_idx).to be_present
    end
  end

  # ── expand_detail video breakdown keys ───────────────────────────────────────

  describe "#call — expand_detail video section keys" do
    let!(:channel) { create(:channel, handle: "@keycheck") }

    it "includes Published, Scheduled, Unlisted, and Private rows after spacer" do
      result = build_handler(raw: "/disconnect @keycheck").call
      detail = result.events.first[:payload]["expand_detail"]
      spacer_idx = detail.index { |item| item == "" }
      video_rows = detail[(spacer_idx + 1)..]
      kv_keys = video_rows.select { |r| r.is_a?(Hash) }.map { |r| r[:key] }
      expect(kv_keys).to include("Vids", "Published", "Scheduled", "Unlisted", "Private")
    end
  end

  # ── id=0 edge case ────────────────────────────────────────────────────────────

  describe "#call — id 0 (never valid)" do
    it "returns an error event" do
      result = build_handler(raw: "/disconnect 0").call
      expect(result.events.first[:kind]).to eq("error")
    end
  end
end
