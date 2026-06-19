# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportVideosJob do
  let(:connection) { create(:youtube_connection) }
  let!(:channel) {
    create(:channel,
           youtube_connection: connection,
           youtube_channel_id: "UCaaa111",
           title: "Alpha Channel",
           handle: "@alpha")
  }

  let(:conversation) { Conversation.create! }
  let(:turn) {
    conversation.turns.create!(
      position: Turn.next_position_for(conversation),
      input_kind: :slash,
      input_text: "/connect"
    )
  }

  # Stub the shared sync service so the job spec exercises ONLY the job's
  # orchestration (run the full sync per channel, aggregate, summarize) — the
  # discover/upsert behavior lives in Pito::Sync::VideoLibrary's own spec.
  let(:library) { instance_double(Pito::Sync::VideoLibrary) }

  def result(imported: 0, updated: 0, deleted: 0, titles: [])
    Pito::Sync::VideoLibrary::Result.new(imported:, updated:, deleted:, titles:)
  end

  before do
    allow(Pito::Sync::VideoLibrary).to receive(:new).and_return(library)
    allow(library).to receive(:sync).and_return(result(imported: 2, updated: 3, deleted: 1, titles: %w[A B X]))
  end

  it "runs the full sync once for each channel" do
    described_class.new.perform(connection.id, turn.id)

    expect(library).to have_received(:sync).once
  end

  it "updates channel last_synced_at" do
    described_class.new.perform(connection.id, turn.id)
    expect(channel.reload.last_synced_at).to be_within(5.seconds).of(Time.current)
  end

  it "emits an enhanced summary reflecting the new/updated/removed counts" do
    described_class.new.perform(connection.id, turn.id)

    event = conversation.events.where(kind: :enhanced).last
    body  = event.payload["body"]
    expect(body).to include("2 new")
    expect(body).to include("3 updated")
    expect(body).to include("1 removed")
  end

  context "across multiple channels" do
    let!(:channel_two) {
      create(:channel,
             youtube_connection: connection,
             youtube_channel_id: "UCbbb222",
             title: "Beta Channel",
             handle: "@beta")
    }

    it "aggregates the per-channel Results into an 'All channels' total" do
      described_class.new.perform(connection.id, turn.id)

      body = conversation.events.where(kind: :enhanced).last.payload["body"]
      # Two channels × (2 new, 3 updated, 1 removed) = 4 / 6 / 2.
      total_label = I18n.t("pito.jobs.import_videos.summary.total_label")
      expect(body).to include(total_label)
      expect(body).to include("4 new")
      expect(body).to include("6 updated")
      expect(body).to include("2 removed")
    end
  end

  context "when nothing changed at all" do
    before do
      allow(library).to receive(:sync).and_return(result)
    end

    it "emits a clear 'nothing new' enhanced message and completes the turn" do
      described_class.new.perform(connection.id, turn.id)

      event = conversation.events.where(kind: :enhanced).last
      expect(event.payload["body"]).to include(
        I18n.t("pito.jobs.import_videos.summary.nothing_new")
      )

      turn.reload
      expect(turn.completed_at).to be_present
    end
  end

  it "resolves the thinking indicator" do
    thinking = Event.create_with_position!(
      conversation: conversation,
      turn: turn,
      kind: :thinking,
      payload: { dictionary: "importing", word_index: 0, started_at: 5.seconds.ago.iso8601 }
    )

    described_class.new.perform(connection.id, turn.id)

    thinking.reload
    expect(thinking.payload["resolved"]).to be(true)
    expect(thinking.payload["elapsed_seconds"]).to be >= 4
  end

  it "marks the turn as completed" do
    described_class.new.perform(connection.id, turn.id)

    turn.reload
    expect(turn.completed_at).to be_present
  end

  it "no-ops when turn is already completed" do
    turn.update!(completed_at: Time.current)

    expect {
      described_class.new.perform(connection.id, turn.id)
    }.not_to change { conversation.events.count }
  end

  it "no-ops when connection is missing" do
    expect {
      described_class.new.perform(0, turn.id)
    }.not_to change { conversation.events.count }
  end

  context "when a channel has no live connection" do
    before { allow(channel).to receive(:youtube_connection).and_return(nil) }

    it "skips the channel but still completes the turn" do
      # Re-find through the same connection scope so the stubbed channel is used.
      allow(Channel).to receive(:where).and_return([ channel ])

      described_class.new.perform(connection.id, turn.id)

      expect(library).not_to have_received(:sync)
      turn.reload
      expect(turn.completed_at).to be_present
    end
  end

  context "on error" do
    before do
      allow(library).to receive(:sync).and_raise(StandardError, "boom")
    end

    it "emits an error event and re-raises" do
      expect {
        described_class.new.perform(connection.id, turn.id)
      }.to raise_error(StandardError, "boom")

      error_event = conversation.events.where(kind: :error).last
      expect(error_event).to be_present
      expect(error_event.payload["detail"]).to eq("boom")
    end

    it "resolves the thinking indicator and completes the turn before re-raising" do
      suppress(StandardError) { described_class.new.perform(connection.id, turn.id) }

      turn.reload
      expect(turn.completed_at).to be_present
    end
  end
end
