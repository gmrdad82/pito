# frozen_string_literal: true

require "rails_helper"

# NOTE: BulkSyncJob depends on BulkOperation + BulkOperationItem models which
# are not yet in the schema. The specs below stub those models to exercise the
# job's orchestration logic (convention-based dispatch, progress broadcast,
# partial-failure resilience) without requiring the tables to exist.

RSpec.describe BulkSyncJob, type: :job do
  # ── Stub AR models that don't yet exist in the schema ────────────
  let(:item_double) do
    double(
      "BulkOperationItem",
      id:              1,
      target_type:     "Game",
      target_id:       99,
      status_skipped?: false,
      update!:         true
    )
  end

  let(:items_relation) do
    relation = double("ItemsRelation")
    allow(relation).to receive(:find_each).and_yield(item_double)
    allow(relation).to receive(:size).and_return(1)
    relation
  end

  let(:operation_double) do
    double(
      "BulkOperation",
      id:                   42,
      bulk_operation_items: items_relation,
      update!:              true
    )
  end

  before do
    bulk_op_class = Class.new
    stub_const("BulkOperation", bulk_op_class)
    without_partial_double_verification do
      allow(BulkOperation).to receive(:find).with(42).and_return(operation_double)
    end

    # Silence Turbo broadcasts
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    # The convention-based sync class for "Game" is GameSync
    allow(GameSync).to receive(:perform_later)
  end

  describe "#perform" do
    it "marks the operation as running" do
      expect(operation_double).to receive(:update!).with(status: :running)
      described_class.new.perform(42)
    end

    it "dispatches the sync job for each non-skipped item" do
      expect(GameSync).to receive(:perform_later).with(99)
      described_class.new.perform(42)
    end

    it "marks the item as succeeded when dispatch succeeds" do
      expect(item_double).to receive(:update!).with(status: :succeeded)
      described_class.new.perform(42)
    end

    it "marks the operation as completed when all items succeed" do
      expect(operation_double).to receive(:update!).with(
        hash_including(status: :completed)
      )
      described_class.new.perform(42)
    end

    context "when a skipped item is encountered" do
      before { allow(item_double).to receive(:status_skipped?).and_return(true) }

      it "does not dispatch a sync job for the skipped item" do
        expect(GameSync).not_to receive(:perform_later)
        described_class.new.perform(42)
      end
    end

    context "when an item's sync class does not exist" do
      before { allow(item_double).to receive(:target_type).and_return("Widget") }

      it "marks the item as failed with an appropriate message" do
        expect(item_double).to receive(:update!).with(
          hash_including(status: :failed, error_message: /No sync job/)
        )
        described_class.new.perform(42)
      end

      it "marks the operation as failed" do
        allow(item_double).to receive(:update!)
        expect(operation_double).to receive(:update!).with(
          hash_including(status: :failed)
        )
        described_class.new.perform(42)
      end
    end

    context "when dispatch raises for one item" do
      before do
        allow(GameSync).to receive(:perform_later).and_raise(StandardError, "connection refused")
      end

      it "marks the item as failed with the error message" do
        expect(item_double).to receive(:update!).with(
          hash_including(status: :failed, error_message: "connection refused")
        )
        described_class.new.perform(42)
      end

      it "marks the operation as failed" do
        allow(item_double).to receive(:update!)
        expect(operation_double).to receive(:update!).with(hash_including(status: :failed))
        described_class.new.perform(42)
      end
    end
  end
end
