require "rails_helper"

# ADR 0018 — Action bus + cable architecture.
#
# Mirrors `meilisearch_reindex_job_spec.rb` against the Voyage AI panel
# channel `pito:settings:stack:voyage`.
RSpec.describe VoyageReindexJob do
  describe "#perform" do
    before do
      AppSetting.start_reindex!
      # The job's REINDEX_SLEEP_SECONDS=8 stub keeps the spec fast.
      stub_const("VoyageReindexJob::REINDEX_SLEEP_SECONDS", 0)
    end
    after { AppSetting.clear_reindex_lock! }

    it "broadcasts running state on entry + complete state on finish" do
      expect(Pito::CableBroadcaster).to receive(:broadcast_panel).with(
        "pito:settings:stack:voyage",
        kind: "reindex_event",
        payload: { state: "running" }
      ).ordered

      expect(Pito::CableBroadcaster).to receive(:broadcast_panel).with(
        "pito:settings:stack:voyage",
        kind: "reindex_event",
        payload: { state: "complete" }
      ).ordered

      allow(ActionCable.server).to receive(:broadcast)
      allow(StackStats::Broadcaster).to receive(:broadcast!)
      allow(StackStatsBroadcastJob).to receive_message_chain(:set, :perform_later)
      allow(BulkVoyageIndexJob).to receive(:perform_later)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      described_class.new.perform
    end
  end
end
