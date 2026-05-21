require "rails_helper"

# ADR 0018 — Action bus + cable architecture.
#
# `Pito::CableBroadcaster` is the canonical broadcast entry point. The
# specs lock the envelope (`kind`, `payload`, `ts`) + the channel grammar
# guard (panel channels must start with `pito:`).
RSpec.describe Pito::CableBroadcaster do
  describe ".broadcast_status_bar" do
    it "broadcasts to the canonical pito:status_bar channel with kind=data" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "pito:status_bar",
        hash_including(kind: "data", payload: { sync_state: "syncing" })
      )

      described_class.broadcast_status_bar(sync_state: "syncing")
    end

    it "stamps an ISO8601 timestamp" do
      expect(ActionCable.server).to receive(:broadcast) do |_channel, message|
        expect(message[:ts]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      described_class.broadcast_status_bar(busy: 0)
    end
  end

  describe ".broadcast_panel" do
    it "broadcasts to the named pito:<screen>:<panel> channel" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "pito:settings:stack:meilisearch",
        hash_including(kind: "reindex_event", payload: { state: "running" })
      )

      described_class.broadcast_panel(
        "pito:settings:stack:meilisearch",
        kind: "reindex_event",
        payload: { state: "running" }
      )
    end

    it "raises ArgumentError when the channel does not follow the pito: grammar" do
      expect {
        described_class.broadcast_panel("custom_channel", kind: "x", payload: {})
      }.to raise_error(ArgumentError, /pito:/)
    end

    it "stamps an ISO8601 timestamp on every panel broadcast" do
      expect(ActionCable.server).to receive(:broadcast) do |_channel, message|
        expect(message[:ts]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        expect(message[:kind]).to eq("progress")
        expect(message[:payload]).to eq({ pct: 42 })
      end

      described_class.broadcast_panel(
        "pito:settings:stack:voyage",
        kind: "progress",
        payload: { pct: 42 }
      )
    end
  end
end
