require "rails_helper"

# Phase 23 §23c — user-triggered `[ sync ]` button on /videos/:slug
# routes through `/syncs/video/:ids` (the bulk-as-foundation
# confirmation framework).
#
# Phase 11i Q7 follow-up — the `[sync]` button on /videos/:slug now
# carries `intent=diff_check`. The POST enqueues `VideoDiffCheckJob`
# directly, bypassing the legacy `BulkSyncJob → VideoSync` indirection
# (which already delegated to `VideoDiffCheckJob` for videos, but went
# through the BulkOperation surface). The legacy (default) intent path
# keeps the existing BulkSyncJob/VideoSync chain so cron callers and
# the MCP `sync_records` tool keep working unchanged.
RSpec.describe "Video sync via [ sync ] button", type: :request do
  let(:user) { create(:user) }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv",
           youtube_connection: create(:youtube_connection, user: user))
  end
  let(:video) { create(:video, channel: channel) }

  describe "GET /syncs/video/:ids?intent=diff_check — confirmation page" do
    it "renders the confirmation screen with the video listed" do
      get syncs_path(type: "video", ids: video.id, intent: "diff_check")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(video.youtube_video_id)
    end

    it "renders the diff-check copy in the lead paragraph" do
      get syncs_path(type: "video", ids: video.id, intent: "diff_check")
      expect(response.body).to include("compare and present any differences for review")
    end
  end

  describe "POST /syncs/video/:ids?intent=diff_check — diff-check dispatch" do
    it "does NOT create a BulkOperation (diff-check skips the bulk surface)" do
      expect {
        post syncs_path(type: "video", ids: video.id, intent: "diff_check")
      }.not_to change(BulkOperation, :count)
    end

    it "does NOT enqueue BulkSyncJob (diff-check bypasses the bulk fan-out)" do
      expect {
        post syncs_path(type: "video", ids: video.id, intent: "diff_check")
      }.not_to change(BulkSyncJob.jobs, :size)
    end

    it "enqueues VideoDiffCheckJob directly with the video id" do
      expect {
        post syncs_path(type: "video", ids: video.id, intent: "diff_check")
      }.to change(VideoDiffCheckJob.jobs, :size).by(1)

      expect(VideoDiffCheckJob.jobs.last["args"]).to eq([ video.id ])
    end

    it "redirects back to the video show page with a notice" do
      post syncs_path(type: "video", ids: video.id, intent: "diff_check")
      expect(response).to redirect_to(video_path(video))
    end
  end

  describe "GET /syncs/video/:ids — legacy (no intent) confirmation page" do
    it "renders the confirmation screen with the video listed" do
      get syncs_path(type: "video", ids: video.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(video.youtube_video_id)
    end
  end

  describe "POST /syncs/video/:ids — legacy (no intent) bulk-sync dispatch" do
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

  describe "VideoSync → VideoDiffCheckJob delegation (legacy bulk path)" do
    it "constantizes VideoSync from the target type" do
      expect("VideoSync".safe_constantize).to eq(VideoSync)
    end

    it "delegates perform to VideoDiffCheckJob" do
      expect_any_instance_of(VideoDiffCheckJob).to receive(:perform).with(video.id)
      VideoSync.new.perform(video.id)
    end
  end

  describe "[sync] link on /videos/:slug" do
    it "carries intent=diff_check so the POST enqueues the diff-check job" do
      get video_path(video)
      expect(response.body).to include("/syncs/video/#{video.id}?intent=diff_check") |
                                include("intent=diff_check")
      # belt-and-braces — the actual params shape
      expect(response.body).to match(/syncs\/video\/#{video.id}[^"]*intent=diff_check/)
    end
  end
end
