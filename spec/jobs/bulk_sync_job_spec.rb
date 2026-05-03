require "rails_helper"

RSpec.describe BulkSyncJob, type: :job do
  describe "queue configuration" do
    it "uses the bulk_sync queue, which is processed by the worker" do
      expect(described_class.sidekiq_options["queue"]).to eq("bulk_sync")
      processed_queues = YAML.load_file(Rails.root.join("config", "sidekiq.yml"))[:queues]
      expect(processed_queues).to include("bulk_sync")
    end
  end

  describe "#perform" do
    context "happy path — all channels syncable" do
      let!(:channels) { Array.new(3) { create(:channel) } }
      let!(:operation) do
        op = create(:bulk_operation, kind: :bulk_sync, status: :pending)
        channels.each do |c|
          op.bulk_operation_items.create!(target: c, target_type: "Channel", target_id: c.id, status: :pending)
        end
        op
      end

      before { ChannelSync.jobs.clear }

      it "marks every item succeeded and enqueues a ChannelSync per channel" do
        expect {
          described_class.new.perform(operation.id)
        }.to change(ChannelSync.jobs, :size).by(3)

        operation.reload
        expect(operation.status).to eq("completed")
        expect(operation.completed_at).to be_present
        expect(operation.bulk_operation_items.pluck(:status).uniq).to eq([ "succeeded" ])
      end

      it "dispatches via convention-based <TargetType>Sync mapping (Channel -> ChannelSync)" do
        described_class.new.perform(operation.id)
        enqueued_ids = ChannelSync.jobs.map { |j| j["args"].first }
        expect(enqueued_ids).to match_array(channels.map(&:id))
      end
    end

    context "skip path — pre-skipped items don't fire ChannelSync" do
      let!(:channels) { Array.new(5) { |i| create(:channel) } }
      let!(:operation) do
        op = create(:bulk_operation, kind: :bulk_sync, status: :pending)
        channels.each_with_index do |c, i|
          status = (i == 1 || i == 3) ? :skipped : :pending
          err = (status == :skipped) ? "already syncing" : nil
          op.bulk_operation_items.create!(
            target: c, target_type: "Channel", target_id: c.id,
            status: status, error_message: err
          )
        end
        op
      end

      before { ChannelSync.jobs.clear }

      it "fires ChannelSync only for non-skipped channels" do
        expect {
          described_class.new.perform(operation.id)
        }.to change(ChannelSync.jobs, :size).by(3)

        operation.reload
        items = operation.bulk_operation_items.order(:id).to_a
        expect(items[0].status).to eq("succeeded")
        expect(items[1].status).to eq("skipped")
        expect(items[2].status).to eq("succeeded")
        expect(items[3].status).to eq("skipped")
        expect(items[4].status).to eq("succeeded")
      end

      it "does not enqueue a ChannelSync for the skipped target ids" do
        described_class.new.perform(operation.id)
        enqueued_ids = ChannelSync.jobs.map { |j| j["args"].first }
        expect(enqueued_ids).to include(channels[0].id, channels[2].id, channels[4].id)
        expect(enqueued_ids).not_to include(channels[1].id, channels[3].id)
      end

      it "marks the operation completed when no real failures occurred" do
        described_class.new.perform(operation.id)
        expect(operation.reload.status).to eq("completed")
      end

      it "leaves pre-skipped items completely untouched (status, error_message)" do
        described_class.new.perform(operation.id)
        skipped_items = operation.bulk_operation_items.where(target_id: [ channels[1].id, channels[3].id ])
        skipped_items.each do |item|
          expect(item.status).to eq("skipped")
          expect(item.error_message).to eq("already syncing")
        end
      end
    end

    context "mixed — skip + succeed in one operation" do
      let!(:syncable) { create(:channel) }
      let!(:already_syncing) { create(:channel, :syncing) }
      let!(:operation) do
        op = create(:bulk_operation, kind: :bulk_sync, status: :pending)
        op.bulk_operation_items.create!(target: syncable, target_type: "Channel", target_id: syncable.id, status: :pending)
        op.bulk_operation_items.create!(target: already_syncing, target_type: "Channel", target_id: already_syncing.id, status: :skipped, error_message: "already syncing")
        op
      end

      before { ChannelSync.jobs.clear }

      it "succeeds the syncable, leaves the skipped untouched" do
        described_class.new.perform(operation.id)
        operation.reload
        expect(operation.status).to eq("completed")
        items = operation.bulk_operation_items.order(:id)
        expect(items.first.status).to eq("succeeded")
        expect(items.last.status).to eq("skipped")
        expect(items.last.error_message).to eq("already syncing")
        expect(ChannelSync.jobs.size).to eq(1)
      end
    end

    context "no-fail-fast — a failed item does not abort the loop" do
      let!(:c1) { create(:channel) }
      let!(:c2) { create(:channel) }
      let!(:c3) { create(:channel) }
      let!(:operation) do
        op = create(:bulk_operation, kind: :bulk_sync, status: :pending)
        op.bulk_operation_items.create!(target: c1, target_type: "Channel", target_id: c1.id, status: :pending)
        op.bulk_operation_items.create!(target: c2, target_type: "Channel", target_id: c2.id, status: :pending)
        op.bulk_operation_items.create!(target: c3, target_type: "Channel", target_id: c3.id, status: :pending)
        op
      end

      before do
        ChannelSync.jobs.clear
        # Make ChannelSync.perform_async raise the first time it's called for c2
        allow(ChannelSync).to receive(:perform_async).and_call_original
        allow(ChannelSync).to receive(:perform_async).with(c2.id).and_raise(StandardError, "boom")
      end

      it "marks the failing item failed and continues with the rest" do
        described_class.new.perform(operation.id)
        operation.reload
        items = operation.bulk_operation_items.order(:id).to_a
        expect(items[0].status).to eq("succeeded")
        expect(items[1].status).to eq("failed")
        expect(items[1].error_message).to include("boom")
        expect(items[2].status).to eq("succeeded")
        expect(operation.status).to eq("failed")
      end
    end

    context "convention-based dispatch — unknown target type" do
      # Simulate a future / unknown target_type that has no <X>Sync class. The
      # job must not raise; it must fail the item with a clear error message
      # and continue processing the remaining items.
      let!(:channel) { create(:channel) }
      let!(:operation) do
        op = create(:bulk_operation, kind: :bulk_sync, status: :pending)
        # Real Channel item — should succeed via ChannelSync.
        op.bulk_operation_items.create!(target: channel, target_type: "Channel", target_id: channel.id, status: :pending)
        # Synthetic item with target_type that won't resolve to a sync class.
        # We bypass `target` polymorphic load by using a target_id that won't
        # exist in any model; the job's safe_constantize check fires first.
        item = op.bulk_operation_items.build(target_type: "UnknownType", target_id: 1, status: :pending)
        item.save!(validate: false)
        op
      end

      before { ChannelSync.jobs.clear }

      it "marks the unknown-type item failed with a clear error and fails the operation" do
        described_class.new.perform(operation.id)
        operation.reload
        items = operation.bulk_operation_items.order(:id).to_a
        expect(items[0].status).to eq("succeeded")
        expect(items[1].status).to eq("failed")
        expect(items[1].error_message).to eq("No sync job for UnknownType")
        expect(operation.status).to eq("failed")
      end
    end

    context "broadcasting" do
      let!(:channel) { create(:channel) }
      let!(:operation) do
        op = create(:bulk_operation, kind: :bulk_sync, status: :pending)
        op.bulk_operation_items.create!(target: channel, target_type: "Channel", target_id: channel.id, status: :pending)
        op
      end

      it "broadcasts progress, item status, and final status" do
        expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).at_least(:once)
        described_class.new.perform(operation.id)
      end
    end
  end
end
