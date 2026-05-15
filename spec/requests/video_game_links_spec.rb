require "rails_helper"

# Phase 14 §3 — VideoGameLinksController request specs.
#
# Surface:
#   POST   /videos/:video_id/links            create
#   PATCH  /videos/:video_id/links/:id        flip is_primary
#   DELETE /videos/:video_id/links/:id        destroy
#
# Boundary discipline:
#   - is_primary on the wire is "yes"/"no". Boolean smuggling rejected.
#   - Smuggling both `game_id` and `bundle_id` rejected (422).
#   - Duplicate (same video + same target) surfaces as a clean
#     "already linked" flash (master-agent decision #7).
RSpec.describe "VideoGameLinks", type: :request do
  let(:channel) { create(:channel) }
  let(:video)   { create(:video, channel: channel) }
  let(:game)    { create(:game, title: "Sekiro") }
  let(:bundle)  { create(:bundle, name: "Soulslikes") }

  describe "POST /videos/:video_id/links (game)" do
    it "creates a game link with is_primary=no" do
      expect {
        post video_links_path(video),
             params: { link_type: "game", linked_id: game.id, is_primary: "no" }
      }.to change(VideoGameLink, :count).by(1)

      link = VideoGameLink.last
      expect(link.video_id).to eq(video.id)
      expect(link.game_id).to eq(game.id)
      expect(link.bundle_id).to be_nil
      expect(link.is_primary).to be(false)
      expect(response).to redirect_to(edit_video_path(video))
      follow_redirect!
      expect(flash[:notice]).to eq("link added.")
    end

    it "persists is_primary=yes correctly" do
      post video_links_path(video),
           params: { link_type: "game", linked_id: game.id, is_primary: "yes" }
      expect(VideoGameLink.last.is_primary).to be(true)
    end

    it "rejects a duplicate link with a clean 'already linked' flash" do
      create(:video_game_link, video: video, game: game)

      post video_links_path(video),
           params: { link_type: "game", linked_id: game.id }
      follow_redirect!
      expect(flash[:alert]).to eq("already linked.")
    end

    it "rejects a nonexistent linked_id with a clean error" do
      post video_links_path(video),
           params: { link_type: "game", linked_id: 999_999 }
      follow_redirect!
      expect(flash[:alert]).to eq("game not found.")
    end

    it "rejects smuggled bundle_id" do
      post video_links_path(video),
           params: { link_type: "game", linked_id: game.id, bundle_id: bundle.id }
      follow_redirect!
      expect(flash[:alert]).to include("smuggle")
    end

    it "rejects link_type=game without linked_id" do
      post video_links_path(video),
           params: { link_type: "game" }
      follow_redirect!
      expect(flash[:alert]).to include("required")
    end

    it "rejects an unknown link_type" do
      post video_links_path(video),
           params: { link_type: "garbage", linked_id: game.id }
      follow_redirect!
      expect(flash[:alert]).to include("link_type")
    end

    it "stamps Current.user as created_by_user_id" do
      Current.user = User.first || create(:user)
      post video_links_path(video),
           params: { link_type: "game", linked_id: game.id }
      expect(VideoGameLink.last.created_by_user_id).to eq(Current.user.id)
    end
  end

  describe "POST /videos/:video_id/links (bundle)" do
    it "creates a bundle link" do
      expect {
        post video_links_path(video),
             params: { link_type: "bundle", linked_id: bundle.id }
      }.to change(VideoGameLink, :count).by(1)

      link = VideoGameLink.last
      expect(link.bundle_id).to eq(bundle.id)
      expect(link.game_id).to be_nil
      expect(link.link_bundle?).to be(true)
    end

    it "rejects smuggled game_id on a bundle link" do
      post video_links_path(video),
           params: { link_type: "bundle", linked_id: bundle.id, game_id: game.id }
      follow_redirect!
      expect(flash[:alert]).to include("smuggle")
    end
  end

  describe "PATCH /videos/:video_id/links/:id" do
    let!(:link) { create(:video_game_link, video: video, game: game, is_primary: false) }

    it "flips is_primary from false to true with is_primary=yes" do
      patch video_link_path(video, link), params: { is_primary: "yes" }
      expect(link.reload.is_primary).to be(true)
      expect(response).to redirect_to(edit_video_path(video))
    end

    it "flips is_primary back to false" do
      link.update_column(:is_primary, true)
      patch video_link_path(video, link), params: { is_primary: "no" }
      expect(link.reload.is_primary).to be(false)
    end

    it "rejects boolean is_primary smuggling" do
      patch video_link_path(video, link), params: { is_primary: "true" }
      follow_redirect!
      expect(flash[:alert]).to include("yes")
    end

    it "404s on a missing link" do
      patch video_link_path(video, 999_999), params: { is_primary: "yes" }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /videos/:video_id/links/:id" do
    let!(:link) { create(:video_game_link, video: video, game: game) }

    it "destroys the link directly when the controller is hit" do
      # The web UI routes the user through `/deletions/video_game_link/:id`
      # (action screen) — but the controller's destroy still works for
      # programmatic callers (curl, integration testing).
      expect {
        delete video_link_path(video, link)
      }.to change(VideoGameLink, :count).by(-1)
      expect(response).to redirect_to(edit_video_path(video))
    end
  end

  describe "deletion via /deletions action screen" do
    let!(:link) { create(:video_game_link, video: video, game: game) }

    it "GET /deletions/video_game_link/:id returns the action screen" do
      get deletions_path(type: "video_game_link", ids: link.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("delete")
      expect(response.body).to include("video ##{link.video_id}")
    end

    it "POST /deletions/video_game_link/:id enqueues the bulk delete job" do
      expect {
        post deletions_path(type: "video_game_link", ids: link.id)
      }.to change(BulkOperation, :count).by(1)
    end
  end

  describe "multi-user permissions" do
    it "User B can remove a link User A created (ADR 0003)" do
      # Phase 29 — Unit A2. The mandatory-2FA gate bounces any
      # not-yet-TOTP-configured authenticated user to the enrollment
      # page. User B is signed in via cookie for the DELETE, so it must
      # be TOTP-configured to reach the action.
      user_a = create(:user, :totp_enabled)
      user_b = create(:user, :totp_enabled)

      Current.user = user_a
      post video_links_path(video),
           params: { link_type: "game", linked_id: game.id }
      link = VideoGameLink.last

      Current.user = user_b
      sign_in_as(user_b)

      expect {
        delete video_link_path(video, link)
      }.to change(VideoGameLink, :count).by(-1)
    end
  end
end
