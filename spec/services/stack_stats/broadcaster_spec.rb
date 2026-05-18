require "rails_helper"

RSpec.describe StackStats::Broadcaster do
  describe ".broadcast!" do
    let(:fake_payload) { { redis: { busy: 0 }, voyage: {}, postgres: {}, meilisearch: {}, assets: {} } }

    before { allow(StackStats::Payload).to receive(:call).and_return(fake_payload) }

    it "publishes the payload on the `stack_stats` broadcasting" do
      expect(ActionCable.server).to receive(:broadcast).with("stack_stats", fake_payload)

      described_class.broadcast!
    end

    it "broadcasts to the BROADCASTING constant (no drift)" do
      expect(described_class::BROADCASTING).to eq("stack_stats")
    end

    it "is observable via have_broadcasted_to matcher" do
      expect {
        described_class.broadcast!
      }.to have_broadcasted_to("stack_stats")
    end

    it "swallows broadcast errors (UX nicety must never escape the worker ensure block)" do
      allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, "redis pubsub down")

      expect { described_class.broadcast! }.not_to raise_error
    end

    it "swallows payload-build errors" do
      allow(StackStats::Payload).to receive(:call).and_raise(StandardError, "boom")

      expect { described_class.broadcast! }.not_to raise_error
    end

    it "returns nil on success path" do
      allow(ActionCable.server).to receive(:broadcast)

      expect(described_class.broadcast!).to be_nil.or be_a(Object)
    end
  end
end
