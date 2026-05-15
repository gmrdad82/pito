require "rails_helper"

# Phase 11i Q7 follow-up — the `[ sync ]` button on /videos/:slug flips
# an `intent=diff_check` flag on the `/syncs/:type/:ids` flow. The POST
# enqueues `VideoDiffCheckJob` directly — NOT `BulkSyncJob` — so the
# user-triggered sync produces a diff dialog rather than a cache
# overwrite.
#
# Unit A0 (beta-2) trimmed this spec. The channel diff-check intent was
# retired when the channel became a strictly read-only mirror —
# `ChannelDiffCheckJob` and the `"channel" => ...` entry in
# `SyncsController::DIFF_CHECK_JOBS` are gone. A channel `[ sync ]` now
# only ever runs the `overwrite` intent (`ChannelSync` via
# `BulkSyncJob`), covered by the "channel sync runs the overwrite path"
# example below and by `spec/requests/syncs_spec.rb`.
#
# Legacy `intent=overwrite` (default) is covered by the existing
# `spec/requests/syncs_spec.rb` and stays untouched here.
RSpec.describe "Syncs — diff-check intent", type: :request do
  describe "GET /syncs/:type/:ids?intent=diff_check (confirmation page)" do
    context "video" do
      let!(:video) { create(:video) }

      it "returns 200 and renders the diff-check lead copy" do
        get syncs_path(type: "video", ids: video.id, intent: "diff_check")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("compare and present any differences for review")
      end

      it "does NOT render the legacy overwrite lead copy" do
        get syncs_path(type: "video", ids: video.id, intent: "diff_check")
        expect(response.body).not_to include("just kicking off the sync")
      end

      it "preserves the intent param in the form action URL" do
        get syncs_path(type: "video", ids: video.id, intent: "diff_check")
        expect(response.body).to include("action=\"/syncs/video/#{video.id}?intent=diff_check\"")
      end

      it "renders a non-destructive [sync] submit button" do
        get syncs_path(type: "video", ids: video.id, intent: "diff_check")
        expect(response.body).not_to match(/<button[^>]*btn-danger/)
        expect(response.body).to include("[sync]")
      end
    end

    context "unknown intent value" do
      let!(:video) { create(:video) }

      it "falls back to overwrite lead copy (intent is a hint, not an authz boundary)" do
        get syncs_path(type: "video", ids: video.id, intent: "bogus")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("just kicking off the sync")
        expect(response.body).not_to include("compare and present any differences")
      end
    end
  end

  describe "POST /syncs/:type/:ids?intent=diff_check (enqueue diff-check)" do
    context "video" do
      let!(:video) { create(:video) }

      it "enqueues a VideoDiffCheckJob with the video id" do
        expect {
          post syncs_path(type: "video", ids: video.id, intent: "diff_check")
        }.to change(VideoDiffCheckJob.jobs, :size).by(1)

        enqueued = VideoDiffCheckJob.jobs.last
        expect(enqueued["args"]).to eq([ video.id ])
      end

      it "does NOT create a BulkOperation row (no overwrite path)" do
        expect {
          post syncs_path(type: "video", ids: video.id, intent: "diff_check")
        }.not_to change(BulkOperation, :count)
      end

      it "does NOT enqueue BulkSyncJob or VideoSync" do
        expect {
          post syncs_path(type: "video", ids: video.id, intent: "diff_check")
        }.to change(BulkSyncJob.jobs, :size).by(0)
          .and change(VideoSync.jobs, :size).by(0)
      end

      it "redirects to the video show page with a flash notice" do
        post syncs_path(type: "video", ids: video.id, intent: "diff_check")
        expect(response).to redirect_to(video_path(video))
        follow_redirect!
        expect(response.body).to include("sync queued")
      end

      context "multiple video ids" do
        let!(:video_b) { create(:video) }

        it "enqueues one VideoDiffCheckJob per id" do
          expect {
            post syncs_path(type: "video", ids: "#{video.id},#{video_b.id}", intent: "diff_check")
          }.to change(VideoDiffCheckJob.jobs, :size).by(2)
        end

        it "redirects to the videos index (cancel path) when more than one id" do
          post syncs_path(type: "video", ids: "#{video.id},#{video_b.id}", intent: "diff_check")
          expect(response).to redirect_to(videos_path)
        end
      end
    end

    # Unit A0 — `channel` is no longer a diff-check type. Even with an
    # `intent=diff_check` query forced onto the URL, a channel sync
    # cannot enqueue a diff-check job (the type was removed from
    # `DIFF_CHECK_JOBS`); the controller falls back to a clear alert.
    context "channel — diff-check is no longer supported" do
      let!(:channel) { create(:channel) }

      it "redirects with an alert (no crash) and enqueues nothing" do
        post syncs_path(type: "channel", ids: channel.id, intent: "diff_check")
        # `create_diff_check` falls back to the cancel path (the
        # channels index) with a clear alert when the type has no
        # diff-check job registered.
        expect(response).to redirect_to(channels_path)
        follow_redirect!
        expect(response.body).to include("diff-check unsupported")
      end
    end

    context "type that does not support diff-check" do
      let!(:project) { create(:project) }

      it "redirects to the type index with an alert (no crash)" do
        post syncs_path(type: "project", ids: project.id, intent: "diff_check")
        expect(response).to redirect_to(projects_path)
        follow_redirect!
        expect(response.body).to include("diff-check unsupported")
      end

      it "does NOT enqueue any diff-check job" do
        expect {
          post syncs_path(type: "project", ids: project.id, intent: "diff_check")
        }.to change(VideoDiffCheckJob.jobs, :size).by(0)
      end
    end

    context "missing record" do
      it "redirects to the videos index with an alert (Confirmable guard)" do
        post syncs_path(type: "video", ids: "99999", intent: "diff_check")
        expect(response).to redirect_to(videos_path)
      end
    end
  end

  describe "POST /syncs/:type/:ids?intent=diff_check (JSON)" do
    let!(:video) { create(:video) }

    it "returns the diff-check enqueued envelope with operation_id nil" do
      post syncs_path(type: "video", ids: video.id, intent: "diff_check", format: :json)

      expect(response).to have_http_status(:accepted)
      expect(response.media_type).to eq("application/json")

      data = JSON.parse(response.body)
      expect(data["mode"]).to eq("enqueued")
      expect(data["intent"]).to eq("diff_check")
      expect(data["total"]).to eq(1)
      expect(data["enqueued"]).to eq([ video.id ])
      expect(data["operation_id"]).to be_nil
      expect(data["message"]).to match(/Diff check queued/i)
    end

    it "returns 422 JSON for an unknown type" do
      post syncs_path(type: "invalid", ids: "1", intent: "diff_check", format: :json)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "channel sync runs the overwrite path" do
    let!(:channel) { create(:channel) }

    # Unit A0 — a channel is a read-only mirror; the only sync path for
    # a channel is the legacy `overwrite` intent (the one-way
    # YouTube → pito cache pull via `BulkSyncJob → ChannelSync`).
    it "uses the legacy BulkSyncJob path for a channel (no diff-check)" do
      expect {
        post syncs_path(type: "channel", ids: channel.id)
      }.to change(BulkSyncJob.jobs, :size).by(1)
        .and change(BulkOperation, :count).by(1)
    end
  end
end
