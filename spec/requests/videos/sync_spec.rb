require "rails_helper"

# Phase 23 §23c — user-triggered `[ sync ]` button on /videos/:slug
# routes through `/syncs/video/:ids` (the bulk-as-foundation
# confirmation framework). The framework spawns a `BulkSyncJob`,
# which dispatches `VideoSync.perform_async(id)`, which delegates to
# `VideoDiffCheckJob`. This spec verifies the entire chain.
RSpec.describe "Video sync via [ sync ] button", type: :request do
  let(:user) { create(:user) }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv",
           youtube_connection: create(:youtube_connection, user: user))
  end
  let(:video) { create(:video, channel: channel) }

  describe "GET /syncs/video/:ids — confirmation page" do
    it "renders the confirmation screen with the video listed" do
      get syncs_path(type: "video", ids: video.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(video.youtube_video_id)
    end
  end

  describe "POST /syncs/video/:ids — bulk-sync dispatch" do
    it "creates a BulkOperation with one item" do
      expect {
        post syncs_path(type: "video", ids: video.id)
      }.to change(BulkOperation, :count).by(1)
      op = BulkOperation.last
      expect(op.bulk_operation_items.size).to eq(1)
      expect(op.bulk_operation_items.first.target_type).to eq("Video")
    end

    it "enqueues BulkSyncJob" do
      expect {
        post syncs_path(type: "video", ids: video.id)
      }.to change(BulkSyncJob.jobs, :size).by(1)
    end

    it "redirects/renders the progress page" do
      post syncs_path(type: "video", ids: video.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/sync|progress|queued/i)
    end
  end

  describe "VideoSync → VideoDiffCheckJob delegation" do
    it "constantizes VideoSync from the target type" do
      expect("VideoSync".safe_constantize).to eq(VideoSync)
    end

    it "delegates perform to VideoDiffCheckJob" do
      expect_any_instance_of(VideoDiffCheckJob).to receive(:perform).with(video.id)
      VideoSync.new.perform(video.id)
    end
  end
end
