# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatImportVideosJob, type: :job do
  let!(:connection) { create(:youtube_connection) }
  let!(:channel)    { create(:channel, handle: "@pito", youtube_connection: connection) }

  before do
    allow(NightlyVideoSyncJob).to receive(:perform_now)
  end

  describe "#perform" do
    context "without a conversation_id" do
      it "does not run any import" do
        described_class.new.perform([ channel.id ], "@pito")
        expect(NightlyVideoSyncJob).not_to have_received(:perform_now)
      end
    end

    context "with a conversation_id" do
      let!(:conversation) { Conversation.singleton }
      let(:broadcaster)   { instance_double(Pito::Stream::Broadcaster, emit: nil, complete_turn: nil) }

      before do
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
      end

      it "emits one message for a healthy channel and completes the turn" do
        described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)

        expect(broadcaster).to have_received(:emit).once
        expect(broadcaster).to have_received(:complete_turn).once
      end

      it "emits each per-channel result as an :enhanced event" do
        described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)

        expect(broadcaster).to have_received(:emit) do |args|
          expect(args[:kind]).to eq(:enhanced)
        end
      end

      it "calls NightlyVideoSyncJob.perform_now for a healthy channel" do
        described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)

        expect(NightlyVideoSyncJob).to have_received(:perform_now).with(channel.id)
      end

      it "includes the channel at_handle in the emitted message text" do
        described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)

        expect(broadcaster).to have_received(:emit) do |args|
          expect(args[:payload]["text"]).to include("@pito")
        end
      end

      it "emits a message for all channels when channel_ids is empty" do
        described_class.new.perform([], "all channels", conversation_id: conversation.id)

        expect(broadcaster).to have_received(:emit).once
        expect(NightlyVideoSyncJob).to have_received(:perform_now).with(channel.id)
      end

      context "with a needs_reauth channel" do
        let!(:reauth_connection) { create(:youtube_connection, :needs_reauth) }
        let!(:reauth_channel)    { create(:channel, handle: "@locked", youtube_connection: reauth_connection) }

        it "emits a reauth message and does NOT call NightlyVideoSyncJob" do
          described_class.new.perform(
            [ reauth_channel.id ],
            "@locked",
            conversation_id: conversation.id
          )

          expect(NightlyVideoSyncJob).not_to have_received(:perform_now)
          expect(broadcaster).to have_received(:emit).once do |args|
            expect(args[:payload]["text"]).to include("reauth")
            expect(args[:payload]["text"]).to include("@locked")
          end
          expect(broadcaster).to have_received(:complete_turn).once
        end
      end

      context "with multiple channels (one healthy, one needs_reauth)" do
        let!(:reauth_connection) { create(:youtube_connection, :needs_reauth) }
        let!(:reauth_channel)    { create(:channel, handle: "@locked", youtube_connection: reauth_connection) }

        it "emits one message per channel (N channels → N messages)" do
          described_class.new.perform(
            [ channel.id, reauth_channel.id ],
            "two channels",
            conversation_id: conversation.id
          )

          expect(broadcaster).to have_received(:emit).twice
          expect(broadcaster).to have_received(:complete_turn).once
        end

        it "only calls NightlyVideoSyncJob for the healthy channel" do
          described_class.new.perform(
            [ channel.id, reauth_channel.id ],
            "two channels",
            conversation_id: conversation.id
          )

          expect(NightlyVideoSyncJob).to have_received(:perform_now).with(channel.id)
          expect(NightlyVideoSyncJob).not_to have_received(:perform_now).with(reauth_channel.id)
        end
      end
    end
  end
end
