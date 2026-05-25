# FB-test-infra (2026-05-22). Pito::CableBroadcaster spec.
require "rails_helper"

RSpec.describe Pito::CableBroadcaster do
  describe ".broadcast_status_bar" do
    it "broadcasts to the canonical pito:status_bar channel with the default kind 'data'" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "pito:status_bar",
        { kind: "data", payload: { busy: 1 }, ts: kind_of(String) }
      )
      described_class.broadcast_status_bar({ busy: 1 })
    end

    it "accepts an explicit kind: kwarg and stringifies it" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "pito:status_bar",
        { kind: "sidekiq", payload: { busy: 1 }, ts: kind_of(String) }
      )
      described_class.broadcast_status_bar({ busy: 1 }, kind: :sidekiq)
    end

    # FB-test-infra (2026-05-22) — Regression: lock the two
    # self-describing kinds the dev/test rake depends on (`sidekiq` /
    # `notifications`). The TST controller routes each through the
    # KIND_HANDLERS registry; if any of these are renamed the test
    # surface stops painting. (`sync` was dropped from the broadcaster
    # surface — sync state is no longer externally settable; the sync
    # indicator pulses on any cable activity.)
    it "emits kind: 'sidekiq' for the sidekiq-stats test envelope" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "pito:status_bar",
        { kind: "sidekiq", payload: { busy: 3, enqueued: 0, retry: 0 }, ts: kind_of(String) }
      )
      described_class.broadcast_status_bar({ busy: 3, enqueued: 0, retry: 0 }, kind: :sidekiq)
    end

    it "emits kind: 'notifications' for the future-count test envelope" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "pito:status_bar",
        { kind: "notifications", payload: { future_count: 3 }, ts: kind_of(String) }
      )
      described_class.broadcast_status_bar({ future_count: 3 }, kind: :notifications)
    end

    it "always emits an ISO8601 ts on the envelope" do
      captured = nil
      allow(ActionCable.server).to receive(:broadcast) { |_chan, envelope| captured = envelope }
      described_class.broadcast_status_bar({ ok: true })
      expect(captured[:ts]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it "pins to STATUS_BAR_CHANNEL constant" do
      expect(described_class::STATUS_BAR_CHANNEL).to eq("pito:status_bar")
    end
  end

  describe ".broadcast_panel" do
    it "broadcasts to a pito:-prefixed channel with kind + payload + ts" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "pito:home:stack",
        { kind: "indeterminate", payload: { step: 2 }, ts: kind_of(String) }
      )
      described_class.broadcast_panel("pito:home:stack", kind: "indeterminate", payload: { step: 2 })
    end

    it "raises ArgumentError for a channel name that does not start with pito:" do
      expect {
        described_class.broadcast_panel("home:stack", kind: "x", payload: {})
      }.to raise_error(ArgumentError, /must start with pito:/)
    end

    it "accepts deeper sub-panel grammar (pito:home:stack:meilisearch)" do
      expect(ActionCable.server).to receive(:broadcast).with("pito:home:stack:meilisearch", anything)
      described_class.broadcast_panel("pito:home:stack:meilisearch", kind: "complete", payload: {})
    end
  end

  # 2026-05-25 (sync-rebuild) — server-side sync-state gate.
  # Disabled targets never reach the broadcast call.
  describe ".broadcast_panel — sync-state suppression gate" do
    it "drops the broadcast when the panel target is disabled" do
      AppSetting.set_sync("home.stack", false)
      expect(ActionCable.server).not_to receive(:broadcast)
      described_class.broadcast_panel("pito:home:stack", kind: "indeterminate", payload: {})
    end

    it "drops the broadcast when the parent panel target is disabled" do
      AppSetting.set_sync("home.stack", false)
      expect(ActionCable.server).not_to receive(:broadcast)
      described_class.broadcast_panel("pito:home:stack:voyage", kind: "complete", payload: {})
    end

    it "drops the broadcast when the master 'app' switch is off" do
      AppSetting.set_sync("app", false)
      expect(ActionCable.server).not_to receive(:broadcast)
      described_class.broadcast_panel("pito:home:security", kind: "data", payload: {})
    end

    it "fires the broadcast when every link in the chain is enabled" do
      AppSetting.set_sync("app", true)
      AppSetting.set_sync("home.stack", true)
      AppSetting.set_sync("home.stack.voyage", true)
      expect(ActionCable.server).to receive(:broadcast).with("pito:home:stack:voyage", anything)
      described_class.broadcast_panel("pito:home:stack:voyage", kind: "complete", payload: {})
    end

    it "leaves non-registered channel grammars alone (no gate, broadcast fires)" do
      # `pito:settings:stack:*` is a legacy grammar not in the sync
      # registry; the gate is a no-op for it (broadcast still fires
      # so the legacy reindex jobs keep working).
      AppSetting.set_sync("app", false)
      expect(ActionCable.server).to receive(:broadcast).with("pito:settings:stack:meilisearch", anything)
      described_class.broadcast_panel("pito:settings:stack:meilisearch", kind: "complete", payload: {})
    end
  end

  # 2026-05-25 — canonical convenience wrappers for pause + uncertain kinds.
  describe ".broadcast_pause" do
    it "emits kind 'pause' on the given target stream with the correct payload shape" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "pito:home:stack",
        {
          kind: "pause",
          payload: { target: "pito:home:stack", paused: true, ts: kind_of(String) },
          ts: kind_of(String)
        }
      )
      described_class.broadcast_pause(target: "pito:home:stack", paused: true)
    end

    it "coerces paused to a boolean" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "pito:home:stack",
        hash_including(payload: hash_including(paused: false))
      )
      described_class.broadcast_pause(target: "pito:home:stack", paused: nil)
    end

    it "honors the sync-enabled gate (broadcast suppressed when target is disabled)" do
      AppSetting.set_sync("home.stack", false)
      expect(ActionCable.server).not_to receive(:broadcast)
      described_class.broadcast_pause(target: "pito:home:stack", paused: true)
    end

    it "raises ArgumentError when the target does not start with pito:" do
      expect {
        described_class.broadcast_pause(target: "home:stack", paused: false)
      }.to raise_error(ArgumentError, /must start with pito:/)
    end
  end

  describe ".broadcast_uncertain" do
    it "emits kind 'uncertain' on the given target stream with the correct payload shape" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "pito:home:security",
        {
          kind: "uncertain",
          payload: { target: "pito:home:security", uncertain: true, reason: "API timeout", ts: kind_of(String) },
          ts: kind_of(String)
        }
      )
      described_class.broadcast_uncertain(target: "pito:home:security", reason: "API timeout")
    end

    it "always sets uncertain: true in the payload" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "pito:home:security",
        hash_including(payload: hash_including(uncertain: true))
      )
      described_class.broadcast_uncertain(target: "pito:home:security", reason: "unknown")
    end

    it "stringifies the reason arg" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "pito:home:security",
        hash_including(payload: hash_including(reason: "timed_out"))
      )
      described_class.broadcast_uncertain(target: "pito:home:security", reason: :timed_out)
    end

    it "honors the sync-enabled gate (broadcast suppressed when target is disabled)" do
      AppSetting.set_sync("home.security", false)
      expect(ActionCable.server).not_to receive(:broadcast)
      described_class.broadcast_uncertain(target: "pito:home:security", reason: "timeout")
    end

    it "raises ArgumentError when the target does not start with pito:" do
      expect {
        described_class.broadcast_uncertain(target: "home:security", reason: "x")
      }.to raise_error(ArgumentError, /must start with pito:/)
    end
  end

  describe ".broadcast_sync_state" do
    it "broadcasts a sync_state envelope on pito:sync_state with the canonical payload shape" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "pito:sync_state",
        {
          kind: "sync_state",
          payload: { target: "home.stack.meilisearch", enabled: true },
          ts: kind_of(String)
        }
      )
      described_class.broadcast_sync_state(target: "home.stack.meilisearch", enabled: true)
    end

    it "stringifies the target arg" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "pito:sync_state",
        hash_including(payload: hash_including(target: "home.stack"))
      )
      described_class.broadcast_sync_state(target: :"home.stack", enabled: false)
    end

    it "coerces enabled to a boolean" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "pito:sync_state",
        hash_including(payload: hash_including(enabled: false))
      )
      described_class.broadcast_sync_state(target: "app", enabled: nil)
    end

    it "pins to the SYNC_STATE_CHANNEL constant" do
      expect(described_class::SYNC_STATE_CHANNEL).to eq("pito:sync_state")
    end
  end
end
