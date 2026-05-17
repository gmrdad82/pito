require "rails_helper"

RSpec.describe "BundleMembers", type: :request do
  let(:bundle) { create(:bundle) }

  describe "POST /bundles/:bundle_id/members" do
    let(:game) { create(:game, :synced, title: "Sekiro") }

    it "adds the game to the bundle and enqueues BundleCoverBuild" do
      BundleCoverBuild.clear
      expect {
        post bundle_members_path(bundle), params: { game_id: game.id }
      }.to change { bundle.reload.bundle_members.count }.by(1)

      expect(response).to redirect_to(bundle_path(bundle))
      enqueued = BundleCoverBuild.jobs.map { |j| j["args"].first }
      expect(enqueued).to include(bundle.id)
    end

    it "rejects duplicate members with a flash alert" do
      bundle.bundle_members.create!(game: game)
      post bundle_members_path(bundle), params: { game_id: game.id }
      expect(response).to redirect_to(bundle_path(bundle))
      follow_redirect!
      expect(response.body).to include("already a member")
    end

    it "redirects with alert when the game is not found" do
      post bundle_members_path(bundle), params: { game_id: 999_999 }
      expect(response).to redirect_to(bundle_path(bundle))
      follow_redirect!
      expect(response.body).to include("game not found")
    end
  end

  describe "DELETE /bundles/:bundle_id/members/:id" do
    let(:game) { create(:game, :synced) }

    it "removes the member and enqueues a cover rebuild" do
      bundle.bundle_members.create!(game: game)

      BundleCoverBuild.clear
      expect {
        delete bundle_member_path(bundle, game)
      }.to change { bundle.reload.bundle_members.count }.by(-1)

      enqueued = BundleCoverBuild.jobs.map { |j| j["args"].first }
      expect(enqueued).to include(bundle.id)
    end

    it "redirects with alert when the member does not exist" do
      delete bundle_member_path(bundle, 999_999)
      expect(response).to redirect_to(bundle_path(bundle))
      follow_redirect!
      expect(response.body).to include("member not found")
    end
  end
end
