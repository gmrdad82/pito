require "rails_helper"

# ADR 0018 — Action bus + cable architecture.
#
# Job-level coverage for the panel-scoped cable broadcast contract.
# The job MUST emit `running` on entry + `complete` on exit (via the
# `ensure` block) on the canonical
# `pito:settings:stack:meilisearch` channel.
RSpec.describe MeilisearchReindexJob do
  describe "#perform" do
    before { AppSetting.start_reindex! }
    after { AppSetting.clear_reindex_lock! }

    it "broadcasts running state on entry + complete state on finish" do
      expect(Pito::CableBroadcaster).to receive(:broadcast_panel).with(
        "pito:settings:stack:meilisearch",
        kind: "reindex_event",
        payload: { state: "running" }
      ).ordered

      expect(Pito::CableBroadcaster).to receive(:broadcast_panel).with(
        "pito:settings:stack:meilisearch",
        kind: "reindex_event",
        payload: { state: "complete" }
      ).ordered

      # Stub the indexers + the legacy stack_stats broadcaster so we
      # don't exercise Meilisearch in unit-spec territory.
      allow(Game).to receive(:find_each)
      allow(ActionCable.server).to receive(:broadcast)
      allow(StackStats::Broadcaster).to receive(:broadcast!)
      allow(StackStatsBroadcastJob).to receive_message_chain(:set, :perform_later)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      described_class.new.perform
    end

    it "still emits the complete broadcast when the job raises" do
      expect(Pito::CableBroadcaster).to receive(:broadcast_panel).with(
        "pito:settings:stack:meilisearch",
        kind: "reindex_event",
        payload: { state: "running" }
      ).ordered

      expect(Pito::CableBroadcaster).to receive(:broadcast_panel).with(
        "pito:settings:stack:meilisearch",
        kind: "reindex_event",
        payload: { state: "complete" }
      ).ordered

      allow(ActionCable.server).to receive(:broadcast)
      allow(StackStats::Broadcaster).to receive(:broadcast!)
      allow(StackStatsBroadcastJob).to receive_message_chain(:set, :perform_later)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      allow(Game).to receive(:find_each).and_raise(StandardError, "boom")

      expect { described_class.new.perform }.to raise_error(StandardError, "boom")
    end
  end
end
