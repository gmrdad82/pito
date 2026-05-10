require "rails_helper"

# Phase 12 — video schema expansion + edit surface + pre-publish checklist.
# Re-introduces edit / update / publish / schedule / pre_publish_checklist
# actions on top of the post-Path-A2 thin retract.
RSpec.describe "Videos", type: :request do
  describe "GET /videos" do
    it "returns 200" do
      get videos_path
      expect(response).to have_http_status(:ok)
    end

    it "has page title" do
      get videos_path
      expect(response.body).to include("<title>videos ~ pito</title>")
    end

    it "shows empty state when no videos" do
      get videos_path
      expect(response.body).to include("no videos yet")
    end

    context "with videos" do
      let!(:channel) { create(:channel) }
      let!(:video) { create(:video, channel: channel) }
      let!(:stat) { create(:video_stat, video: video, date: Date.current, views: 500, likes: 25, comments: 3) }

      it "displays the video table" do
        get videos_path
        expect(response.body).to include(video.youtube_video_id)
        expect(response.body).to include(channel.channel_url)
        expect(response.body).to include("500")
      end

      it "renders the privacy_status column" do
        get videos_path
        expect(response.body).to include("private")
      end

      it "includes [edit] link on each row" do
        get videos_path
        expect(response.body).to include(edit_video_path(video))
      end

      it "renders the name column header as a server-side sort link" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip == "name" }
        expect(link).not_to be_nil
        expect(link["href"]).to include("sort=id")
      end

      it "exposes `id` in VideosController::ALLOWED_SORTS so server-side sort honors it" do
        expect(VideosController::ALLOWED_SORTS).to include("id" => "videos.id")
      end

      it "renders always-on bulk select checkboxes" do
        get videos_path
        expect(response.body).to include('data-bulk-select-target="checkbox"')
        expect(response.body).to include('data-bulk-select-target="headerCheckbox"')
      end

      # Frame-escape regression guard (2026-05-10). The videos table
      # sits inside `<turbo-frame id="videos-index-table">` so sortable
      # headers can partial-swap. Without `data-turbo-frame="_top"`
      # cascading on the bulk-toolbar actions container, the
      # controller-injected `[open N]` / `[delete N]` links would
      # navigate the click inside that frame — the panes workspace and
      # the deletions confirmation page are full-page surfaces with no
      # matching frame, so Turbo would render "Content missing".
      it "stamps data-turbo-frame=_top on the bulk-toolbar actions container" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        actions = html.css('[data-bulk-select-target="actions"]').first
        expect(actions).not_to be_nil, "expected the bulk-select actions container"
        expect(actions["data-turbo-frame"]).to eq("_top"),
          "bulk-toolbar must escape the videos-index-table frame so [open N] / [delete N] navigate full-page"
      end
    end

    context "JSON format" do
      let!(:channel) { create(:channel) }
      let!(:video) { create(:video, channel: channel, title: "MyVideo") }

      it "returns video list as JSON in the post-12 shape" do
        get videos_path(format: :json)
        json = JSON.parse(response.body)
        expect(json).to be_an(Array)
        row = json.first
        expect(row).to include(
          "id", "youtube_video_id", "channel_id", "channel_url",
          "title", "privacy_status", "published_at",
          "star", "views", "likes", "comments", "watch_time_minutes",
          "last_synced_at", "imported", "trend"
        )
      end
    end
  end

  describe "GET /videos/:id (show)" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel, title: "ShowMe") }

    it "returns 200" do
      get video_path(video)
      expect(response).to have_http_status(:ok)
    end

    it "displays video detail" do
      get video_path(video)
      expect(response.body).to include(video.youtube_video_id)
      expect(response.body).to include("ShowMe")
    end

    it "shows breadcrumb" do
      get video_path(video)
      expect(response.body).to include("video ##{video.id}")
    end

    it "includes [-] delete link in breadcrumb actions" do
      get video_path(video)
      expect(response.body).to include("/deletions/video/#{video.id}")
    end

    it "includes [e] edit link in breadcrumb actions" do
      get video_path(video)
      expect(response.body).to include(edit_video_path(video))
    end

    it "returns 404 for unknown video" do
      get video_path(id: 99999)
      expect(response).to have_http_status(:not_found)
    end

    it "returns detail JSON" do
      get video_path(video, format: :json)
      json = JSON.parse(response.body)
      expect(json).to include("id", "youtube_video_id", "channel_id", "title", "stats")
    end

    context "with project linked" do
      let!(:project) { create(:project, name: "Halo Run") }
      let!(:linked_video) { create(:video, channel: channel, project: project) }

      it "renders a part-of-project link" do
        get video_path(linked_video)
        expect(response.body).to include("part of project")
        expect(response.body).to include("Halo Run")
        expect(response.body).to include(project_path(project))
      end
    end

    context "imported video" do
      let!(:imported_video) { create(:video, :imported, channel: channel) }

      it "shows the imported indicator" do
        get video_path(imported_video)
        expect(response.body).to include("imported")
      end
    end

    context "with last_sync_error" do
      let!(:err_video) { create(:video, :with_sync_error, channel: channel) }

      it "surfaces the youtube sync error" do
        get video_path(err_video)
        expect(response.body).to include("youtube sync failed")
      end
    end
  end

  describe "GET /videos/:id/edit" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel) }
    let!(:project) { create(:project) }

    it "returns 200" do
      get edit_video_path(video)
      expect(response).to have_http_status(:ok)
    end

    it "renders the writable subset of inputs" do
      get edit_video_path(video)
      expect(response.body).to include("video[title]")
      expect(response.body).to include("video[description]")
      expect(response.body).to include("video[tags_csv]")
      expect(response.body).to include("video[category_id]")
      expect(response.body).to include("video[self_declared_made_for_kids]")
      expect(response.body).to include("video[contains_synthetic_media]")
      expect(response.body).to include("video[project_id]")
    end

    it "does NOT render a privacy_status input" do
      get edit_video_path(video)
      expect(response.body).not_to match(/name="video\[privacy_status\]"/)
    end

    it "does NOT render a publish_at input on the edit form (it is a schedule-flow only field)" do
      get edit_video_path(video)
      expect(response.body).not_to match(/name="video\[publish_at\]"/)
    end

    it "renders Studio deep-links for the four Studio-only fields" do
      get edit_video_path(video)
      expect(response.body).to include(video.studio_url)
    end

    it "returns 404 for missing video" do
      get edit_video_path(id: 99999)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /videos/:id (update)" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel, title: "old") }
    let!(:project) { create(:project, name: "P1") }

    before { VideoSyncBack.jobs.clear }

    it "updates title and redirects" do
      patch video_path(video), params: { video: { title: "new title" } }
      expect(response).to redirect_to(video_path(video))
      expect(video.reload.title).to eq("new title")
    end

    it "updates description" do
      patch video_path(video), params: { video: { description: "new desc" } }
      expect(video.reload.description).to eq("new desc")
    end

    it "updates tags from csv input" do
      patch video_path(video), params: { video: { tags_csv: "halo, speedrun" } }
      expect(video.reload.tags).to eq([ "halo", "speedrun" ])
    end

    it "updates category_id" do
      patch video_path(video), params: { video: { category_id: "22" } }
      expect(video.reload.category_id).to eq("22")
    end

    it "updates self_declared_made_for_kids" do
      patch video_path(video), params: { video: { self_declared_made_for_kids: "1" } }
      expect(video.reload.self_declared_made_for_kids).to be(true)
    end

    it "updates contains_synthetic_media" do
      patch video_path(video), params: { video: { contains_synthetic_media: "1" } }
      expect(video.reload.contains_synthetic_media).to be(true)
    end

    it "updates project_id" do
      patch video_path(video), params: { video: { project_id: project.id } }
      expect(video.reload.project_id).to eq(project.id)
    end

    it "enqueues VideoSyncBack once on title change" do
      expect {
        patch video_path(video), params: { video: { title: "new title" } }
      }.to change(VideoSyncBack.jobs, :size).by(1)
    end

    it "JSON request returns 200 with detail JSON" do
      patch video_path(video, format: :json), params: { video: { title: "json title" } }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["title"]).to eq("json title")
    end

    context "validation failures" do
      it "rejects title > 100 chars (422)" do
        patch video_path(video), params: { video: { title: "a" * 101 } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects oversized description (422)" do
        patch video_path(video), params: { video: { description: "\u{1F600}" * 1500 } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects category_id `abc` (422)" do
        patch video_path(video), params: { video: { category_id: "abc" } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "404 for missing video" do
        patch video_path(id: 99999), params: { video: { title: "x" } }
        expect(response).to have_http_status(:not_found)
      end
    end

    context "smuggling guards" do
      it "drops smuggled youtube_video_id silently" do
        patch video_path(video), params: { video: { title: "ok", youtube_video_id: "FAKE_ID" } }
        expect(video.reload.youtube_video_id).not_to eq("FAKE_ID")
      end

      it "drops smuggled channel_id silently" do
        other = create(:channel)
        patch video_path(video), params: { video: { title: "ok", channel_id: other.id } }
        expect(video.reload.channel_id).to eq(channel.id)
      end

      it "drops smuggled etag silently" do
        patch video_path(video), params: { video: { title: "ok", etag: "evil" } }
        expect(video.reload.etag).not_to eq("evil")
      end

      it "drops smuggled last_synced_at silently" do
        patch video_path(video), params: { video: { title: "ok", last_synced_at: Time.current.iso8601 } }
        expect(video.reload.last_synced_at).to be_nil
      end

      it "drops smuggled pre_publish_checked_at silently" do
        ts = Time.current.iso8601
        patch video_path(video), params: { video: { title: "ok", pre_publish_checked_at: ts } }
        expect(video.reload.pre_publish_checked_at).to be_nil
      end

      it "drops smuggled pre_publish_game_ok silently" do
        patch video_path(video), params: { video: { title: "ok", pre_publish_game_ok: "1" } }
        expect(video.reload.pre_publish_game_ok).to be(false)
      end

      it "drops smuggled made_for_kids_effective silently" do
        patch video_path(video), params: { video: { title: "ok", made_for_kids_effective: "1" } }
        expect(video.reload.made_for_kids_effective).to be(false)
      end

      it "drops smuggled last_sync_error silently" do
        patch video_path(video), params: { video: { title: "ok", last_sync_error: "evil" } }
        expect(video.reload.last_sync_error).to be_nil
      end

      # The `update` smuggle guard rejects `privacy_status` in either
      # direction. The forward direction (private → public/unlisted)
      # belongs to `:publish`; the reverse direction (public/unlisted
      # → private) belongs to the dedicated `:unpublish` action.
      # Coverage for the unpublish direction lives in the
      # `PATCH /videos/:id/unpublish` describe block below.
      it "rejects privacy_status in update params (422)" do
        patch video_path(video), params: { video: { privacy_status: "public" } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects publish_at in update params (422)" do
        patch video_path(video), params: { video: { publish_at: 1.day.from_now.iso8601 } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "GET /videos/:id/pre_publish_checklist" do
    let!(:video) { create(:video) }

    it "returns 200" do
      get pre_publish_checklist_video_path(video)
      expect(response).to have_http_status(:ok)
    end

    it "renders the four-checkbox modal" do
      get pre_publish_checklist_video_path(video)
      expect(response.body).to include("pre_publish_game_ok")
      expect(response.body).to include("pre_publish_age_ok")
      expect(response.body).to include("pre_publish_paid_promotion_ok")
      expect(response.body).to include("pre_publish_end_screen_ok")
    end

    it "includes the studio deep-links" do
      get pre_publish_checklist_video_path(video)
      expect(response.body).to include(video.studio_url)
    end

    it "pre-checks boxes whose corresponding boolean is already true" do
      video.update_columns(pre_publish_game_ok: true)
      get pre_publish_checklist_video_path(video)
      # The checkbox renders with `checked` immediately before the `>`
      # closing the input tag (no other `>` between id and the closing
      # angle bracket of the same tag because attribute values escape).
      html = Nokogiri::HTML.fragment(response.body)
      checkbox = html.css('input[type="checkbox"]#video_pre_publish_game_ok').first
      expect(checkbox).not_to be_nil
      expect(checkbox.attributes["checked"]).not_to be_nil
    end

    it "supports the schedule target_action" do
      get pre_publish_checklist_video_path(video, target_action: "schedule")
      expect(response.body).to include("video[publish_at]")
      expect(response.body).to include("confirm schedule")
    end
  end

  describe "PATCH /videos/:id/publish" do
    let!(:video) { create(:video, title: "ok", category_id: "20") }
    let(:complete_params) do
      {
        pre_publish_game_ok: "yes",
        pre_publish_age_ok: "yes",
        pre_publish_paid_promotion_ok: "yes",
        pre_publish_end_screen_ok: "yes",
        target_privacy_status: "public"
      }
    end

    before { VideoSyncBack.jobs.clear }

    it "302 redirects on success with all four yes" do
      patch publish_video_path(video), params: { video: complete_params }
      expect(response).to redirect_to(video_path(video))
      expect(video.reload.privacy_public?).to be(true)
    end

    it "stamps pre_publish_checked_at" do
      patch publish_video_path(video), params: { video: complete_params }
      expect(video.reload.pre_publish_checked_at).to be_within(2.seconds).of(Time.current)
    end

    it "enqueues VideoSyncBack" do
      expect {
        patch publish_video_path(video), params: { video: complete_params }
      }.to change(VideoSyncBack.jobs, :size).by(1)
    end

    it "supports unlisted target" do
      patch publish_video_path(video), params: { video: complete_params.merge(target_privacy_status: "unlisted") }
      expect(video.reload.privacy_unlisted?).to be(true)
    end

    it "422 when any boolean is no" do
      patch publish_video_path(video), params: { video: complete_params.merge(pre_publish_game_ok: "no") }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422 when target_privacy_status missing" do
      params = complete_params.dup
      params.delete(:target_privacy_status)
      patch publish_video_path(video), params: { video: params }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422 when target_privacy_status=private (illegal)" do
      patch publish_video_path(video), params: { video: complete_params.merge(target_privacy_status: "private") }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422 when target_privacy_status=scheduled (use :schedule action)" do
      patch publish_video_path(video), params: { video: complete_params.merge(target_privacy_status: "scheduled") }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422 when source video is already public" do
      already_public = create(:video, :public)
      patch publish_video_path(already_public), params: { video: complete_params }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /videos/:id/schedule" do
    let!(:video) { create(:video, title: "ok", category_id: "20") }
    let(:future) { 1.day.from_now }
    let(:base_params) do
      {
        pre_publish_game_ok: "yes",
        pre_publish_age_ok: "yes",
        pre_publish_paid_promotion_ok: "yes",
        pre_publish_end_screen_ok: "yes",
        publish_at: future.iso8601
      }
    end

    before { VideoSyncBack.jobs.clear }

    it "302 redirects on success" do
      patch schedule_video_path(video), params: { video: base_params }
      expect(response).to redirect_to(video_path(video))
    end

    it "stamps pre_publish_checked_at + sets publish_at + privacy stays private" do
      patch schedule_video_path(video), params: { video: base_params }
      v = video.reload
      expect(v.pre_publish_checked_at).to be_present
      expect(v.publish_at).to be_within(2.seconds).of(future)
      expect(v.privacy_private?).to be(true)
    end

    it "enqueues VideoSyncBack" do
      expect {
        patch schedule_video_path(video), params: { video: base_params }
      }.to change(VideoSyncBack.jobs, :size).by(1)
    end

    it "422 with past publish_at" do
      patch schedule_video_path(video), params: { video: base_params.merge(publish_at: 1.day.ago.iso8601) }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422 when publish_at missing" do
      params = base_params.dup
      params.delete(:publish_at)
      patch schedule_video_path(video), params: { video: params }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422 when any boolean no" do
      patch schedule_video_path(video), params: { video: base_params.merge(pre_publish_age_ok: "no") }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422 when source video already public" do
      already_public = create(:video, :public)
      patch schedule_video_path(already_public), params: { video: base_params }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /videos/:id/unpublish" do
    # Dedicated `public` / `unlisted` → `private` route. Going down
    # is free per Note 1 (no checklist needed), so the privacy_status
    # flip lives outside the smuggle guard's blocklist on `update`.
    let!(:channel) { create(:channel) }

    before { VideoSyncBack.jobs.clear }

    it "flips privacy_status from public → private and redirects" do
      v = create(:video, :public, channel: channel)
      patch unpublish_video_path(v)
      expect(response).to redirect_to(video_path(v))
      expect(v.reload.privacy_private?).to be(true)
    end

    it "flips privacy_status from unlisted → private" do
      v = create(:video, :unlisted, channel: channel)
      patch unpublish_video_path(v)
      expect(v.reload.privacy_private?).to be(true)
    end

    it "enqueues VideoSyncBack on the privacy flip" do
      v = create(:video, :public, channel: channel)
      expect {
        patch unpublish_video_path(v)
      }.to change(VideoSyncBack.jobs, :size).by(1)
    end

    it "JSON request returns 200 with detail JSON" do
      v = create(:video, :public, channel: channel)
      patch unpublish_video_path(v, format: :json)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["privacy_status"]).to eq("private")
    end

    it "422 when source video is already private" do
      v = create(:video, channel: channel) # default privacy_status = :private
      patch unpublish_video_path(v)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "404 for missing video" do
      patch unpublish_video_path(id: 99999)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /videos/:id" do
    let!(:video) { create(:video) }

    it "deletes the video and redirects" do
      expect {
        delete video_path(video)
      }.to change(Video, :count).by(-1)
      expect(response).to redirect_to(videos_path)
    end

    it "JSON returns 204" do
      v = create(:video)
      delete video_path(v, format: :json)
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "GET /videos/panes (multi-pane)" do
    let!(:channel) { create(:channel) }
    let!(:video1) { create(:video, channel: channel) }
    let!(:video2) { create(:video, channel: channel) }

    it "redirects to show when single ID" do
      get panes_videos_path(ids: video1.id)
      expect(response).to redirect_to(video_path(video1))
    end

    it "redirects to index when no IDs" do
      get panes_videos_path(ids: "")
      expect(response).to redirect_to(videos_path)
    end

    it "renders multi-pane view with comma-separated IDs" do
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(video1.youtube_video_id)
      expect(response.body).to include(video2.youtube_video_id)
    end
  end

  describe "GET /videos/:id/stats(.json)" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel) }
    let!(:stat) { create(:video_stat, video: video, date: Date.current, views: 100, likes: 5, comments: 2, watch_time_minutes: 50) }

    it "returns the stats JSON in the pito-shape" do
      get stats_video_path(video, format: :json)
      json = JSON.parse(response.body)
      expect(json).to be_an(Array)
      row = json.first
      expect(row).to include("date", "views", "likes", "comments", "watch_time_minutes")
    end

    it "redirects HTML requests to the video show page" do
      get stats_video_path(video)
      expect(response).to redirect_to(video_path(video))
    end
  end
end
