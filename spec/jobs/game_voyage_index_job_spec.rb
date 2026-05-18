require "rails_helper"

RSpec.describe GameVoyageIndexJob, type: :job do
  before do
    allow(Games::VoyageIndexer).to receive(:call)
    allow(StackStats::Broadcaster).to receive(:broadcast!)
  end

  it "is enqueued on the :search queue" do
    expect(described_class.new.queue_name).to eq("search")
  end

  it "delegates to Games::VoyageIndexer.call with the looked-up Game" do
    game = create(:game)

    expect(Games::VoyageIndexer).to receive(:call).with(an_object_having_attributes(id: game.id))

    described_class.new.perform(game.id)
  end

  it "returns early (no indexer call) when the game id does not resolve" do
    expect(Games::VoyageIndexer).not_to receive(:call)

    described_class.new.perform(0)
  end

  describe "ensure-block broadcasting" do
    let(:game) { create(:game) }

    it "broadcasts the immediate stack-stats snapshot" do
      expect(StackStats::Broadcaster).to receive(:broadcast!)

      described_class.new.perform(game.id)
    end

    it "enqueues StackStatsBroadcastJob with wait: 1.second (trailing-edge)" do
      clear_enqueued_jobs

      described_class.new.perform(game.id)

      expect(enqueued_jobs.map { |j| j[:job] }).to include(StackStatsBroadcastJob)
    end

    it "still broadcasts + re-enqueues when the indexer raises" do
      allow(Games::VoyageIndexer).to receive(:call).and_raise(StandardError, "boom")
      expect(StackStats::Broadcaster).to receive(:broadcast!)
      clear_enqueued_jobs

      expect {
        described_class.new.perform(game.id)
      }.to raise_error(StandardError, "boom")

      expect(enqueued_jobs.map { |j| j[:job] }).to include(StackStatsBroadcastJob)
    end

    it "broadcasts even when the game id does not resolve (early return)" do
      expect(StackStats::Broadcaster).to receive(:broadcast!)

      described_class.new.perform(0)
    end
  end

  it "enqueues via ActiveJob with the game id" do
    clear_enqueued_jobs

    expect {
      described_class.perform_later(42)
    }.to have_enqueued_job(described_class).with(42)
  end
end
