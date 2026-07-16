# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightlyReindexJob, type: :job do
  include ActiveJob::TestHelper

  describe "#perform" do
    subject(:job) { described_class.new }

    let!(:game_a)  { create(:game) }
    let!(:game_b)  { create(:game) }
    let!(:channel) { create(:channel) }
    let!(:video_a) { create(:video, channel: channel) }
    let!(:video_b) { create(:video, channel: channel) }

    # Stubbed for every EXISTING example below (games/videos/events fan-out) so
    # they stay focused on their own assertions — the NL sync call itself gets
    # its own dedicated coverage further down.
    before { allow(Pito::Nl::Router).to receive(:sync!) }

    it "enqueues GameEmbedIndexJob for every game" do
      expect {
        job.perform
      }.to have_enqueued_job(GameEmbedIndexJob).with(game_a.id)
         .and have_enqueued_job(GameEmbedIndexJob).with(game_b.id)
    end

    it "enqueues VideoEmbedIndexJob for every video" do
      expect {
        job.perform
      }.to have_enqueued_job(VideoEmbedIndexJob).with(video_a.id)
         .and have_enqueued_job(VideoEmbedIndexJob).with(video_b.id)
    end

    it "enqueues exactly N_games + N_videos index jobs" do
      job.perform
      game_jobs  = enqueued_jobs.count { |j| j["job_class"] == "GameEmbedIndexJob" }
      video_jobs = enqueued_jobs.count { |j| j["job_class"] == "VideoEmbedIndexJob" }

      expect(game_jobs).to eq(Game.count)
      expect(video_jobs).to eq(Video.count)
    end

    it "is a no-op (enqueues nothing) when there are no games or videos" do
      Game.destroy_all
      Video.destroy_all

      job.perform
      expect(enqueued_jobs).to be_empty
    end

    context "events" do
      let!(:nil_embedding_event) { create(:event, kind: "echo") }
      let!(:non_embeddable_event) { create(:event, kind: "thinking") }
      let!(:already_embedded_event) do
        create(:event, kind: "system").tap do |event|
          event.update_columns(embedding: Array.new(768, 0.05), embedded_digest: "digest123")
        end
      end

      before do
        allow(Pito::Embedding::EventIndexer).to receive(:call)
      end

      it "embeds every EMBEDDABLE_KINDS event whose embedding is nil" do
        job.perform
        expect(Pito::Embedding::EventIndexer).to have_received(:call).with(nil_embedding_event)
      end

      it "skips a non-embeddable-kind event even when its embedding is nil" do
        job.perform
        expect(Pito::Embedding::EventIndexer).not_to have_received(:call).with(non_embeddable_event)
      end

      it "skips an event that already carries an embedding" do
        job.perform
        expect(Pito::Embedding::EventIndexer).not_to have_received(:call).with(already_embedded_event)
      end
    end

    # 3.0.1 P11 — the NL router's example cache self-heal. Own `before` block
    # UNDOES the outer stub so these examples exercise the real call.
    context "NL router example cache sync" do
      before { allow(Pito::Nl::Router).to receive(:sync!).and_call_original }

      it "calls Pito::Nl::Router.sync! before enqueuing any game index job" do
        called_sync_before_enqueue = false
        allow(Pito::Nl::Router).to receive(:sync!) do
          called_sync_before_enqueue = enqueued_jobs.none? { |j| j["job_class"] == "GameEmbedIndexJob" }
        end

        job.perform

        expect(called_sync_before_enqueue).to be(true)
      end

      it "does not raise and still runs the games/videos fan-out when sync! raises" do
        allow(Pito::Nl::Router).to receive(:sync!).and_raise(StandardError, "boom")
        allow(Rails.logger).to receive(:warn)

        expect { job.perform }.not_to raise_error
        expect(enqueued_jobs.count { |j| j["job_class"] == "GameEmbedIndexJob" }).to eq(Game.count)
      end

      it "logs a warning naming the failure when sync! raises" do
        allow(Pito::Nl::Router).to receive(:sync!).and_raise(StandardError, "boom")

        expect(Rails.logger).to receive(:warn).with(a_string_including("Pito::Nl::Router.sync!", "StandardError", "boom"))

        job.perform
      end
    end
  end
end
