# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventEmbedJob, type: :job do
  let(:conversation) { create(:conversation) }
  let(:turn) { create(:turn, conversation:) }

  it "runs on the search queue" do
    expect(described_class.new.queue_name).to eq("search")
  end

  it "is a no-op when the turn has vanished" do
    expect(Pito::Embedding::EventIndexer).not_to receive(:call)

    expect { described_class.new.perform(0) }.not_to raise_error
  end

  it "hands every event of the turn to Pito::Embedding::EventIndexer.call, once each" do
    events = create_list(:event, 3, conversation:, turn:)

    events.each do |event|
      expect(Pito::Embedding::EventIndexer).to receive(:call).with(event)
    end

    described_class.new.perform(turn.id)
  end

  it "rescues a single event's embed failure so it can't starve the rest of the turn" do
    events = create_list(:event, 3, conversation:, turn:)

    allow(Pito::Embedding::EventIndexer).to receive(:call).with(events[0]).and_raise(StandardError, "boom")
    events[1..].each do |event|
      expect(Pito::Embedding::EventIndexer).to receive(:call).with(event)
    end

    expect { described_class.new.perform(turn.id) }.not_to raise_error
  end

  describe "enqueued from Pito::Stream::Broadcaster#complete_turn" do
    it "enqueues with the turn id when the broadcaster completes a turn" do
      broadcaster = Pito::Stream::Broadcaster.new(conversation:)

      expect {
        broadcaster.complete_turn(turn:)
      }.to have_enqueued_job(described_class).with(turn.id)
    end
  end
end
