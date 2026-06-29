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

    it "emits a thinking indicator before the sync work" do
      broadcaster = instance_double(
        Pito::Stream::Broadcaster,
        emit: nil, emit_thinking: nil, resolve_thinking: nil, complete_turn: nil
      )
      allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

      described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)

      expect(broadcaster).to have_received(:emit_thinking).with(
        hash_including(dictionary: :syncing)
      )
    end

    it "resolves the thinking indicator after the sync" do
      broadcaster = instance_double(
        Pito::Stream::Broadcaster,
        emit: nil, emit_thinking: nil, resolve_thinking: nil, complete_turn: nil
      )
      allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

      described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)

      expect(broadcaster).to have_received(:resolve_thinking)
    end

    it "prepends the shimmered intro to the enhanced body" do
      described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)

      body = enhanced_body
      # The intro div with scope label comes first, before the per-channel sync lines.
      expect(body).to include("@pito")
    end

    it "emits an enhanced per-channel summary reflecting the Result counts" do
      described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)

      body = enhanced_body
      expect(body).to include("2 new")
      expect(body).to include("3 updated")
      expect(body).to include("1 removed")
    end

    it "embeds the timestamp slot in the first line (intro div) so HH:MM renders inline" do
      described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)
      body = enhanced_body
      # TS_SLOT must sit INSIDE the first <div>, not before it.
      expect(body).to include(%(<div class="text-fg">#{Pito::Event::BodyComponent::TS_SLOT}))
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

    context "partial-failure isolation: first channel raises, second still synced" do
      # Title "Alpha" sorts before "Pito", so channel_two is the first channel
      # passed to safe_sync. safe_sync rescues its StandardError and returns nil;
      # the second channel (channel / "Pito") must still be synced.
      let!(:channel_two) do
        create(:channel, handle: "@alpha", title: "Alpha", youtube_connection: create(:youtube_connection))
      end
      let(:failing_library) { instance_double(Pito::Sync::VideoLibrary) }

      before do
        allow(Pito::Sync::VideoLibrary).to receive(:new).with(channel_two).and_return(failing_library)
        allow(failing_library).to receive(:sync).and_raise(StandardError, "API timeout")
      end

      it "still calls #sync for the second channel when the first raises" do
        described_class.new.perform([], "all channels", conversation_id: conversation.id)
        expect(library).to have_received(:sync)
      end

      it "does not re-raise when one channel sync fails" do
        expect {
          described_class.new.perform([], "all channels", conversation_id: conversation.id)
        }.not_to raise_error
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

  describe "#perform — error path (thinking resolved, :error emitted)" do
    # Trigger the outer rescue by having the success-path :enhanced emit raise.
    # The :error emit in the rescue block must still succeed.
    let(:broadcaster) do
      instance_double(
        Pito::Stream::Broadcaster,
        emit_thinking: nil, resolve_thinking: nil, complete_turn: nil
      )
    end

    before do
      allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
      allow(broadcaster).to receive(:emit)
        .with(hash_including(kind: :enhanced)).and_raise(StandardError, "cable failure")
      allow(broadcaster).to receive(:emit)
        .with(hash_including(kind: :error)).and_return(nil)
    end

    it "emits an :error event into the conversation" do
      described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)
      expect(broadcaster).to have_received(:emit).with(
        hash_including(kind: :error, payload: hash_including(text: anything))
      )
    end

    it "resolves the thinking indicator on error (no hung spinner)" do
      described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)
      expect(broadcaster).to have_received(:resolve_thinking)
    end

    it "completes the turn on error" do
      described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)
      expect(broadcaster).to have_received(:complete_turn)
    end

    it "does not re-raise (job handles the error gracefully)" do
      expect {
        described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)
      }.not_to raise_error
    end
  end
end
