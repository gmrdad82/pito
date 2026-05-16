require "rails_helper"

# Phase 27 v2 spec 02 — Collection composite cover rebuild job.
#
# The job rebuilds the on-disk composite for ONE collection by calling
# `Collections::CoverComposer#call`, then enqueues the NEXT job in the
# chain (if any). The orchestrator builds the chain in alphabetical
# (by name) order; the job pops the head off the tail on success.
#
# Failure semantics: a raise inside the composer propagates out of the
# job (Sidekiq retries the head). The chain does NOT advance on
# failure — by design, a broken composite never trickles down the
# queue.
RSpec.describe CollectionCoverRebuildJob, type: :job do
  let(:composer) { instance_double(Collections::CoverComposer) }

  before do
    allow(Collections::CoverComposer).to receive(:new).and_return(composer)
    allow(composer).to receive(:call).and_return(nil)
    described_class.clear
  end

  describe "Sidekiq options" do
    it "is enqueued on the :default queue" do
      described_class.perform_async(1, [])
      expect(described_class.jobs.last["queue"]).to eq("default")
    end

    it "declares the lock: :until_executed uniqueness intent" do
      opts = described_class.sidekiq_options
      expect(opts["lock"]).to eq(:until_executed)
      expect(opts["on_conflict"]).to eq(:log)
    end
  end

  describe "#perform — single collection (no chain)" do
    let(:collection) { create(:collection, name: "Solo") }

    it "calls the composer for the given collection" do
      described_class.new.perform(collection.id)
      expect(composer).to have_received(:call).with(collection)
    end

    it "does NOT enqueue a follow-up job when remaining_chain is nil" do
      described_class.new.perform(collection.id, nil)
      expect(described_class.jobs).to be_empty
    end

    it "does NOT enqueue a follow-up job when remaining_chain is []" do
      described_class.new.perform(collection.id, [])
      expect(described_class.jobs).to be_empty
    end
  end

  describe "#perform — chained" do
    let(:c_a) { create(:collection, name: "A") }
    let(:c_b) { create(:collection, name: "B") }
    let(:c_c) { create(:collection, name: "C") }

    it "composes for the head collection" do
      described_class.new.perform(c_a.id, [ c_b.id, c_c.id ])
      expect(composer).to have_received(:call).with(c_a)
    end

    it "enqueues EXACTLY ONE follow-up job (not the whole tail)" do
      described_class.new.perform(c_a.id, [ c_b.id, c_c.id ])
      expect(described_class.jobs.size).to eq(1)
    end

    it "passes the head of the tail and the remaining tail to the next job" do
      described_class.new.perform(c_a.id, [ c_b.id, c_c.id ])
      args = described_class.jobs.last["args"]
      expect(args).to eq([ c_b.id, [ c_c.id ] ])
    end

    it "drains the chain across successive perform calls" do
      described_class.new.perform(c_a.id, [ c_b.id, c_c.id ])
      described_class.clear

      described_class.new.perform(c_b.id, [ c_c.id ])
      next_args = described_class.jobs.last["args"]
      expect(next_args).to eq([ c_c.id, [] ])
      described_class.clear

      described_class.new.perform(c_c.id, [])
      expect(described_class.jobs).to be_empty
    end
  end

  describe "#perform — failure semantics" do
    let(:c_a) { create(:collection, name: "A") }
    let(:c_b) { create(:collection, name: "B") }

    it "lets the composer's exception propagate" do
      allow(composer).to receive(:call).and_raise(Vips::Error, "boom")
      expect {
        described_class.new.perform(c_a.id, [ c_b.id ])
      }.to raise_error(Vips::Error, /boom/)
    end

    it "does NOT advance the chain when the composer raises" do
      allow(composer).to receive(:call).and_raise(Vips::Error, "boom")
      begin
        described_class.new.perform(c_a.id, [ c_b.id ])
      rescue Vips::Error
        # expected — we want to assert on the side-effect after the raise
      end
      expect(described_class.jobs).to be_empty
    end
  end

  describe "#perform — deleted-collection edge" do
    let(:c_b) { create(:collection, name: "B") }

    it "no-ops gracefully when the head collection is missing" do
      expect {
        described_class.new.perform(-1, [ c_b.id ])
      }.not_to raise_error
      expect(composer).not_to have_received(:call)
    end

    it "STILL advances the chain after a missing-collection no-op" do
      described_class.new.perform(-1, [ c_b.id ])
      expect(described_class.jobs.size).to eq(1)
      expect(described_class.jobs.last["args"]).to eq([ c_b.id, [] ])
    end
  end
end
