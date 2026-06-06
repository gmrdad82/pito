# frozen_string_literal: true

require "rails_helper"

# NOTE: BulkDeleteJob depends on BulkOperation + BulkOperationItem models
# which are not yet in the schema. The specs stub those models to exercise
# the orchestration logic (serial destroy path, cascade, idempotent
# re-run, finalize_if_complete) without requiring the tables to exist.

RSpec.describe BulkDeleteJob, type: :job do
  # ── Helpers ──────────────────────────────────────────────────────
  let(:target_record) do
    double("Channel_record", destroy: true, errors: double(full_messages: []))
  end

  let(:item) do
    double(
      "BulkOperationItem",
      id:                1,
      target_type:       "Channel",
      target_id:         10,
      target:            target_record,
      bulk_operation_id: 42,
      update!:           true
    )
  end

  let(:items_relation) do
    rel = double("ItemsRelation")
    allow(rel).to receive(:order).with(:id).and_return(rel)
    allow(rel).to receive(:any?).and_return(true)
    allow(rel).to receive(:first).and_return(item)
    allow(rel).to receive(:size).and_return(1)
    allow(rel).to receive(:each_with_index).and_yield(item, 0)
    allow(rel).to receive(:each).and_yield(item)
    rel
  end

  let(:operation_double) do
    double(
      "BulkOperation",
      id:                   42,
      bulk_operation_items: items_relation,
      completed_at:         nil,
      update!:              true
    )
  end

  before do
    bulk_op_class = Class.new
    stub_const("BulkOperation", bulk_op_class)
    without_partial_double_verification do
      allow(BulkOperation).to receive(:find).with(42).and_return(operation_double)
      allow(BulkOperation).to receive(:find_by).with(id: 42).and_return(operation_double)
      allow(BulkOperation).to receive(:find_by).with(id: 999).and_return(nil)
    end

    # Silence Turbo broadcasts
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    it "marks the operation as running" do
      expect(operation_double).to receive(:update!).with(status: :running)
      described_class.new.perform(42)
    end

    it "destroys the target record via serial path" do
      expect(target_record).to receive(:destroy).and_return(true)
      described_class.new.perform(42)
    end

    it "marks the item as succeeded when destroy succeeds" do
      expect(item).to receive(:update!).with(status: :succeeded)
      described_class.new.perform(42)
    end

    it "marks the operation as completed when all items succeed" do
      allow(item).to receive(:update!)
      expect(operation_double).to receive(:update!).with(hash_including(status: :completed))
      described_class.new.perform(42)
    end

    context "when destroy returns false (validation failure)" do
      before do
        allow(target_record).to receive(:destroy).and_return(false)
        allow(target_record.errors).to receive(:full_messages).and_return([ "Cannot delete" ])
      end

      it "marks the item as failed with the error details" do
        expect(item).to receive(:update!).with(
          hash_including(status: :failed, error_message: "Cannot delete")
        )
        described_class.new.perform(42)
      end

      it "marks the operation as failed" do
        allow(item).to receive(:update!)
        expect(operation_double).to receive(:update!).with(hash_including(status: :failed))
        described_class.new.perform(42)
      end
    end
  end

  describe ".finalize_if_complete" do
    let(:items_query) { double("Items") }

    before do
      allow(operation_double).to receive(:bulk_operation_items).and_return(items_query)
      allow(items_query).to receive(:where).with(status: %i[pending running]).and_return(
        double(exists?: false)
      )
      allow(items_query).to receive(:where).with(status: :failed).and_return(
        double(exists?: false)
      )
    end

    it "marks operation completed when no items are still pending/running" do
      expect(operation_double).to receive(:update!).with(hash_including(status: :completed))
      described_class.finalize_if_complete(42)
    end

    it "marks operation failed when some items failed" do
      allow(items_query).to receive(:where).with(status: :failed).and_return(
        double(exists?: true)
      )
      expect(operation_double).to receive(:update!).with(hash_including(status: :failed))
      described_class.finalize_if_complete(42)
    end

    it "is a no-op when the operation is already complete" do
      allow(operation_double).to receive(:completed_at).and_return(Time.current)
      expect(operation_double).not_to receive(:update!)
      described_class.finalize_if_complete(42)
    end

    it "is a no-op when operation is not found" do
      expect { described_class.finalize_if_complete(999) }.not_to raise_error
    end
  end
end
