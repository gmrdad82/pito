require "rails_helper"

RSpec.describe BundleVoyageIndexJob, type: :job do
  before do
    allow(Bundles::VoyageIndexer).to receive(:call)
    allow(StackStats::Broadcaster).to receive(:broadcast!)
  end

  it "is enqueued on the :search queue" do
    expect(described_class.new.queue_name).to eq("search")
  end

  it "delegates to Bundles::VoyageIndexer.call with the looked-up Bundle" do
    bundle = create(:bundle)

    expect(Bundles::VoyageIndexer).to receive(:call).with(an_object_having_attributes(id: bundle.id))

    described_class.new.perform(bundle.id)
  end

  it "returns early (no indexer call) when the bundle id does not resolve" do
    expect(Bundles::VoyageIndexer).not_to receive(:call)

    described_class.new.perform(0)
  end

  describe "ensure-block broadcasting" do
    let(:bundle) { create(:bundle) }

    it "broadcasts the immediate stack-stats snapshot" do
      expect(StackStats::Broadcaster).to receive(:broadcast!)

      described_class.new.perform(bundle.id)
    end

    it "enqueues StackStatsBroadcastJob (trailing-edge follow-up)" do
      clear_enqueued_jobs

      described_class.new.perform(bundle.id)

      expect(enqueued_jobs.map { |j| j[:job] }).to include(StackStatsBroadcastJob)
    end

    it "still broadcasts + re-enqueues when the indexer raises" do
      allow(Bundles::VoyageIndexer).to receive(:call).and_raise(StandardError, "boom")
      expect(StackStats::Broadcaster).to receive(:broadcast!)
      clear_enqueued_jobs

      expect {
        described_class.new.perform(bundle.id)
      }.to raise_error(StandardError, "boom")

      expect(enqueued_jobs.map { |j| j[:job] }).to include(StackStatsBroadcastJob)
    end

    it "broadcasts even when the bundle id does not resolve (early return)" do
      expect(StackStats::Broadcaster).to receive(:broadcast!)

      described_class.new.perform(0)
    end
  end

  it "enqueues via ActiveJob with the bundle id" do
    clear_enqueued_jobs

    expect {
      described_class.perform_later(99)
    }.to have_enqueued_job(described_class).with(99)
  end
end
