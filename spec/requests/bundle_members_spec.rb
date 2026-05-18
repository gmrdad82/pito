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

  # 2026-05-18 — `from_igdb` `[add]` action for IGDB rows in the bundle
  # modal `:bundle_add` omnisearch. The endpoint creates a Game stub
  # with `igdb_id` + `title` pre-seed, enqueues `GameIgdbSync`, and
  # adds the new game as a `BundleMember` — all in one click. When the
  # IGDB id already maps to a local Game, the action behaves like a
  # regular local add (no duplicate Game row, no new sync).
  describe "POST /bundles/:bundle_id/members/from_igdb" do
    it "creates a Game stub, enqueues GameIgdbSync, and adds it to the bundle" do
      GameIgdbSync.clear
      expect {
        post from_igdb_bundle_members_path(bundle),
             params: { igdb_id: 7346, title: "Zelda BotW" }
      }.to change { Game.count }.by(1)
                                 .and change { bundle.reload.bundle_members.count }.by(1)

      created = Game.find_by(igdb_id: 7346)
      expect(created.title).to eq("Zelda BotW")
      expect(GameIgdbSync.jobs.map { |j| j["args"].first }).to include(created.id)
      expect(response).to redirect_to(bundle_path(bundle))
    end

    it "is idempotent when the IGDB id already maps to a local Game (no new Game, no new sync)" do
      existing = create(:game, :synced, igdb_id: 7346, title: "Zelda BotW")
      GameIgdbSync.clear
      expect {
        post from_igdb_bundle_members_path(bundle),
             params: { igdb_id: 7346, title: "Zelda BotW" }
      }.to change { Game.count }.by(0)
                                 .and change { bundle.reload.bundle_members.count }.by(1)

      expect(GameIgdbSync.jobs).to be_empty
      expect(bundle.bundle_members.pluck(:game_id)).to eq([ existing.id ])
    end

    it "rejects an already-member game with a flash alert (no duplicate row)" do
      existing = create(:game, :synced, igdb_id: 7346, title: "Zelda BotW")
      bundle.bundle_members.create!(game_id: existing.id)
      expect {
        post from_igdb_bundle_members_path(bundle),
             params: { igdb_id: 7346, title: "Zelda BotW" }
      }.not_to change { bundle.reload.bundle_members.count }

      follow_redirect!
      expect(response.body).to include("already a member")
    end

    it "rejects an invalid igdb_id (zero / negative / non-numeric) with a flash alert" do
      expect {
        post from_igdb_bundle_members_path(bundle), params: { igdb_id: 0, title: "Whatever" }
      }.not_to change { Game.count }

      follow_redirect!
      expect(response.body).to include("igdb id must be a positive integer")
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
