# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncVideosJob, type: :job do
  let(:conversation) { Conversation.create! }
  let(:library)      { instance_double(Pito::Sync::VideoLibrary) }

  let!(:connection) { create(:youtube_connection) }
  let!(:channel)    { create(:channel, handle: "@pito", title: "Pito", youtube_connection: connection) }

  def result(imported: 0, updated: 0, deleted: 0, titles: [])
    Pito::Sync::VideoLibrary::Result.new(imported:, updated:, deleted:, titles:)
  end

  before do
    allow(Pito::Sync::VideoLibrary).to receive(:new).and_return(library)
    allow(library).to receive(:sync).and_return(result(imported: 2, updated: 3, deleted: 1))
    allow(library).to receive(:refresh).and_return(result(updated: 5))
  end

  def enhanced_body
    conversation.events.where(kind: :enhanced).last.payload["body"]
  end

  describe "#perform — whole-channel sync" do
    it "runs Pito::Sync::VideoLibrary#sync for the scoped channel" do
      described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)
      expect(Pito::Sync::VideoLibrary).to have_received(:new).with(channel)
      expect(library).to have_received(:sync)
    end

    it "emits an enhanced per-channel summary reflecting the Result counts" do
      described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)

      body = enhanced_body
      expect(body).to include("2 new")
      expect(body).to include("3 updated")
      expect(body).to include("1 removed")
    end

    it "omits the 'All channels' total for a single channel" do
      described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)
      expect(enhanced_body).not_to include(I18n.t("pito.jobs.import_videos.summary.total_label"))
    end

    it "completes the turn" do
      described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)
      expect(conversation.turns.last.completed_at).to be_present
    end

    context "across multiple channels" do
      let!(:channel_two) do
        create(:channel, handle: "@beta", title: "Beta", youtube_connection: create(:youtube_connection))
      end

      it "adds an 'All channels' total aggregating the per-channel Results" do
        described_class.new.perform([], "all channels", conversation_id: conversation.id)

        body = enhanced_body
        # Two channels × (2 new, 3 updated, 1 removed) = 4 / 6 / 2.
        expect(body).to include(I18n.t("pito.jobs.import_videos.summary.total_label"))
        expect(body).to include("4 new")
        expect(body).to include("6 updated")
        expect(body).to include("2 removed")
      end
    end

    context "when a scoped channel needs reauth" do
      before { connection.update!(needs_reauth: true) }

      it "emits a reauth line instead of syncing the channel" do
        described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)

        expect(library).not_to have_received(:sync)
        expect(enhanced_body).to include("needs reauth")
      end
    end

    context "when nothing is in scope" do
      it "emits the 'nothing new' line" do
        described_class.new.perform([ 999_999 ], "@gone", conversation_id: conversation.id)
        expect(enhanced_body).to include(I18n.t("pito.jobs.import_videos.summary.nothing_new"))
      end
    end
  end

  describe "#perform — targeted refresh (video_ids)" do
    let!(:video_one) { create(:video, channel:, youtube_video_id: "vid_one") }
    let!(:video_two) { create(:video, channel:, youtube_video_id: "vid_two") }

    it "calls #refresh with the channel's youtube ids (not #sync)" do
      described_class.new.perform(
        [ channel.id ], "@pito",
        conversation_id: conversation.id, video_ids: [ video_one.id, video_two.id ]
      )

      expect(library).to have_received(:refresh).with(match_array(%w[vid_one vid_two]))
      expect(library).not_to have_received(:sync)
    end

    it "emits an enhanced summary reflecting the refreshed count" do
      described_class.new.perform(
        [ channel.id ], "@pito",
        conversation_id: conversation.id, video_ids: [ video_one.id ]
      )
      expect(enhanced_body).to include("5 updated")
    end

    it "completes the turn" do
      described_class.new.perform(
        [ channel.id ], "@pito",
        conversation_id: conversation.id, video_ids: [ video_one.id ]
      )
      expect(conversation.turns.last.completed_at).to be_present
    end
  end

  describe "#perform — without a conversation" do
    it "does nothing and does not raise" do
      expect {
        described_class.new.perform([ channel.id ], "@pito")
      }.not_to change { conversation.turns.count }
      expect(library).not_to have_received(:sync)
    end
  end
end
