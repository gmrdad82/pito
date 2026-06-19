# frozen_string_literal: true

require "rails_helper"

RSpec.describe VideoSyncJob, type: :job do
  let(:connection) { create(:youtube_connection) }
  let!(:channel) do
    create(:channel,
           youtube_connection: connection,
           youtube_channel_id: "UCaaa111",
           handle: "@alpha")
  end

  # Stub the shared sync service so the job spec exercises ONLY the job's
  # orchestration (guards → sync → notify) — the discover/upsert behavior lives
  # in Pito::Sync::VideoLibrary's own spec.
  let(:library) { instance_double(Pito::Sync::VideoLibrary) }
  let(:result) do
    Pito::Sync::VideoLibrary::Result.new(imported: 2, updated: 1, deleted: 0, titles: %w[A B])
  end

  before do
    allow(Pito::Sync::VideoLibrary).to receive(:new).and_return(library)
    allow(library).to receive(:sync).and_return(result)
    allow(Pito::Notifications::Source::VideoSync).to receive(:report!)
  end

  describe "#perform" do
    it "runs the channel's full sync via Pito::Sync::VideoLibrary#sync" do
      described_class.new.perform(channel.id)

      expect(Pito::Sync::VideoLibrary).to have_received(:new).with(channel)
      expect(library).to have_received(:sync)
    end

    it "reports a VideoSync notification with the channel handle and result" do
      described_class.new.perform(channel.id)

      expect(Pito::Notifications::Source::VideoSync).to have_received(:report!)
        .with(scope_label: channel.handle, result: result)
    end

    it "returns early for a missing channel" do
      described_class.new.perform(0)

      expect(library).not_to have_received(:sync)
      expect(Pito::Notifications::Source::VideoSync).not_to have_received(:report!)
    end

    it "returns early when the channel has no connection" do
      orphan = create(:channel, youtube_channel_id: "UCorphan")

      described_class.new.perform(orphan.id)

      expect(library).not_to have_received(:sync)
    end

    it "returns early when the connection needs reauth" do
      reauth_channel = create(:channel,
                              youtube_connection: create(:youtube_connection, :needs_reauth),
                              youtube_channel_id: "UCreauth")

      described_class.new.perform(reauth_channel.id)

      expect(library).not_to have_received(:sync)
    end

    it "rescues and logs a raised error without re-raising" do
      allow(library).to receive(:sync).and_raise(StandardError, "boom")

      expect { described_class.new.perform(channel.id) }.not_to raise_error
    end
  end
end
